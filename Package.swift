// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawView",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClawView",
            path: "Sources/ClawView",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-framework", "AppKit", "-framework", "QuartzCore"])
            ]
        )
    ]
)
