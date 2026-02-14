import Foundation

public struct MBRelayPublishOutcome: Sendable {
    public let relayURL: URL
    public let endpointURL: URL

    public init(relayURL: URL, endpointURL: URL) {
        self.relayURL = relayURL
        self.endpointURL = endpointURL
    }
}

public enum MBRelayClientError: LocalizedError, Sendable {
    case noRelayCandidates
    case publishFailed(attempts: [String])

    public var errorDescription: String? {
        switch self {
        case .noRelayCandidates:
            return "No relay candidates available."
        case .publishFailed(let attempts):
            if attempts.isEmpty {
                return "Failed to publish envelope to all relay candidates."
            }
            return "Failed to publish envelope to all relay candidates: \(attempts.joined(separator: " | "))"
        }
    }
}

private struct MBRelayListPayload: Decodable {
    let relays: [String]
}

public enum MBRelayClient {
    public static func discoverRelays(
        seeds: [URL],
        requestTimeout: TimeInterval = 1.5
    ) async -> [URL] {
        let normalizedSeeds = normalizeRelayURLs(seeds)
        guard !normalizedSeeds.isEmpty else {
            return []
        }

        var mergedByKey: [String: URL] = [:]
        for seed in normalizedSeeds {
            mergedByKey[urlKey(seed)] = seed
        }

        await withTaskGroup(of: [URL].self) { group in
            for seed in normalizedSeeds {
                group.addTask {
                    await fetchRelayList(from: seed, requestTimeout: requestTimeout)
                }
            }

            for await discovered in group {
                for relay in discovered {
                    mergedByKey[urlKey(relay)] = relay
                }
            }
        }

        return mergedByKey
            .values
            .sorted { $0.absoluteString < $1.absoluteString }
    }

    public static func publishEnvelope(
        _ envelope: MBEnvelope,
        primaryRelay: URL,
        bootstrapRelays: [URL],
        discover: Bool = true,
        requestTimeout: TimeInterval = 4.0
    ) async throws -> MBRelayPublishOutcome {
        let seeds = normalizeRelayURLs([primaryRelay] + bootstrapRelays)
        let relayCandidates: [URL]
        if discover {
            let discovered = await discoverRelays(seeds: seeds, requestTimeout: min(2.5, requestTimeout))
            relayCandidates = normalizeRelayURLs(discovered + seeds)
        } else {
            relayCandidates = seeds
        }
        return try await publishEnvelope(
            envelope,
            relayCandidates: relayCandidates,
            requestTimeout: requestTimeout
        )
    }

    public static func publishEnvelope(
        _ envelope: MBEnvelope,
        relayCandidates: [URL],
        requestTimeout: TimeInterval = 4.0
    ) async throws -> MBRelayPublishOutcome {
        let candidates = normalizeRelayURLs(relayCandidates)
        guard !candidates.isEmpty else {
            throw MBRelayClientError.noRelayCandidates
        }

        let body = try MBJSON.encode(envelope)
        let session = URLSession.shared
        var attempts: [String] = []

        for relay in candidates {
            for endpoint in publishEndpointCandidates(for: relay) {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = requestTimeout
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (_, response) = try await session.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200...299).contains(status) {
                        return MBRelayPublishOutcome(relayURL: relay, endpointURL: endpoint)
                    }
                    attempts.append("\(endpoint.absoluteString) -> HTTP \(status)")
                } catch {
                    attempts.append("\(endpoint.absoluteString) -> \(error.localizedDescription)")
                }
            }
        }

        throw MBRelayClientError.publishFailed(attempts: attempts)
    }

    static func normalizeRelayURLs(_ urls: [URL]) -> [URL] {
        var mergedByKey: [String: URL] = [:]
        for url in urls {
            guard let normalized = normalizeRelayURL(url) else { continue }
            mergedByKey[urlKey(normalized)] = normalized
        }
        return mergedByKey
            .values
            .sorted { $0.absoluteString < $1.absoluteString }
    }

    static func publishEndpointCandidates(for relay: URL) -> [URL] {
        let normalized = normalizeRelayURL(relay) ?? relay
        var endpoints: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                endpoints.append(url)
            }
        }

        if normalized.path.isEmpty || normalized.path == "/" {
            append(normalized.appendingPathComponent("v1").appendingPathComponent("publish"))
            append(normalized)
        } else {
            append(normalized)
            append(rootRelayURL(for: normalized).appendingPathComponent("v1").appendingPathComponent("publish"))
        }
        return endpoints
    }

    private static func fetchRelayList(from relay: URL, requestTimeout: TimeInterval) async -> [URL] {
        let endpoint = discoveryEndpoint(for: relay)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            if let payload = try? JSONDecoder().decode(MBRelayListPayload.self, from: data) {
                return payload.relays.compactMap(parseRelayURL)
            }
            if let relays = try? JSONDecoder().decode([String].self, from: data) {
                return relays.compactMap(parseRelayURL)
            }
            return []
        } catch {
            return []
        }
    }

    private static func discoveryEndpoint(for relay: URL) -> URL {
        let normalized = normalizeRelayURL(relay) ?? relay
        if normalized.path.isEmpty || normalized.path == "/" {
            return normalized
                .appendingPathComponent("v1")
                .appendingPathComponent("discovery")
                .appendingPathComponent("relays")
        }
        return normalized
    }

    private static func parseRelayURL(_ raw: String) -> URL? {
        guard let parsed = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return normalizeRelayURL(parsed)
    }

    private static func normalizeRelayURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        components.scheme = scheme
        components.fragment = nil
        components.query = nil

        let path = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = path.isEmpty ? "" : "/\(path)"
        return components.url
    }

    private static func rootRelayURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.percentEncodedPath = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func urlKey(_ url: URL) -> String {
        guard let normalized = normalizeRelayURL(url) else {
            return url.absoluteString
        }
        return normalized.absoluteString
    }
}
