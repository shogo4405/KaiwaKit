// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

#if swift(<6)
let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency")
]
#else
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]
#endif

let package = Package(
    name: "KaiwaKit",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v12),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "KaiwaKit", targets: ["KaiwaKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", revision: "3e52fd8d")
    ],
    targets: [
        .target(
            name: "KaiwaKit",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTCHaishinKit", package: "HaishinKit.swift")
            ],
            path: "KaiwaKit/Sources",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "KaiwaKitTests",
            dependencies: ["KaiwaKit"],
            path: "KaiwaKit/Tests",
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v6, .v5]
)
