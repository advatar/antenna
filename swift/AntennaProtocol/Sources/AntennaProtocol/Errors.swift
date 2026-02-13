import Foundation

public enum MBP2PError: Error, LocalizedError {
    case invalidJSON(String)
    case unsupportedNumber(String)
    case canonicalizationError(String)
    case invalidHex(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let s): return "Invalid JSON: \(s)"
        case .unsupportedNumber(let s): return "Unsupported number for canonicalization: \(s)"
        case .canonicalizationError(let s): return "Canonicalization error: \(s)"
        case .invalidHex(let s): return "Invalid hex: \(s)"
        }
    }
}
