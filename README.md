# KaiwaKit

KaiwaKit provides native **Swift and Kotlin SDKs for OpenAI Realtime and Gemini Live voice conversations**. OpenAI uses HaishinKit WebRTC media tracks and the `oai-events` data channel. Gemini uses WebSocket with 16 kHz microphone PCM and 24 kHz response PCM.

- **Apple:** Swift SDK at the repository root, with a SwiftUI sample in `Examples/`. The instructions below cover this SDK.
- **Android:** Kotlin SDK and Jetpack Compose sample in [`android/`](android/README.md). Open that directory as a separate Android Studio project. It downloads HaishinKit.kt from JitPack and requires a version containing the duplex RTC changes.

The implementations and build systems are independent. No Kotlin Multiplatform or Compose Multiplatform dependency is required.

The repository includes a shared SwiftUI voice-chat sample for **iOS and native macOS**.

> [!IMPORTANT]
> This is a proof of concept using HaishinKit’s WebRTC implementation. The remote package dependency tracks HaishinKit `main` (the upcoming 2.3 API), which includes the duplex audio changes. These changes are not yet available in a tagged release. Production adoption requires further testing; consider libwebrtc for mature WebRTC audio processing.

## Features

- Gemini Live voice conversations over WebSocket, with input/output transcripts and interruption handling.
- A shared conversation API and OpenAI/Gemini selectors in the Apple and Android samples.
- [OpenAI Realtime API with WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc): SDP negotiation through `/v1/realtime/calls`.
- Full-duplex microphone capture and AI audio playback using HaishinKit’s `RTCStream` and `AudioPlayer`.
- Audio transcripts and API errors delivered as Realtime events.
- Short-lived Realtime client secrets, plus API-key entry for local development.
- Shared iOS/macOS sample with microphone permission handling and call cleanup.

## Requirements

- Swift 6 / Xcode 16 or later; use a toolchain supported by the HaishinKit checkout.
- Library: iOS 15+, macOS 12+, tvOS 15+, Mac Catalyst 15+, visionOS 1.3+.
- Sample: iOS 16+ or macOS 13.5+. The current libdatachannel binary supports arm64 iOS Simulator; the generic x86_64 Simulator build does not link.
- An OpenAI or Gemini API account, or a short-lived credential issued by your backend.

## Run the sample

Open `Examples/Examples.xcodeproj` and resolve package dependencies to use HaishinKit `main`. Select the **Kaiwa Example** scheme and **My Mac** or an iOS device, then follow steps 3–5 below.

### Develop with a local HaishinKit checkout

To edit both libraries together, keep the repositories side by side:

```text
GitHub/
├── HaishinKit.swift/   # checkout containing the duplex audio changes
└── KaiwaKit/
```

1. Open `Examples/LocalDevelopment.xcworkspace`. This overrides the remote HaishinKit package with `../HaishinKit.swift`.
2. Select the **Kaiwa Example** scheme and **My Mac** or an iOS device. Select your signing team if needed.
3. Choose **OpenAI** or **Gemini**, then choose API key or a provider-specific short-lived credential. For Gemini, select a Live API model available to your account. Credentials are retained only in memory.
4. Click **Start conversation**, allow microphone access, and speak. The selected provider’s generated voice plays through the selected output device; its transcript appears in the window.
5. Click **Stop** to release the microphone, player, and connection. Closing the window or backgrounding the sample also ends the call.

Use headphones when testing: this libdatachannel-based prototype does not provide libwebrtc’s acoustic echo cancellation. On macOS, microphone access can be changed in System Settings → Privacy & Security → Microphone.

`Examples/Examples.xcodeproj` uses the remote HaishinKit package. `Examples/LocalDevelopment.xcworkspace` uses the neighboring checkout instead; make sure it includes the duplex audio changes.

### Authentication and ChatGPT login

The sample’s **Open OpenAI API keys** link opens OpenAI Platform in your browser. It is not an OAuth sign-in button and does not authorize the app automatically.

As checked on 2026-11-01, the public [Sign in with ChatGPT inference guide](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) documents the Responses API for ChatGPT plan usage. Realtime API access is not documented for that flow; its [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) also exclude audio input and transcription. KaiwaKit therefore does not use a ChatGPT/Codex login token for Realtime calls.

