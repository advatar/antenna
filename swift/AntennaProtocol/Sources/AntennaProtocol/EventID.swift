import Foundation
import CryptoKit

public enum MBEventId {
    /// Strip fields excluded from eventId hashing per MBP2P v0.1.0:
    /// - id (self-referential)
    /// - auth (variable signatures/proofs)
    /// - thread (root posts often set thread == id)
    /// - metadata (non-normative hints; avoids recursion such as replyTopic derived from id)
    public static let stripFields: Set<String> = ["id", "auth", "thread", "metadata"]

    public static func compute(from eventJSON: Any) throws -> String {
        guard var obj = eventJSON as? [String: Any] else {
            throw MBP2PError.invalidJSON("Event root must be an object")
        }
        for k in stripFields { obj.removeValue(forKey: k) }
        let canon = try JCS.canonicalize(obj)
        let digest = SHA256.hash(data: canon.data(using: .utf8)!)
        return "0x" + digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

public extension MBEvent {
    static func fromJSON(data: Data) throws -> MBEvent {
        return try MBJSON.decode(MBEvent.self, from: data)
    }

    func computeEventId() throws -> String {
        var obj = try MBJSON.toJSONObject(self)
        // Keep author optional identity keys explicit as null to match the shared
        // interop vectors and other reference implementations.
        if var eventDict = obj as? [String: Any], var author = eventDict["author"] as? [String: Any] {
            if author["agentRegistry"] == nil { author["agentRegistry"] = NSNull() }
            if author["agentId"] == nil { author["agentId"] = NSNull() }
            if author["ens"] == nil { author["ens"] = NSNull() }
            if author["anonKey"] == nil { author["anonKey"] = NSNull() }
            eventDict["author"] = author
            obj = eventDict
        }
        return try MBEventId.compute(from: obj)
    }
}
