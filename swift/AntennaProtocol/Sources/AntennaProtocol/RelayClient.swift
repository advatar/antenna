import Foundation
import CryptoKit

public struct MBRelayPublishOutcome: Sendable {
    public let relayURL: URL
    public let endpointURL: URL

    public init(relayURL: URL, endpointURL: URL) {
        self.relayURL = relayURL
        self.endpointURL = endpointURL
    }
}

public struct MBRelayStoredEnvelope: Decodable, Sendable {
    public let receivedAtMilliseconds: Int64
    public let envelope: MBEnvelope

    enum CodingKeys: String, CodingKey {
        case receivedAtMilliseconds = "received_at_ms"
        case envelope
    }

    public init(receivedAtMilliseconds: Int64, envelope: MBEnvelope) {
        self.receivedAtMilliseconds = receivedAtMilliseconds
        self.envelope = envelope
    }
}

public actor MBRelaySubscriptionHandle: Sendable {
    private var task: Task<Void, Never>?

    fileprivate init(task: Task<Void, Never>) {
        self.task = task
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

public enum MBRelayClientError: LocalizedError, Sendable {
    case noRelayCandidates
    case noContentCandidates
    case invalidTopic(String)
    case invalidSHA256(String)
    case publishFailed(attempts: [String])
    case fetchEventsFailed(attempts: [String])
    case contentFetchFailed(attempts: [String])
    case contentIntegrityFailed(expectedSHA256: String, actualSHA256: String)

    public var errorDescription: String? {
        switch self {
        case .noRelayCandidates:
            return "No relay candidates available."
        case .noContentCandidates:
            return "No content URL candidates available."
        case .invalidTopic(let topic):
            return "Invalid relay topic: \(topic)"
        case .invalidSHA256(let value):
            return "Invalid SHA-256 digest: \(value)"
        case .publishFailed(let attempts):
            if attempts.isEmpty {
                return "Failed to publish envelope to all relay candidates."
            }
            return "Failed to publish envelope to all relay candidates: \(attempts.joined(separator: " | "))"
        case .fetchEventsFailed(let attempts):
            if attempts.isEmpty {
                return "Failed to fetch topic events from all relay candidates."
            }
            return "Failed to fetch topic events from all relay candidates: \(attempts.joined(separator: " | "))"
        case .contentFetchFailed(let attempts):
            if attempts.isEmpty {
                return "Failed to fetch content from all URL candidates."
            }
            return "Failed to fetch content from all URL candidates: \(attempts.joined(separator: " | "))"
        case .contentIntegrityFailed(let expectedSHA256, let actualSHA256):
            return "Fetched content failed SHA-256 verification (expected \(expectedSHA256), got \(actualSHA256))."
        }
    }
}

private struct MBRelayListPayload: Decodable {
    let relays: [String]
}

private struct MBRelayEventsPayload: Decodable {
    let events: [MBRelayStoredEnvelope]
}

public enum MBRelayClient {
    public static let canonicalRelayURL = URL(string: "https://ground.zerok.cloud")!

    public static func discoverRelays(
        seeds: [URL],
        requestTimeout: TimeInterval = 1.5
    ) async -> [URL] {
        let normalizedSeeds = relayCandidatesWithCanonical(seeds)
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
        let seeds = relayCandidatesWithCanonical([primaryRelay] + bootstrapRelays)
        let relayCandidates: [URL]
        if discover {
            let discovered = await discoverRelays(seeds: seeds, requestTimeout: min(2.5, requestTimeout))
            relayCandidates = relayCandidatesWithCanonical(discovered + seeds)
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
        let candidates = relayCandidatesWithCanonical(relayCandidates)
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

    public static func fetchTopicEvents(
        topic: String,
        primaryRelay: URL,
        bootstrapRelays: [URL],
        discover: Bool = true,
        sinceMilliseconds: Int64 = 0,
        limit: Int = 100,
        requestTimeout: TimeInterval = 4.0
    ) async throws -> [MBRelayStoredEnvelope] {
        let seeds = relayCandidatesWithCanonical([primaryRelay] + bootstrapRelays)
        let relayCandidates: [URL]
        if discover {
            let discovered = await discoverRelays(seeds: seeds, requestTimeout: min(2.5, requestTimeout))
            relayCandidates = relayCandidatesWithCanonical(discovered + seeds)
        } else {
            relayCandidates = seeds
        }
        return try await fetchTopicEvents(
            topic: topic,
            relayCandidates: relayCandidates,
            sinceMilliseconds: sinceMilliseconds,
            limit: limit,
            requestTimeout: requestTimeout
        )
    }

    public static func fetchTopicEvents(
        topic: String,
        relayCandidates: [URL],
        sinceMilliseconds: Int64 = 0,
        limit: Int = 100,
        requestTimeout: TimeInterval = 4.0
    ) async throws -> [MBRelayStoredEnvelope] {
        let normalizedTopic = try validatedTopic(topic)
        let candidates = relayCandidatesWithCanonical(relayCandidates)
        guard !candidates.isEmpty else {
            throw MBRelayClientError.noRelayCandidates
        }

        let session = URLSession.shared
        var attempts: [String] = []
        let clampedLimit = max(1, min(limit, 500))
        let clampedSince = max(0, sinceMilliseconds)
        let decoder = JSONDecoder()

        for relay in candidates {
            for endpoint in eventsEndpointCandidates(
                for: relay,
                topic: normalizedTopic,
                sinceMilliseconds: clampedSince,
                limit: clampedLimit
            ) {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "GET"
                    request.timeoutInterval = requestTimeout
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (data, response) = try await session.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(status) else {
                        attempts.append("\(endpoint.absoluteString) -> HTTP \(status)")
                        continue
                    }

                    if let payload = try? decoder.decode(MBRelayEventsPayload.self, from: data) {
                        return sortStoredEvents(payload.events)
                    }
                    if let events = try? decoder.decode([MBRelayStoredEnvelope].self, from: data) {
                        return sortStoredEvents(events)
                    }
                    attempts.append("\(endpoint.absoluteString) -> invalid response shape")
                } catch {
                    attempts.append("\(endpoint.absoluteString) -> \(error.localizedDescription)")
                }
            }
        }

        throw MBRelayClientError.fetchEventsFailed(attempts: attempts)
    }

    public static func subscribeToTopic(
        topic: String,
        primaryRelay: URL,
        bootstrapRelays: [URL],
        discover: Bool = true,
        sinceMilliseconds: Int64 = 0,
        limit: Int = 200,
        pollInterval: TimeInterval = 1.5,
        requestTimeout: TimeInterval = 4.0,
        onEvent: @escaping @Sendable (MBRelayStoredEnvelope) -> Void
    ) async throws -> MBRelaySubscriptionHandle {
        let seeds = relayCandidatesWithCanonical([primaryRelay] + bootstrapRelays)
        let relayCandidates: [URL]
        if discover {
            let discovered = await discoverRelays(seeds: seeds, requestTimeout: min(2.5, requestTimeout))
            relayCandidates = relayCandidatesWithCanonical(discovered + seeds)
        } else {
            relayCandidates = seeds
        }
        return try await subscribeToTopic(
            topic: topic,
            relayCandidates: relayCandidates,
            sinceMilliseconds: sinceMilliseconds,
            limit: limit,
            pollInterval: pollInterval,
            requestTimeout: requestTimeout,
            onEvent: onEvent
        )
    }

    public static func subscribeToTopic(
        topic: String,
        relayCandidates: [URL],
        sinceMilliseconds: Int64 = 0,
        limit: Int = 200,
        pollInterval: TimeInterval = 1.5,
        requestTimeout: TimeInterval = 4.0,
        onEvent: @escaping @Sendable (MBRelayStoredEnvelope) -> Void
    ) async throws -> MBRelaySubscriptionHandle {
        let normalizedTopic = try validatedTopic(topic)
        let candidates = relayCandidatesWithCanonical(relayCandidates)
        guard !candidates.isEmpty else {
            throw MBRelayClientError.noRelayCandidates
        }

        let clampedLimit = max(1, min(limit, 500))
        let pollIntervalNanoseconds = UInt64(max(0.2, pollInterval) * 1_000_000_000)

        let task = Task.detached(priority: .utility) {
            var cursor = max(0, sinceMilliseconds)
            var deliveredAtCursor = Set<String>()

            while !Task.isCancelled {
                do {
                    let fetchSince = max(0, cursor - 1)
                    let events = try await fetchTopicEvents(
                        topic: normalizedTopic,
                        relayCandidates: candidates,
                        sinceMilliseconds: fetchSince,
                        limit: clampedLimit,
                        requestTimeout: requestTimeout
                    )
                    for entry in events {
                        let key = eventDeliveryKey(for: entry)
                        if entry.receivedAtMilliseconds < cursor {
                            continue
                        }
                        if entry.receivedAtMilliseconds == cursor {
                            guard deliveredAtCursor.insert(key).inserted else { continue }
                        } else {
                            cursor = entry.receivedAtMilliseconds
                            deliveredAtCursor = [key]
                        }
                        onEvent(entry)
                    }
                } catch {
                    // Polling continues through transient relay/network failures.
                }

                if Task.isCancelled {
                    break
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
        return MBRelaySubscriptionHandle(task: task)
    }

    public static func fetchContentAddressed(
        sha256Hex: String,
        primaryRelay: URL,
        bootstrapRelays: [URL],
        discover: Bool = true,
        requestTimeout: TimeInterval = 8.0
    ) async throws -> Data {
        let seeds = relayCandidatesWithCanonical([primaryRelay] + bootstrapRelays)
        let relayCandidates: [URL]
        if discover {
            let discovered = await discoverRelays(seeds: seeds, requestTimeout: min(2.5, requestTimeout))
            relayCandidates = relayCandidatesWithCanonical(discovered + seeds)
        } else {
            relayCandidates = seeds
        }
        return try await fetchContentAddressed(
            sha256Hex: sha256Hex,
            relayCandidates: relayCandidates,
            requestTimeout: requestTimeout
        )
    }

    public static func fetchContentAddressed(
        sha256Hex: String,
        relayCandidates: [URL],
        requestTimeout: TimeInterval = 8.0
    ) async throws -> Data {
        let normalizedDigest = try normalizedSHA256Digest(sha256Hex)
        let candidates = relayCandidatesWithCanonical(relayCandidates)
        guard !candidates.isEmpty else {
            throw MBRelayClientError.noRelayCandidates
        }

        var contentURLs: [URL] = []
        for relay in candidates {
            contentURLs.append(contentsOf: contentEndpointCandidates(for: relay, sha256Hex: normalizedDigest))
        }
        return try await fetchContentAddressed(
            sha256Hex: normalizedDigest,
            contentURLCandidates: contentURLs,
            requestTimeout: requestTimeout
        )
    }

    public static func fetchContentAddressed(
        sha256Hex: String,
        contentURLCandidates: [URL],
        requestTimeout: TimeInterval = 8.0
    ) async throws -> Data {
        let normalizedDigest = try normalizedSHA256Digest(sha256Hex)
        let candidates = normalizeRequestURLs(contentURLCandidates)
        guard !candidates.isEmpty else {
            throw MBRelayClientError.noContentCandidates
        }

        var attempts: [String] = []
        var integrityMismatch: String?
        let session = URLSession.shared

        for candidate in candidates {
            do {
                var request = URLRequest(url: candidate)
                request.httpMethod = "GET"
                request.timeoutInterval = requestTimeout

                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status) else {
                    attempts.append("\(candidate.absoluteString) -> HTTP \(status)")
                    continue
                }

                let digest = sha256DigestHex(data)
                guard digest == normalizedDigest else {
                    integrityMismatch = digest
                    attempts.append("\(candidate.absoluteString) -> digest mismatch")
                    continue
                }
                return data
            } catch {
                attempts.append("\(candidate.absoluteString) -> \(error.localizedDescription)")
            }
        }

        if let actualDigest = integrityMismatch {
            throw MBRelayClientError.contentIntegrityFailed(
                expectedSHA256: normalizedDigest,
                actualSHA256: actualDigest
            )
        }
        throw MBRelayClientError.contentFetchFailed(attempts: attempts)
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

    static func relayCandidatesWithCanonical(_ urls: [URL]) -> [URL] {
        normalizeRelayURLs(urls + [canonicalRelayURL])
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

    static func eventsEndpointCandidates(
        for relay: URL,
        topic: String,
        sinceMilliseconds: Int64,
        limit: Int
    ) -> [URL] {
        let normalized = normalizeRelayURL(relay) ?? relay
        var baseEndpoints: [URL] = []
        var seen = Set<String>()

        func appendBase(_ url: URL) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                baseEndpoints.append(url)
            }
        }

        if normalized.path.isEmpty || normalized.path == "/" {
            appendBase(normalized.appendingPathComponent("v1").appendingPathComponent("events"))
        } else {
            appendBase(normalized)
            appendBase(rootRelayURL(for: normalized).appendingPathComponent("v1").appendingPathComponent("events"))
        }

        let queryItems = [
            URLQueryItem(name: "topic", value: topic),
            URLQueryItem(name: "since_ms", value: String(max(0, sinceMilliseconds))),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 500))))
        ]
        return baseEndpoints.compactMap { appendQueryItems(to: $0, queryItems: queryItems) }
    }

    static func contentEndpointCandidates(for relay: URL, sha256Hex: String) -> [URL] {
        let normalized = normalizeRelayURL(relay) ?? relay
        let digest = (try? normalizedSHA256Digest(sha256Hex)) ?? sha256Hex.lowercased()
        var endpoints: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                endpoints.append(url)
            }
        }

        func appendWithDigest(_ base: URL) {
            append(base.appendingPathComponent(digest))
        }

        if normalized.path.isEmpty || normalized.path == "/" {
            appendWithDigest(normalized.appendingPathComponent("v1").appendingPathComponent("content"))
            appendWithDigest(normalized.appendingPathComponent("content"))
            appendWithDigest(normalized.appendingPathComponent("v1").appendingPathComponent("artifacts"))
            appendWithDigest(normalized.appendingPathComponent("artifacts"))
        } else {
            appendWithDigest(normalized)
            let root = rootRelayURL(for: normalized)
            appendWithDigest(root.appendingPathComponent("v1").appendingPathComponent("content"))
            appendWithDigest(root.appendingPathComponent("content"))
            appendWithDigest(root.appendingPathComponent("v1").appendingPathComponent("artifacts"))
            appendWithDigest(root.appendingPathComponent("artifacts"))
        }
        return endpoints
    }

    private static func sortStoredEvents(_ events: [MBRelayStoredEnvelope]) -> [MBRelayStoredEnvelope] {
        events.sorted { lhs, rhs in
            if lhs.receivedAtMilliseconds == rhs.receivedAtMilliseconds {
                return eventDeliveryKey(for: lhs) < eventDeliveryKey(for: rhs)
            }
            return lhs.receivedAtMilliseconds < rhs.receivedAtMilliseconds
        }
    }

    private static func eventDeliveryKey(for entry: MBRelayStoredEnvelope) -> String {
        if let eventID = entry.envelope.event.id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventID.isEmpty {
            return eventID
        }
        if let encoded = try? MBJSON.encode(entry.envelope) {
            return "sha256:\(sha256DigestHex(encoded))"
        }
        return "\(entry.receivedAtMilliseconds):\(entry.envelope.topic):\(entry.envelope.event.createdAt)"
    }

    private static func appendQueryItems(to url: URL, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = queryItems
        return components.url
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

    private static func normalizeRequestURLs(_ urls: [URL]) -> [URL] {
        var mergedByKey: [String: URL] = [:]
        for url in urls {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                continue
            }
            mergedByKey[url.absoluteString] = url
        }
        return mergedByKey
            .values
            .sorted { $0.absoluteString < $1.absoluteString }
    }

    private static func validatedTopic(_ topic: String) throws -> String {
        let normalized = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MBRelayClientError.invalidTopic(topic)
        }
        return normalized
    }

    private static func normalizedSHA256Digest(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let stripped: String
        if trimmed.hasPrefix("sha256:") {
            stripped = String(trimmed.dropFirst("sha256:".count))
        } else {
            stripped = trimmed
        }
        guard stripped.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw MBRelayClientError.invalidSHA256(value)
        }
        return stripped
    }

    private static func sha256DigestHex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
