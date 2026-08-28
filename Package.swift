// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MeetStage",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MeetStage", targets: ["MeetStage"])
    ],
    targets: [
        .executableTarget(
            name: "MeetStage",
            path: "Sources/MeetStage",
            exclude: ["IdleStageChrome.metal"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "MeetStageTests",
            dependencies: ["MeetStage"],
            path: "Tests/MeetStageTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
