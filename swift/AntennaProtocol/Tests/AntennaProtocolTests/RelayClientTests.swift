import XCTest
@testable import AntennaProtocol

final class RelayClientTests: XCTestCase {
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
}
