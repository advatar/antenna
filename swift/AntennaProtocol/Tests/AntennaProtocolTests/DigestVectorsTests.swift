import XCTest
@testable import AntennaProtocol

final class DigestVectorsTests: XCTestCase {

    func testEIP191DigestVector1() throws {
        let msg = try Hex.toData("0x3722033095f71954949abc38c48f392a9d18644084078cb710a87c8890f3eb01")
        let digest = EIP191.digest(message: msg)
        XCTAssertEqual(Hex.fromData(digest).lowercased(),
                       "0xcde0eb6d83bcdc11a1f869fdf383589a6b625ef4e6cd3a92dbbd63eefd966a69")
    }

    func testEIP712DigestVector1() throws {
        let eventHash = try Hex.toData("0x3722033095f71954949abc38c48f392a9d18644084078cb710a87c8890f3eb01")
        let verifyingContract = try Hex.toData("0x8004A818BFB912233c491871b3d84c89A494BD9e")
        let domain = try EIP712.Domain(name: "AntennaEvent", version: "1", chainId: 11155111, verifyingContract: verifyingContract)

        let domainSep = EIP712.domainSeparator(domain)
        XCTAssertEqual(Hex.fromData(domainSep).lowercased(),
                       "0xf701ec819b26db5a8372aecce0146a0938d6260b236ed90d0bb22d99987c10ee")

        let structHash = try EIP712.structHashMBEvent(eventHashBytes32: eventHash)
        XCTAssertEqual(Hex.fromData(structHash).lowercased(),
                       "0xda6e202bb53df8e919d63b6ecab363212e3662c65e7428640e2c736612a76fe0")

        let digest = try EIP712.digest(domainSeparator: domainSep, structHash: structHash)
        XCTAssertEqual(Hex.fromData(digest).lowercased(),
                       "0x545936ab250e638f7a5b1f875e750455d0a08d2fbc0808f708efb446cdb401f4")
    }
}
