import Foundation

public enum GeminiCredential: Sendable {
    case apiKey(String)
    case ephemeralToken(String)
}
public struct GeminiSessionConfiguration: Sendable {
    public static let defaultModel = "gemini-3.8-live"
    public let credential: GeminiCredential
    public let model: String
    public init(credential: GeminiCredential, model: String = Self.defaultModel) {
        self.credential = credential
        self.model = model
    }
}
