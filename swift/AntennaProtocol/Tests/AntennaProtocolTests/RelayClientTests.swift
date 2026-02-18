import XCTest
import CryptoKit
@testable import AntennaProtocol

final class RelayClientTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testNormalizeRelayURLsDedupesAndCleans() throws {
        let urls = [
            URL(string: "https://relay.example.com/")!,
            URL(string: "https://relay.example.com")!,
            URL(string: "https://relay.example.com/?q=1")!,
            URL(string: "http://relay-two.example.com/v1/publish")!
        ]
        let normalized = MBRelayClient.normalizeRelayURLs(urls)
        XCTAssertEqual(normalized.count, 2)
        XCTAssertTrue(normalized.contains(URL(string: "https://relay.example.com")!))
        XCTAssertTrue(normalized.contains(URL(string: "http://relay-two.example.com/v1/publish")!))
    }

    func testRelayCandidatesAlwaysIncludeCanonicalRelay() throws {
        let candidates = MBRelayClient.relayCandidatesWithCanonical([])
        XCTAssertEqual(candidates, [URL(string: "https://ground.zerok.cloud")!])
    }

    func testRelayCandidatesWithCanonicalDedupesCanonicalInput() throws {
        let candidates = MBRelayClient.relayCandidatesWithCanonical([
            URL(string: "https://ground.zerok.cloud/")!
        ])
        XCTAssertEqual(candidates, [URL(string: "https://ground.zerok.cloud")!])
    }

    func testPublishEndpointCandidatesIncludeFallbacks() throws {
        let root = URL(string: "https://relay.example.com")!
        let rootEndpoints = MBRelayClient.publishEndpointCandidates(for: root)
        XCTAssertEqual(
            rootEndpoints.map(\.absoluteString),
            [
                "https://relay.example.com/v1/publish",
                "https://relay.example.com"
            ]
        )

        let explicit = URL(string: "https://relay.example.com/custom/publish")!
        let explicitEndpoints = MBRelayClient.publishEndpointCandidates(for: explicit)
        XCTAssertEqual(
            explicitEndpoints.map(\.absoluteString),
            [
                "https://relay.example.com/custom/publish",
                "https://relay.example.com/v1/publish"
            ]
        )
    }

    func testEventsEndpointCandidatesIncludeFallbacks() throws {
        let topic = "mb/v1/help/ai.antenna.eth"
        let root = URL(string: "https://relay.example.com")!
        let rootEndpoints = MBRelayClient.eventsEndpointCandidates(
            for: root,
            topic: topic,
            sinceMilliseconds: 100,
            limit: 50
        )
        XCTAssertEqual(rootEndpoints.count, 1)
        XCTAssertEqual(rootEndpoints.first?.path, "/v1/events")
        XCTAssertEqual(URLComponents(url: rootEndpoints[0], resolvingAgainstBaseURL: false)?.queryItems?.count, 3)

        let explicit = URL(string: "https://relay.example.com/custom/events")!
        let explicitEndpoints = MBRelayClient.eventsEndpointCandidates(
            for: explicit,
            topic: topic,
            sinceMilliseconds: 100,
            limit: 50
        )
        XCTAssertEqual(
            explicitEndpoints.map(\.path),
            [
                "/custom/events",
                "/v1/events"
            ]
        )
    }

    func testContentEndpointCandidatesIncludeFallbacks() throws {
        let digest = String(repeating: "a", count: 64)
        let root = URL(string: "https://relay.example.com")!
        let rootEndpoints = MBRelayClient.contentEndpointCandidates(for: root, sha256Hex: digest)
        XCTAssertEqual(
            rootEndpoints.map(\.path),
            [
                "/v1/content/\(digest)",
                "/content/\(digest)",
                "/v1/artifacts/\(digest)",
                "/artifacts/\(digest)"
            ]
        )

        let explicit = URL(string: "https://relay.example.com/v1/content")!
        let explicitEndpoints = MBRelayClient.contentEndpointCandidates(for: explicit, sha256Hex: digest)
        XCTAssertEqual(
            explicitEndpoints.map(\.path),
            [
                "/v1/content/\(digest)",
                "/content/\(digest)",
                "/v1/artifacts/\(digest)",
                "/artifacts/\(digest)"
            ]
        )
    }

    func testFetchTopicEventsDecodesRelayResponse() async throws {
        let relay = URL(string: "https://relay.example.com")!
        let topic = "mb/v1/help/ai.antenna.eth"
        let endpoint = try XCTUnwrap(
            MBRelayClient.eventsEndpointCandidates(
                for: relay,
                topic: topic,
                sinceMilliseconds: 0,
                limit: 100
            ).first
        )

        let envelope = sampleEnvelope(topic: topic, text: "hello")
        let responseData = try makeEventsResponseData(
            topic: topic,
            events: [
                MBRelayStoredEnvelope(receivedAtMilliseconds: 1234, envelope: envelope)
            ]
        )
        StubURLProtocol.setHandler(for: endpoint) { _ in
            (200, ["Content-Type": "application/json"], responseData)
        }

        let events = try await MBRelayClient.fetchTopicEvents(
            topic: topic,
            relayCandidates: [relay],
            sinceMilliseconds: 0,
            limit: 100,
            requestTimeout: 0.5
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].receivedAtMilliseconds, 1234)
        XCTAssertEqual(events[0].envelope.topic, topic)
        XCTAssertEqual(events[0].envelope.event.parts.first?.text, "hello")
    }

    func testSubscribeToTopicDeliversEventAndCanCancel() async throws {
        let relay = URL(string: "https://relay.example.com")!
        let topic = "mb/v1/help/ai.antenna.eth"
        let endpoint = try XCTUnwrap(
            MBRelayClient.eventsEndpointCandidates(
                for: relay,
                topic: topic,
                sinceMilliseconds: 0,
                limit: 10
            ).first
        )

        let envelope = sampleEnvelope(topic: topic, text: "hello-subscribe")
        let delivered = expectation(description: "event delivered")
        let counter = LockedCounter()
        let receivedCount = LockedCounter()

        StubURLProtocol.setHandler(for: endpoint) { _ in
            if counter.increment() == 1 {
                let data = try makeEventsResponseData(
                    topic: topic,
                    events: [MBRelayStoredEnvelope(receivedAtMilliseconds: 42, envelope: envelope)]
                )
                return (200, ["Content-Type": "application/json"], data)
            }
            let data = try makeEventsResponseData(topic: topic, events: [])
            return (200, ["Content-Type": "application/json"], data)
        }

        let handle = try await MBRelayClient.subscribeToTopic(
            topic: topic,
            relayCandidates: [relay],
            sinceMilliseconds: 0,
            limit: 10,
            pollInterval: 0.05,
            requestTimeout: 0.5
        ) { _ in
            if receivedCount.increment() == 1 {
                delivered.fulfill()
            }
        }

        await fulfillment(of: [delivered], timeout: 1.0)
        await handle.cancel()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(receivedCount.value, 1)
    }

    func testFetchContentAddressedVerifiesDigest() async throws {
        let contentURL = URL(string: "https://relay.example.com/content/demo")!
        let payload = Data("artifact-bytes".utf8)
        let digest = sha256Hex(payload)
        StubURLProtocol.setHandler(for: contentURL) { _ in
            (200, [:], payload)
        }

        let fetched = try await MBRelayClient.fetchContentAddressed(
            sha256Hex: digest,
            contentURLCandidates: [contentURL],
            requestTimeout: 0.5
        )
        XCTAssertEqual(fetched, payload)
    }

    func testFetchContentAddressedReportsIntegrityMismatch() async throws {
        let contentURL = URL(string: "https://relay.example.com/content/demo")!
        let expectedPayload = Data("expected".utf8)
        let mismatchPayload = Data("mismatch".utf8)
        let digest = sha256Hex(expectedPayload)
        StubURLProtocol.setHandler(for: contentURL) { _ in
            (200, [:], mismatchPayload)
        }

        do {
            _ = try await MBRelayClient.fetchContentAddressed(
                sha256Hex: digest,
                contentURLCandidates: [contentURL],
                requestTimeout: 0.5
            )
            XCTFail("Expected content integrity mismatch")
        } catch let error as MBRelayClientError {
            switch error {
            case .contentIntegrityFailed(let expected, let actual):
                XCTAssertEqual(expected, digest)
                XCTAssertEqual(actual, sha256Hex(mismatchPayload))
            default:
                XCTFail("Expected contentIntegrityFailed, got \(error)")
            }
        }
    }
}

