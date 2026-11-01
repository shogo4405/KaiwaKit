import Foundation

/// A partial representation of a JSON event received from OpenAI Realtime.
///
/// Inspect ``type`` before reading optional payloads. For example,
/// `response.output_audio_transcript.done` provides ``transcript``, while an
/// `error` event provides ``error``. Unknown JSON keys are ignored during decoding.
/// This type does not model every Realtime event or conversation-item shape;
/// events whose payload cannot be decoded are skipped by ``RealtimeSession``.
///
/// Receive events through ``RealtimeSession/events``. These values describe
/// events only; encoding a value does not send it to the server.
public struct RealtimeEvent: Codable, Equatable, Sendable {
    /// One text or audio-transcript content part of a conversation message.
    public struct Content: Codable, Equatable, Sendable {
        /// The server-provided discriminator, such as `output_text` or `output_audio`.
        public let type: String
        /// Text content when present; audio-only content may omit this field.
        public let text: String?
        /// The transcript attached to an audio content part, when present.
        public let transcript: String?
    }

    /// A conversation message containing a role and content parts.
    /// Non-message items, such as function calls, are not modeled by this structure.
    public struct Item: Codable, Equatable, Sendable {
        /// The conversation-item discriminator, typically `message`.
        public let type: String
        /// The message author, such as `user` or `assistant`.
        public let role: String
        /// The content parts included with this message.
        public let content: [Content]
    }

    /// The Realtime event name, such as `response.output_audio_transcript.done`.
    public let type: String
    /// A message item included by events such as `response.output_item.done`.
    public let item: Item?
    /// A top-level transcript provided by an audio-transcript event.
    public let transcript: String?
    /// Error details when this is a server error event.
    public let error: APIError?

    /// The human-readable portion of a server error received on the data channel.
    /// Connection-setup errors are represented separately by ``RealtimeError``.
    public struct APIError: Codable, Equatable, Sendable {
        /// The diagnostic message supplied by the server.
        public let message: String
    }
}
