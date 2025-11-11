enum RealtimeClientSecrets {
    static let endpoint: String = "https://api.openai.com/v1/realtime/client_secrets"

    struct Request: Codable, Sendable {
        struct ExpiresAfter: Codable, Sendable {
            let anchor: String
            let seconds: Int
        }
        struct Session: Codable, Sendable {
            let type: String
            let model: String
            var instructions: String = "You are a friendly assistant."
            var outputModalities: [String] = ["text"]
        }
        let expiresAfter: ExpiresAfter
        let session: Session
    }

    struct Response: Codable, Sendable {
        let value: String
    }
}
