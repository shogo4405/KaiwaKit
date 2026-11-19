import Foundation

public enum ConversationProvider: String, CaseIterable, Sendable, Identifiable {
    case openAI, gemini
    public var id: String { rawValue }
    public var name: String { self == .openAI ? "OpenAI" : "Gemini" }
}
public enum ConversationState: Sendable { case idle, connecting, connected, closing, closed }
public enum ConversationSpeaker: Sendable { case user, assistant }
public enum ConversationEvent: Sendable, Equatable {
    /// Cumulative text for one segment; `isFinal` marks the end of that segment.
    case transcript(speaker: ConversationSpeaker, text: String, isFinal: Bool)
    case interrupted
}

/// A single foreground voice call. The host owns microphone permission and platform audio routing.
/// Instances are single-use. Close after failure/cancellation and create a new instance to reconnect.
@MainActor
public protocol ConversationSession: AnyObject {
    var state: ConversationState { get }
    var events: AsyncThrowingStream<ConversationEvent, any Error> { get }
    func connect() async throws
    func setMicrophoneEnabled(_ enabled: Bool) async
    func close() async
}

enum ConversationError: LocalizedError {
    case closed, timeout, overflow, audio, protocolMessage, connection
    var errorDescription: String? {
        switch self {
        case .closed: "The conversation was closed. Start a new conversation."
        case .timeout: "The connection timed out. Check the network and credential."
        case .overflow: "The conversation exceeded its audio or event queue capacity."
        case .audio: "Unable to initialize or process microphone and playback audio."
        case .protocolMessage: "The AI service returned an invalid or unsupported message."
        case .connection: "The AI connection failed. Check the network, model and credential."
        }
    }
}

@MainActor
final class ConversationEvents {
    let stream: AsyncThrowingStream<ConversationEvent, any Error>
    private let continuation: AsyncThrowingStream<ConversationEvent, any Error>.Continuation
    init() {
        var saved: AsyncThrowingStream<ConversationEvent, any Error>.Continuation!
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(64)) { saved = $0 }
        continuation = saved
    }
    func emit(_ event: ConversationEvent) throws {
        if case .dropped = continuation.yield(event) { throw ConversationError.overflow }
    }
    func finish(_ error: (any Error)? = nil) { continuation.finish(throwing: error) }
}
