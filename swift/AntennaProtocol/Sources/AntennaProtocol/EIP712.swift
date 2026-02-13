import Foundation

public enum EIP712 {
    // Matches the repository’s interop vectors (see python reference).
    private static let domainType = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    private static let eventType = "MBEvent(bytes32 eventHash)"

    public struct Domain {
        public let name: String
        public let version: String
        public let chainId: UInt64
        public let verifyingContract: Data // 20 bytes

        public init(name: String, version: String, chainId: UInt64, verifyingContract: Data) throws {
            guard verifyingContract.count == 20 else { throw MBP2PError.invalidHex("verifyingContract must be 20 bytes") }
            self.name = name
            self.version = version
            self.chainId = chainId
            self.verifyingContract = verifyingContract
        }
    }

    public static func domainSeparator(_ domain: Domain) -> Data {
        let typeHash = Keccak256.hash(Data(domainType.utf8))
        let nameHash = Keccak256.hash(Data(domain.name.utf8))
        let versionHash = Keccak256.hash(Data(domain.version.utf8))

        var enc = Data()
        enc.append(typeHash)
        enc.append(pad32(nameHash))
        enc.append(pad32(versionHash))
        enc.append(abiEncodeUInt256(domain.chainId))
        enc.append(abiEncodeAddress(domain.verifyingContract))
        return Keccak256.hash(enc)
    }

    public static func structHashMBEvent(eventHashBytes32: Data) throws -> Data {
        guard eventHashBytes32.count == 32 else { throw MBP2PError.invalidHex("eventHash must be 32 bytes") }
        let typeHash = Keccak256.hash(Data(eventType.utf8))
        var enc = Data()
        enc.append(typeHash)
        enc.append(eventHashBytes32)
        return Keccak256.hash(enc)
    }

    public static func digest(domainSeparator: Data, structHash: Data) throws -> Data {
        guard domainSeparator.count == 32, structHash.count == 32 else {
            throw MBP2PError.invalidJSON("domainSeparator/structHash must be 32 bytes")
        }
        var data = Data([0x19, 0x01])
        data.append(domainSeparator)
        data.append(structHash)
        return Keccak256.hash(data)
    }

    // MARK: - ABI helpers (EIP-712 encoding profile)

    private static func pad32(_ data: Data) -> Data {
        if data.count == 32 { return data }
        if data.count > 32 { return data.suffix(32) }
        var out = Data(repeating: 0, count: 32 - data.count)
        out.append(data)
        return out
    }

    private static func abiEncodeUInt256(_ x: UInt64) -> Data {
        var out = Data(repeating: 0, count: 24)
        var v = x.bigEndian
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        return out // 32 bytes total
    }

    private static func abiEncodeAddress(_ addr20: Data) -> Data {
        var out = Data(repeating: 0, count: 12)
        out.append(addr20)
        return out
    }
}
