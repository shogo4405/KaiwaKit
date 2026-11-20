# 📚 API documentation

Pushing a tag runs the **API documentation** workflow. It generates the Swift
reference with DocC and the Android reference with Dokka from that tag's source.
Only the library targets are documented; example applications are excluded.

After both generators succeed, the workflow publishes the combined site to
[GitHub Pages](https://shogo4405.github.io/KaiwaKit/). The site shows the most
recently published tag. Each workflow run also retains the generated HTML as
`api-documentation` for 90 days.

The workflow can be run manually from Actions. A run on `main` generates and
uploads the same documentation for verification but does not deploy it. To
republish an existing tag, manually run the workflow with that tag selected.
No tag or release is created by this workflow.

## 🛠️ Local generation

From the repository root, on macOS with Xcode selected:

```sh
mkdir -p /tmp/kaiwakit-api
swift package --allow-writing-to-directory /tmp/kaiwakit-api generate-documentation \
  --target KaiwaKit --disable-indexing --warnings-as-errors \
  --transform-for-static-hosting --hosting-base-path KaiwaKit/swift \
  --output-path /tmp/kaiwakit-api/swift
./android/gradlew -p android :kaiwakit:dokkaGenerate -PdocumentationVersion=local
```

Android output is written to `android/kaiwakit/build/dokka/html/`. The build needs
the Android SDK but does not build the sample or require a local HaishinKit checkout.

## 🖼️ Screenshot

`images/macos-sample.png` is an actual capture of the macOS sample with Gemini
selected and no credential entered. It illustrates the sample's connection UI,
not a live or simulated conversation.

## ✅ Verification

Apple library tests and native sample builds:

```sh
swift test
xcodebuild -workspace Examples/LocalDevelopment.xcworkspace \
  -scheme 'Kaiwa Example' -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Examples/LocalDevelopment.xcworkspace \
  -scheme 'Kaiwa Example' -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

The local workspace expects HaishinKit.swift next to KaiwaKit. The current native
binary supports arm64 iOS Simulator; x86_64 simulator builds do not link.

Android SDK tests and sample checks:

```sh
./android/gradlew -p android ktlintCheck :kaiwakit:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

Tests do not contact either AI provider. Audible conversations, Bluetooth routing,
echo behavior, and microphone interruptions still require device testing with valid
credentials.

## 📦 JitPack publication

`jitpack.yml` publishes only `:kaiwakit` from the Android subdirectory using JDK 17.
The JitPack `VERSION` is passed as `kaiwaKitVersion` to the Maven publication. The
published coordinates are `com.github.shogo4405.KaiwaKit:kaiwakit:<tag>`; development
builds use `main-SNAPSHOT`. SwiftPM reads the root `Package.swift` from the same tag.
