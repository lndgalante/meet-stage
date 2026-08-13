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
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit")
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
