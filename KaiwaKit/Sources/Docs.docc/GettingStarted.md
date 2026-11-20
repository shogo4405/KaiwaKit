# Getting started

Create a voice session and manage its audio and event lifecycle.

## Overview

KaiwaKit provides native Apple APIs for OpenAI Realtime and Gemini Live. Choose
``OpenAIConversationSession`` or ``GeminiConversationSession`` and keep application
code on the shared ``ConversationSession`` interface. These APIs run on the main
actor and own microphone capture, response playback, and their connection.

### Prepare the host application

Add `NSMicrophoneUsageDescription` to your app and request microphone access with
`AVCaptureDevice.requestAccess(for: .audio)`. A sandboxed macOS app needs audio-input
and network client/server entitlements. WebRTC uses UDP sockets.

On iOS, configure and activate `AVAudioSession` for your communication audio route
before connecting. Restore the route when the call ends. Microphone permission
and audio routing belong to the host app, not the library.

### Choose a provider and credential

For OpenAI, create a ``RealtimeSessionConfiguration`` with a fresh client secret
issued by your authenticated backend. The backend obtains it through OpenAI's
`POST /v1/realtime/client_secrets` endpoint. The SDK can also exchange a supplied
API key for a short-lived secret for local development.

For Gemini, use ``GeminiSessionConfiguration`` with a Gemini API key for local
builds, or an ephemeral token issued by your backend for distributed apps. Select
a Live model available to your account through the configuration's `model` value.
Never embed production API keys in distributed apps or log credentials.

```swift
let session: any ConversationSession = GeminiConversationSession(
    configuration: GeminiSessionConfiguration(
        credential: .ephemeralToken(token)
    )
)
```

For OpenAI, use `OpenAIConversationSession(configuration:)` instead, passing a
`RealtimeSessionConfiguration(clientSecret:)`. Create a new session for each call.

### Consume events and manage the call

Subscribe to ``ConversationSession/events`` before calling
``ConversationSession/connect()``. Each ``ConversationEvent`` transcript contains
cumulative text for its current segment. Its `isFinal` value marks completion.
Interruption events indicate that the assistant's response was interrupted;
Gemini discards queued response audio when this happens.

```swift
let events = session.events
let consumer = Task { @MainActor in
    for try await event in events {
        if case .transcript(let speaker, let text, let isFinal) = event, isFinal {
            print(speaker, text)
        }
    }
}
try await session.connect()
await session.setMicrophoneEnabled(false)

// When the user stops or the app leaves the foreground:
await session.close()
consumer.cancel()
```

The event stream throws on connection or processing failure. Always close the
session on failure, cancellation, and normal call completion. Sessions do not
reconnect automatically. See the native sample for a complete foreground lifecycle.

### Use lower-level OpenAI events

``RealtimeSession`` exposes the underlying OpenAI event stream and media stream
when the app needs provider-specific behavior. Unlike the shared conversation
adapters, this API leaves capture and playback ownership to the host.

```swift
import AVFoundation
import HaishinKit
import KaiwaKit

let configuration = RealtimeSessionConfiguration(clientSecret: clientSecret)
let session = RealtimeSession(
    uri: URL(string: "https://api.openai.com/v1/realtime/calls")!,
    mode: .publish,
    configuration: configuration
)
let mixer = MediaMixer(captureSessionMode: .single)
let player = AudioPlayer(audioEngine: AVAudioEngine())
let stream = await session.stream

try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
await stream.attachAudioPlayer(player)
await mixer.addOutput(stream)
try await session.connect {
    // Stop capture and update your UI when disconnected.
}
await mixer.startRunning()

// At the end of the call:
await mixer.stopRunning()
await mixer.removeOutput(stream)
try await mixer.attachAudio(nil)
try await session.close()
await stream.attachAudioPlayer(nil)
```

Retain the session, mixer, player, and asynchronous consumers until cleanup has
finished. ``RealtimeSession/events`` delivers transcripts, errors, and other
OpenAI events through ``RealtimeEvent``.

### Transport and audio

OpenAI uses HaishinKit WebRTC tracks for microphone and response audio, with
realtime events on the data channel. Gemini uses `URLSessionWebSocketTask`, 16 kHz
mono PCM capture, and 24 kHz mono PCM playback. Test latency, speaker echo,
interruptions, and device routing on actual hardware; this prototype does not
provide libwebrtc's software echo cancellation.
