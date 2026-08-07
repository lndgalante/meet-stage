// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MeetStage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetStage", targets: ["MeetStage"])
    ],
    targets: [
        .executableTarget(
            name: "MeetStage",
            path: "Sources/MeetStage",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
