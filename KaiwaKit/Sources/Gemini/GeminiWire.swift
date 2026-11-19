import Foundation

enum GeminiWire {
    struct Message: Sendable {
        var setupComplete = false
        var audio: [Data] = []
        var input: String?
        var output: String?
        var inputFinished = false
        var outputFinished = false
        var turnComplete = false
        var interrupted = false
    }
    static func url(_ credential: GeminiCredential) throws -> URL {
        let key: String
        let parameter: String
        let method: String
        switch credential {
        case .apiKey(let value): key = value; parameter = "key"; method = "BidiGenerateContent"
        case .ephemeralToken(let value): key = value; parameter = "access_token"; method = "BidiGenerateContentConstrained"
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RealtimeError.missingCredential }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.\(method)"
        components.queryItems = [URLQueryItem(name: parameter, value: trimmed)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw ConversationError.protocolMessage }
        return url
    }
    static func setup(_ model: String) throws -> String {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversationError.protocolMessage }
        return try encode(["setup": [
            "model": model.hasPrefix("models/") ? model : "models/\(model)",
            "generationConfig": ["responseModalities": ["AUDIO"]],
            "systemInstruction": ["parts": [["text": "You are a friendly assistant."]]],
            "inputAudioTranscription": [:], "outputAudioTranscription": [:]
        ]])
    }
    static func audio(_ bytes: Data) throws -> String {
        try encode(["realtimeInput": ["audio": ["mimeType": "audio/pcm;rate=16000", "data": bytes.base64EncodedString()]]])
    }
    static func decode(_ text: String) throws -> Message {
        guard text.utf8.count <= 1024 * 1024, let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConversationError.protocolMessage }
        guard root["error"] == nil, root["goAway"] == nil else { throw ConversationError.connection }
        let content = root["serverContent"] as? [String: Any] ?? [:]
        let input = content["inputTranscription"] as? [String: Any] ?? [:]
        let output = content["outputTranscription"] as? [String: Any] ?? [:]
        var result = Message()
        result.setupComplete = root["setupComplete"] is [String: Any]
        result.input = input["text"] as? String
        result.output = output["text"] as? String
        result.inputFinished = input["finished"] as? Bool == true
        result.outputFinished = output["finished"] as? Bool == true
        result.interrupted = content["interrupted"] as? Bool == true
        result.turnComplete = content["turnComplete"] as? Bool == true
        let turn = content["modelTurn"] as? [String: Any] ?? [:]
        for part in turn["parts"] as? [[String: Any]] ?? [] {
            guard let inline = part["inlineData"] as? [String: Any], let mime = inline["mimeType"] as? String,
                  mime.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) == "audio/pcm" else { continue }
            guard !mime.components(separatedBy: ";").dropFirst().map({ $0.trimmingCharacters(in: .whitespaces) }).contains(where: { $0.hasPrefix("rate=") && $0 != "rate=24000" }),
                  let encoded = inline["data"] as? String, let pcm = Data(base64Encoded: encoded), pcm.count % 2 == 0 else {
                throw ConversationError.protocolMessage
            }
            result.audio.append(pcm)
        }
        return result
    }
    private static func encode(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
}
