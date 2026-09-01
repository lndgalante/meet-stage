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
        .target(
            name: "MeetStageCore",
            path: "Sources/MeetStageCore"
        ),
        .executableTarget(
            name: "MeetStage",
            dependencies: ["MeetStageCore"],
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
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "MeetStageTests",
            dependencies: ["MeetStage", "MeetStageCore"],
            path: "Tests/MeetStageTests"
        ),
        .testTarget(
            name: "MeetStageCoreTests",
            dependencies: ["MeetStageCore"],
            path: "Tests/MeetStageCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
