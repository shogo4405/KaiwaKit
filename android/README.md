# KaiwaKit for Android

Native Kotlin SDK and Jetpack Compose voice-chat sample for OpenAI Realtime over
WebRTC and Gemini Live over WebSocket. The Swift package remains at the repository root. Android and Apple code
build independently; neither KMP nor Compose Multiplatform is required.

## Requirements

- Android 10 / API 29 or later; a physical device with an Opus encoder/decoder.
- Android Studio with JDK 17 or later (AGP 9.2.1 / Gradle 9.4.1).
- Android SDK 37.
- HaishinKit.kt with `RTCDuplexSession` and `RTCWebSocket` (see dependency setup below).
- An OpenAI or Gemini API key for local development, or a fresh provider-specific short-lived token.

Open this `android/` directory in Android Studio. Set the Android SDK location
using the IDE or `ANDROID_HOME`. HaishinKit.kt is downloaded as a prebuilt AAR
from JitPack; a neighboring checkout, NDK and CMake are not required.

The dependency is `com.github.HaishinKit.HaishinKit~kt:rtc`. Its version is set by
`haishinKitVersion` in `gradle.properties`, currently `PR467-SNAPSHOT` from
[HaishinKit.kt PR #467](https://github.com/HaishinKit/HaishinKit.kt/pull/467).
It includes both `RTCDuplexSession` and the new `RTCWebSocket` API. Release
`0.20.3` does not include `RTCWebSocket` and cannot build this Gemini integration.
PR snapshots can change as the PR is updated; use a compatible release tag or
commit for reproducible builds once available.

To select another compatible JitPack version:

```sh
./gradlew :app:assembleDebug -PhaishinKitVersion=<tag-or-commit>
```

## Run the sample

1. Select the `app` run configuration and a physical Android device.
2. Choose **OpenAI**, then **API key (local development)**, then tap **Open OpenAI API keys**.
   Sign in to OpenAI in the browser, create an API key, return to the sample, and
   paste it into **OpenAI API key**. The browser link opens the key-management
   page; it does not automatically sign the app in. API billing is separate from
   ChatGPT subscription usage.
3. Tap **Start conversation** and allow microphone access. For each call the
   sample exchanges the API key for a short-lived `gpt-realtime` audio credential.
4. Speak to hear responses. Completed assistant transcripts appear on screen.
5. Tap **Mute** or **Stop**. Leaving the foreground ends the call.

Alternatively, choose **Realtime client secret** and paste a fresh secret issued
by your backend. The backend controls voice, instructions and optional input
transcription in that mode. User transcripts appear only when input transcription
is enabled. Obtain a new secret for each call. Switching credential types clears
the input so a credential is not accidentally used with the wrong method.

API-key entry is for testing your own local build. Distributed apps should keep
the standard API key on an authenticated backend and supply short-lived secrets.

Credentials and transcripts stay in memory and are not saved across activity
recreation. Background calls, automatic reconnect, and explicit audio-device
selection are not implemented. Android chooses the communication audio route.

Use headphones for this prototype. Capture uses `VOICE_COMMUNICATION` and playback
uses voice-communication audio attributes, but this libdatachannel backend does not
include libwebrtc's software AEC. Speaker echo, Bluetooth routing, interruption,
latency and full-duplex audio quality need real-device validation.

For Gemini, choose **Gemini**, enter a Gemini API key or backend-issued ephemeral
token, and select a Live model available to your account. The key-management link
opens Google AI Studio. Switching providers clears the credential. Gemini uses
16 kHz mono PCM capture and 24 kHz playback, automatic voice activity detection,
and input/output transcription. An interruption discards queued response audio.
The Android WebSocket engine is HaishinKit.kt/libdatachannel with TLS and hostname
verification using platform trust anchors. KaiwaKit has no OkHttp dependency.

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
It does not own the host's microphone. Create a new session for each call. See `ConversationController` for the complete foreground lifecycle.

## Verification

```sh
./gradlew :kaiwakit:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

The native libraries are supplied by the JitPack AAR; no local native build is needed.
Tests do not contact either provider or require credentials. They cover unknown event
payloads, connection readiness, credential cancellation, transport cancellation,
cleanup, API-key credential issuance and validation, HTTP cancellation, bounded response reads and safe HTTP errors. HaishinKit.kt also has native peer round-trip tests for duplex Opus
and Unicode text data channels. A successful build does not validate audible
conversation on a device.

The Android CI also downloads HaishinKit.kt from JitPack. Set the repository
variable `HAISHINKIT_ANDROID_VERSION` to the JitPack version containing the required
RTC changes; it defaults to `PR467-SNAPSHOT`. CI uses the published AARs without a source-checkout override.

Protocol reference: [OpenAI Realtime WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc).
