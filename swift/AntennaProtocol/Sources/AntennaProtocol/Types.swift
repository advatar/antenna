import Foundation

// MARK: - Core types

public struct MBEnvelope: Codable {
    public var type: String
    public var topic: String
    public var event: MBEvent

    public init(type: String = "antenna.envelope.v1", topic: String, event: MBEvent) {
        self.type = type
        self.topic = topic
        self.event = event
    }
}

public struct MBAuthor: Codable {
    public var type: String  // "erc8004" | "ens" | "anon"
    public var agentRegistry: String?
    public var agentId: Int?
    public var ens: String?
    public var anonKey: String?

    public init(type: String, agentRegistry: String? = nil, agentId: Int? = nil, ens: String? = nil, anonKey: String? = nil) {
        self.type = type
        self.agentRegistry = agentRegistry
        self.agentId = agentId
        self.ens = ens
        self.anonKey = anonKey
    }
}

public struct MBAuth: Codable {
    public var type: String   // "eip191" | "eip712" | "anonSig"
    public var payload: [String: CodableValue]

    public init(type: String, payload: [String: CodableValue]) {
        self.type = type
        self.payload = payload
    }
}

/// Antenna Part shape (stable for MBP2P events; do not assume A2A's evolving Part discriminators).
public struct MBPart: Codable {
    public var kind: String   // "text" | "file" | "data"
    public var text: String?
    public var url: String?
    public var bytesBase64: String?
    public var mediaType: String?
    public var data: CodableValue?

    public init(kind: String, text: String? = nil, url: String? = nil, bytesBase64: String? = nil, mediaType: String? = nil, data: CodableValue? = nil) {
        self.kind = kind
        self.text = text
        self.url = url
        self.bytesBase64 = bytesBase64
        self.mediaType = mediaType
        self.data = data
    }
}

public struct MBEvent: Codable {
    public var type: String
    public var id: String?
    public var kind: String
    public var category: String
    public var thread: String?
    public var parents: [String]
    public var author: MBAuthor
    public var createdAt: String
    public var parts: [MBPart]
    public var extensions: [String]
    public var metadata: CodableValue?
    public var auth: MBAuth?

    public init(
        type: String = "antenna.event.v1",
        id: String? = nil,
        kind: String,
        category: String,
        thread: String? = nil,
        parents: [String] = [],
        author: MBAuthor,
        createdAt: String,
        parts: [MBPart],
        extensions: [String] = [],
        metadata: CodableValue? = nil,
        auth: MBAuth? = nil
    ) {
        self.type = type
        self.id = id
        self.kind = kind
        self.category = category
        self.thread = thread
        self.parents = parents
        self.author = author
        self.createdAt = createdAt
        self.parts = parts
        self.extensions = extensions
        self.metadata = metadata
        self.auth = auth
    }
}

// MARK: - JSON helpers

public enum MBJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MBP2PError.invalidJSON(String(describing: error))
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            let enc = JSONEncoder()
            // Do NOT use .prettyPrinted; encoding here is not used for canonicalization.
            return try enc.encode(value)
        } catch {
            throw MBP2PError.invalidJSON(String(describing: error))
        }
    }

    /// Convert Encodable to Foundation JSON object (`Any`) suitable for canonicalization.
    public static func toJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encode(value)
        return try JSONObject(from: data)
    }

    public static func JSONObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw MBP2PError.invalidJSON(String(describing: error))
        }
    }
}

/// A minimal Codable wrapper for arbitrary JSON values.
/// Used for `metadata`, `auth.payload`, and `part.data`.
public enum CodableValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case string(String)
    case array([CodableValue])
    case object([String: CodableValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let i = try? container.decode(Int64.self) { self = .int(i); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([CodableValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: CodableValue].self) { self = .object(o); return }
        throw MBP2PError.invalidJSON("Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public func toFoundation() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return NSNumber(value: i)
        case .string(let s): return s
        case .array(let a): return a.map { $0.toFoundation() }
        case .object(let o):
            var dict: [String: Any] = [:]
            dict.reserveCapacity(o.count)
            for (k, v) in o {
                dict[k] = v.toFoundation()
            }
            return dict
        }
    }
}
