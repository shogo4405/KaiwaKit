import Foundation

/// Errors reported while establishing a Realtime WebRTC session.
public enum RealtimeError: LocalizedError, Equatable {
    /// Neither a nonblank API key nor a nonblank client secret was supplied.
    case missingCredential
    /// The response was not HTTP, the issued token was empty, or the SDP answer was invalid.
    /// Malformed token JSON is reported as a decoding error instead.
    case invalidResponse
    /// The server returned a status outside `200..<300`.
    /// The associated value is the HTTP status code; response bodies are not retained.
    case httpStatus(Int)

    /// A user-facing diagnostic that does not include credentials or HTTP response bodies.
    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Enter an OpenAI API key or a Realtime client secret."
        case .invalidResponse:
            return "OpenAI returned an invalid Realtime response."
        case .httpStatus(let status):
            return "OpenAI rejected the Realtime request (HTTP \(status)). Check your credential and API access."
        }
    }
}

enum RealtimeHTTP {
    static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw RealtimeError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            // Do not expose response bodies, which may contain credentials or user data.
            throw RealtimeError.httpStatus(response.statusCode)
        }
    }

    static func credential(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
