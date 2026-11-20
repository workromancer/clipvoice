// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipVoice",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClipVoiceCore",
            targets: ["ClipVoiceCore"]
        ),
        .library(
            name: "ClipVoiceMCP",
            targets: ["ClipVoiceMCP"]
        ),
        .executable(
            name: "ClipVoice",
            targets: ["ClipVoiceApp"]
        ),
        .executable(
            name: "clipvoice-cli",
            targets: ["ClipVoiceCLI"]
        ),
        .executable(
            name: "clipvoice-mcp",
            targets: ["ClipVoiceMCPServer"]
        )
    ],
    targets: [
        .target(
            name: "ClipVoiceCore"
        ),
        .target(
            name: "ClipVoiceMCP",
            dependencies: ["ClipVoiceCore"]
        ),
        .executableTarget(
            name: "ClipVoiceApp",
            dependencies: ["ClipVoiceCore", "ClipVoiceMCP"]
        ),
        .executableTarget(
            name: "ClipVoiceCLI",
            dependencies: ["ClipVoiceCore", "ClipVoiceMCP"]
        ),
        .executableTarget(
            name: "ClipVoiceMCPServer",
            dependencies: ["ClipVoiceCore", "ClipVoiceMCP"]
        ),
        .testTarget(
            name: "ClipVoiceCoreTests",
            dependencies: ["ClipVoiceCore"]
        ),
        .testTarget(
            name: "ClipVoiceMCPTests",
            dependencies: ["ClipVoiceCore", "ClipVoiceMCP"]
        )
    ]
)
