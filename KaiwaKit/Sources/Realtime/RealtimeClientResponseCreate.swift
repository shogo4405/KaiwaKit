enum RealtimeClientResponseCreate {
    struct Response: Codable, Sendable {
        let outputModalities: [String]
        let instructions: String
        let conversation: String
    }

    struct Request: Codable, Sendable {
        var type: String = "response.create"
        let response: Response
    }
}
