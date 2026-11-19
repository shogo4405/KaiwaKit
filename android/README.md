# KaiwaKit for Android

Native Kotlin SDK and Jetpack Compose voice-chat sample for OpenAI Realtime over
WebRTC. The Swift package remains at the repository root. Android and Apple code
build independently; neither KMP nor Compose Multiplatform is required.

## Requirements

- Android 10 / API 29 or later; a physical device with an Opus encoder/decoder.
- Android Studio with JDK 17 or later (AGP 9.2.1 / Gradle 9.4.1).
- Android SDK 37.
- A JitPack build of HaishinKit.kt containing `RTCDuplexSession`.
- A fresh OpenAI Realtime client secret from your backend.

Open this `android/` directory in Android Studio. Set the Android SDK location
using the IDE or `ANDROID_HOME`. HaishinKit.kt is downloaded as a prebuilt AAR
from JitPack; a neighboring checkout, NDK and CMake are not required for KaiwaKit.

The dependency is `com.github.HaishinKit.HaishinKit~kt:rtc`. Its version is set by
`haishinKitVersion` in `gradle.properties`, pinned to release `0.20.3`. To select
a published tag or commit, override that property:

```sh
./gradlew :app:assembleDebug -PhaishinKitVersion=<tag-or-commit>
```

The default dependency is [HaishinKit.kt 0.20.3](https://github.com/HaishinKit/HaishinKit.kt/releases/tag/0.20.3),
which includes `RTCDuplexSession`. Existing versions without that API are not
compatible. Use a release tag or commit for reproducible builds.

## Run the sample

1. Select the `app` run configuration and a physical Android device.
2. Fetch a **new Realtime client secret** from your authenticated backend. Keep
   standard OpenAI API keys on the backend; the sample accepts only client secrets.
   The secret's session settings should enable audio output and the desired voice,
   instructions, and optional input transcription.
3. Paste the client secret, tap **Start conversation**, and allow microphone access.
4. Speak to hear responses. Completed assistant transcripts appear in the screen;
   user transcripts appear only if enabled in the backend session configuration.
5. Tap **Mute** or **Stop**. Leaving the foreground ends the call. Start another call
   with a new token after a failure or expiration.

Credentials and transcripts stay in memory and are not saved across activity
recreation. Background calls, automatic reconnect, and explicit audio-device
selection are not implemented. Android chooses the communication audio route.

Use headphones for this prototype. Capture uses `VOICE_COMMUNICATION` and playback
uses voice-communication audio attributes, but this libdatachannel backend does not
include libwebrtc's software AEC. Speaker echo, Bluetooth routing, interruption,
latency and full-duplex audio quality need real-device validation.

## SDK usage

```kotlin
val session = RealtimeSession(
    context,
    RealtimeSessionConfiguration(
        clientSecretProvider = { backend.fetchFreshRealtimeClientSecret() },
    ),
)
```

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
It does not own the host's microphone. Create a new session for each call. See
`ConversationController` and `CallMicrophone` for the complete foreground lifecycle.

## Verification

```sh
./gradlew :kaiwakit:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

The native libraries are supplied by the JitPack AAR; no local native build is needed.
Tests do not contact OpenAI or require credentials. They cover unknown event
payloads, connection readiness, credential cancellation, transport cancellation,
cleanup, HTTP cancellation, bounded response reads and safe HTTP errors. HaishinKit.kt also has native peer round-trip tests for duplex Opus
and Unicode text data channels. A successful build does not validate audible
conversation on a device.

The Android CI also downloads HaishinKit.kt from JitPack. Set the repository
variable `HAISHINKIT_ANDROID_VERSION` to the JitPack version containing the required
RTC changes; it defaults to `0.20.3`. No source-checkout substitution is used.

Protocol reference: [OpenAI Realtime WebRTC guide](https://developers.openai.com/api/docs/guides/voice-webrtc).
