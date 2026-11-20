# 📚 API documentation

Pushing a tag runs the **API documentation** workflow. It generates the Swift
reference with DocC and the Android reference with Dokka from that tag's source.
Only the library targets are documented; example applications are excluded.

After both generators succeed, the workflow publishes the combined site to
[GitHub Pages](https://shogo4405.github.io/KaiwaKit/). The site shows the most
recently published tag. Each workflow run also retains the generated HTML as
`api-documentation` for 90 days (containing `api-documentation.tar.gz`).

The workflow can be run manually from Actions. A run on `main` generates and
uploads the same documentation for verification but does not deploy it. To
republish an existing tag, manually run the workflow with that tag selected.
No tag or release is created by this workflow.

## 🌿 Landing page

The landing page template and styles live in `docs/site/`. Both publication
workflows use `.github/scripts/build_documentation_site.rb` to add the page and
its screenshot to the generated API site. Updates to these files on main run the
**Landing page** workflow: it retrieves the latest release’s successful
`api-documentation` artifact and replaces only the landing page assets, preserving
the released Swift and Android references. No new release tag is needed. The
artifact must still be available (90-day retention); if it has expired, rerun
**API documentation** on the release tag first.

For a local preview, run `ruby .github/scripts/build_documentation_site.rb OUTPUT VERSION`
against an extracted API site and serve that directory with a static web server.

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
single published SDK is normalized by JitPack to the repository coordinates `com.github.shogo4405:KaiwaKit:<tag>`; development
builds use `main-SNAPSHOT`. SwiftPM reads the root `Package.swift` from the same tag.

## 🍎 macOS sample releases

The **macOS sample** workflow builds the app for Apple Silicon (`arm64`) on main
updates, tags, pull requests, or manual runs. Tagged runs attach
`KaiwaKit-macOS-arm64.zip` to the matching GitHub Release, creating that Release
with generated notes if it does not exist. Re-running a tag replaces the asset
without changing an existing Release's title or notes. No tag is created.

Main and pull-request builds keep the **KaiwaKit-macOS-arm64** Actions artifact
for 90 days. Extract the ZIP to get `Kaiwa Example.app`.

The app uses the Debug configuration and is ad-hoc signed, without Developer ID notarization. macOS may
require approval before opening a downloaded development build. The archive keeps
framework links, executable permissions, and the app's microphone/network entitlements.
