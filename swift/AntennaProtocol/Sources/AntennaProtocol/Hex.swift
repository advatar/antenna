import Foundation

public enum Hex {
    public static func strip0x(_ s: String) -> String {
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            return String(s.dropFirst(2))
        }
        return s
    }

    public static func toData(_ hex: String) throws -> Data {
        let clean = strip0x(hex)
        guard clean.count % 2 == 0 else { throw MBP2PError.invalidHex("odd length") }
        var data = Data()
        data.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            let byteStr = clean[idx..<next]
            guard let byte = UInt8(byteStr, radix: 16) else { throw MBP2PError.invalidHex(String(byteStr)) }
            data.append(byte)
            idx = next
        }
        return data
    }

    public static func fromData(_ data: Data, prefix0x: Bool = true) -> String {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        return prefix0x ? "0x" + hex : hex
    }
}