For distributed apps, keep the standard OpenAI API key on your backend. After authenticating the user in your own app, have the backend mint a short-lived token with `POST /v1/realtime/client_secrets`. Configure the session with `type: "realtime"`, `model: "gpt-realtime"`, and `output_modalities: ["audio"]`, then pass its `value` to KaiwaKit. Fetch a new token for each connection; expired tokens require a new one. See the [official WebRTC authentication flow](https://developers.openai.com/api/docs/guides/voice-webrtc).

The sample can also create a client secret from a manually entered API key for local testing. Do not embed your key in source code or distribute it with the app. API billing is separate from ChatGPT subscription usage.

## Shared conversation API

`ConversationSession` exposes connection state, microphone mute, close, and normalized
`ConversationEvent` transcripts and interruption events. Each transcript contains
cumulative text for the current segment; `isFinal` marks its completion. Subscribe
before connecting and create a new session for each call. The session owns audio
capture and playback; the host grants microphone permission and configures routing.

```swift
let session: any ConversationSession = GeminiConversationSession(
    configuration: GeminiSessionConfiguration(credential: .apiKey(apiKey))
)
// Or OpenAIConversationSession(configuration: RealtimeSessionConfiguration(clientSecret: secret))
try await session.connect()
await session.setMicrophoneEnabled(false)
await session.close()
```

Apple Gemini connections use `URLSessionWebSocketTask` and system TLS trust.
Android Gemini connections use HaishinKit.kt's libdatachannel WebSocket; see the
[Android dependency instructions](android/README.md).
Gemini uses automatic voice activity detection and discards queued response audio
when interrupted. Input and output transcripts are enabled during setup. For
production, issue Gemini ephemeral tokens on your backend and use
`.ephemeralToken(token)` rather than distributing a standard API key.
See the [Gemini Live WebSocket guide](https://aistudio.google.com/docs/live-api/get-started-websocket).

## Library usage

The lower-level OpenAI `RealtimeSession` API remains available:


```swift
import AVFoundation
import HaishinKit
import KaiwaKit

// Obtain a fresh client secret from your authenticated backend.
let configuration = RealtimeSessionConfiguration(clientSecret: clientSecret)
let session = RealtimeSession(
    uri: URL(string: "https://api.openai.com/v1/realtime/calls")!,
    mode: .publish,
    configuration: configuration
)
let mixer = MediaMixer(captureSessionMode: .single)
let player = AudioPlayer(audioEngine: AVAudioEngine())
let stream = await session.stream

// Request microphone permission and configure AVAudioSession on iOS first.
try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
await stream.attachAudioPlayer(player)
await mixer.addOutput(stream)
try await session.connect {
    // Notify your UI and stop capture when the transport disconnects.
}
await mixer.startRunning()

// At the end of the call:
await mixer.stopRunning()
await mixer.removeOutput(stream)
try await mixer.attachAudio(nil)
try await session.close()
await stream.attachAudioPlayer(nil)
```

Retain the session, mixer, and player for the duration of the call. Include `NSMicrophoneUsageDescription` in your app. A sandboxed macOS app also needs audio-input and network client/server entitlements, as shown in `Examples/macOS/Kaiwa.entitlements` (WebRTC uses UDP sockets).

## Verification

To test KaiwaKit against the local HaishinKit checkout:

```sh
swift package resolve
swift package edit HaishinKit.swift --path ../HaishinKit.swift
swift test
xcodebuild -workspace Examples/LocalDevelopment.xcworkspace \
  -scheme 'Kaiwa Example' -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Examples/LocalDevelopment.xcworkspace \
  -scheme 'Kaiwa Example' -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

Run the duplex regression tests from the HaishinKit repository with `swift test --filter RTCStreamTests`. They cover direction changes, stopping/restarting both pipelines, and preventing decoded remote audio from entering the outgoing encoder. Automated tests do not contact either provider; microphone capture and end-to-end audio still need a real-device check with a valid credential.

## License

BSD-3-Clause
