import Foundation

public enum MBTopics {
    public static func categoryTopic(_ categoryEns: String) -> String {
        return "mb/v1/cat/\(categoryEns)"
    }

    public static func helpTopic(_ categoryEns: String) -> String {
        return "mb/v1/help/\(categoryEns)"
    }

    public static func helpRepliesTopic(_ helpRequestEventId: String) -> String {
        return "mb/v1/help-replies/\(helpRequestEventId)"
    }
}
