# 🤖 KaiwaKit for Android

Native Kotlin voice conversations with **OpenAI Realtime** and **Gemini Live**.
The SDK and Jetpack Compose sample build independently of the Swift package.

## 📦 Library

Install through JitPack using the [root README](../README.md). Detailed API and
integration guidance live in [Dokka](https://shogo4405.github.io/KaiwaKit/android/),
generated automatically from version tags.

- Android 10 / API 29+.
- OpenAI uses WebRTC; Gemini uses HaishinKit.kt's libdatachannel WebSocket.
- HaishinKit.kt 0.21.1 provides `RtcDuplexSession` and `RtcWebSocket`.

## 🖼️ Sample

1. Open `android/` in Android Studio and select the `app` run configuration.
2. Choose OpenAI or Gemini, then enter an API key or a backend-issued short-lived token.
3. For Gemini, choose a Live model available to your account.
4. Start the conversation and grant microphone permission. Use **Mute** or **Stop** as needed.

Credentials and transcripts stay in memory. Leaving the foreground ends the call.
Use headphones while evaluating echo behavior; device audio quality still needs
real-device testing.

## 🛠️ Development

Use JDK 17+, Android SDK 37, and a physical device for audio testing. HaishinKit.kt
is downloaded from JitPack; a local checkout, NDK, or CMake is not required.

```sh
./gradlew ktlintCheck :kaiwakit:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

See [documentation and publication setup](../docs/README.md) for API generation
and publishing. The SDK uses the shared `ConversationSession` lifecycle; the
sample owns microphone permission and communication audio routing.