private func sampleEnvelope(topic: String, text: String) -> MBEnvelope {
    MBEnvelope(
        topic: topic,
        event: MBEvent(
            kind: "post",
            category: "social",
            author: MBAuthor(type: "anon", anonKey: "tester"),
            createdAt: "2026-02-18T00:00:00Z",
            parts: [MBPart(kind: "text", text: text)]
        )
    )
}

private func makeEventsResponseData(topic: String, events: [MBRelayStoredEnvelope]) throws -> Data {
    let response = RelayEventsFixtureResponse(
        ok: true,
        topic: topic,
        events: events.map {
            RelayEventsFixtureStoredEnvelope(received_at_ms: $0.receivedAtMilliseconds, envelope: $0.envelope)
        }
    )
    return try JSONEncoder().encode(response)
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private struct RelayEventsFixtureResponse: Encodable {
    let ok: Bool
    let topic: String
    let events: [RelayEventsFixtureStoredEnvelope]
}

private struct RelayEventsFixtureStoredEnvelope: Encodable {
    let received_at_ms: Int64
    let envelope: MBEnvelope
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storedValue += 1
        return storedValue
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

private final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, headers: [String: String], data: Data)

    private static let state = StubURLProtocolState()

    static func setHandler(for url: URL, handler: @escaping Handler) {
        state.setHandler(for: url.absoluteString, handler: handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler = Self.state.handler(for: url.absoluteString)

        do {
            let result: (statusCode: Int, headers: [String: String], data: Data)
            if let handler {
                result = try handler(request)
            } else {
                result = (404, [:], Data())
            }

            guard let response = HTTPURLResponse(
                url: url,
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StubURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: StubURLProtocol.Handler] = [:]

    func setHandler(for url: String, handler: @escaping StubURLProtocol.Handler) {
        lock.lock()
        handlers[url] = handler
        lock.unlock()
    }

    func handler(for url: String) -> StubURLProtocol.Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[url]
    }

    func reset() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }
}
