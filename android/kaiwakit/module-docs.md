# Module kaiwakit

Native Kotlin APIs for OpenAI Realtime and Gemini Live voice conversations.

Use `ConversationSession` for a shared connection lifecycle, microphone mute,
transcripts, and interruption events. `OpenAIConversationSession` uses WebRTC;
`GeminiConversationSession` uses HaishinKit.kt's libdatachannel WebSocket.
The host application grants microphone permission and configures audio routing.
Create a new session for each call and close it when the call ends.

The lower-level `RealtimeSession` API exposes OpenAI-specific events and media
streams for applications that manage their own audio pipeline.

## Shared SDK API

`OpenAIConversationSession` and `GeminiConversationSession` implement
`ConversationSession`. They own capture/playback; the host owns permission and
audio routing. Subscribe to `events` and `failure` before connecting. Transcript
text is cumulative for each segment; show `isFinal` events for completed text.

```kotlin
val session: ConversationSession = GeminiConversationSession(
    context,
    GeminiSessionConfiguration(credentialProvider = { backend.fetchGeminiEphemeralToken() },
        credentialKind = GeminiCredentialKind.EPHEMERAL_TOKEN),
)
session.connect()
session.setMicrophoneEnabled(false)
session.close()
```

Create a fresh session per call. Use `OpenAIConversationSession(context,
RealtimeSessionConfiguration(...))` for OpenAI with the same lifecycle.

## Lower-level OpenAI SDK usage

```kotlin
val session = RealtimeSession(
    context,
    RealtimeSessionConfiguration(
        clientSecretProvider = { backend.fetchFreshRealtimeClientSecret() },
    ),
)
```

For local development, `clientSecretProvider = { RealtimeClientSecrets.create(apiKey) }`
provides the same API-key flow as the sample. This helper mints a fresh audio
credential; it does not store the key. HTTP failures expose a safe
`RealtimeRequestException.statusCode` without the server response body.

The host requests microphone permission and configures `AudioManager` for
communication. Register `session.outgoing` with a HaishinKit `MediaMixer`, use a
48 kHz capture source, and subscribe to `session.events` before `connect()`.
Incoming audio plays through `session.incoming` without attaching a video view.
`connect()` returns when the audio track, data channel, and media pipelines are
ready. Begin capture after it returns.

`state` and `failure` are `StateFlow`s. `events` is a non-replaying `SharedFlow`;
unknown event types and fields remain accessible through `RealtimeEvent.payload`.
Use `send(JsonObject)` to send client events. Audio travels over the Opus media
track, not JSON messages. Slow event consumers cause a reported failure rather
than unbounded buffering.

On stop or transport failure, stop capture, call `session.close()`, unregister the
outgoing stream, release the microphone/mixer, and restore the previous audio
mode. `close()` cancels connection setup and waits for transport/media cleanup.
It does not own the host's microphone. Create a new session for each call. The native sample demonstrates the complete foreground lifecycle.

