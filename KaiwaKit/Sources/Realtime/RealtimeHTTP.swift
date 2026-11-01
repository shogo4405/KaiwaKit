import Foundation

/// Errors reported while establishing a Realtime WebRTC session.
public enum RealtimeError: LocalizedError, Equatable {
    case missingCredential
    case invalidResponse
    case httpStatus(Int)

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
