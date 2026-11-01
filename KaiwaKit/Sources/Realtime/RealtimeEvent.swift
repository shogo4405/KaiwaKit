import Foundation

// ```json
// {
//    type: "conversation.item.create",
//    item: {
//        type: "message",
//        role: "user",
//        content: [
//            {
//                type: "input_text",
//                text: "hello there!",
//            }
//        ]
//    }
// }
// ```
public struct RealtimeEvent: Codable, Equatable, Sendable {
    public struct Content: Codable, Equatable, Sendable {
        public let type: String
        public let text: String?
        public let transcript: String?
    }

    public struct Item: Codable, Equatable, Sendable {
        public let type: String
        public let role: String
        public let content: [Content]
    }

    public let type: String
    public let item: Item?
    public let transcript: String?
    public let error: APIError?

    public struct APIError: Codable, Equatable, Sendable {
        public let message: String
    }
}
