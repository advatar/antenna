import XCTest
@testable import AntennaProtocol

final class EventIdVectorsTests: XCTestCase {

    func loadFixture(_ name: String) throws -> Data {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "json") ??
                      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            throw NSError(domain: "AntennaProtocolTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name).json"])
        }
        return try Data(contentsOf: url)
    }

    func testPrimaryPostEventId() throws {
        let data = try loadFixture("event.post.primary")
        let event = try MBEvent.fromJSON(data: data)
        let got = try event.computeEventId()
        XCTAssertEqual(got.lowercased(), "0x3722033095f71954949abc38c48f392a9d18644084078cb710a87c8890f3eb01")
    }

    func testAnonHelpEventId() throws {
        let data = try loadFixture("event.helprequest.anon")
        let event = try MBEvent.fromJSON(data: data)
        let got = try event.computeEventId()
        XCTAssertEqual(got.lowercased(), "0x29bf715be4959553f7e2c02ebfa47a39ef1d72bf130255a0d3e33217e1a155e2")
    }
}
