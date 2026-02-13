import Foundation

public enum EIP191 {
    /// Compute the EIP-191 `personal_sign` digest over an arbitrary byte message.
    ///
    /// digest = keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
    public static func digest(message: Data) -> Data {
        let prefix = "\u{0019}Ethereum Signed Message:\n\(message.count)"
        var data = Data(prefix.utf8)
        data.append(message)
        return Keccak256.hash(data)
    }

    /// Convenience for signing a bytes32 payload (common for signing event hashes).
    public static func digestBytes32(_ bytes32: Data) throws -> Data {
        guard bytes32.count == 32 else { throw MBP2PError.invalidJSON("bytes32 must be 32 bytes") }
        return digest(message: bytes32)
    }
}
