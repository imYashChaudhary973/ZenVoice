// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BuilderVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BuilderVoice", targets: ["BuilderVoice"]),
        .executable(name: "BuilderVoiceCoreChecks", targets: ["BuilderVoiceCoreChecks"]),
        .executable(
            name: "BuilderVoiceStorageChecks",
            targets: ["BuilderVoiceStorageChecks"]
        ),
        .executable(
            name: "BuilderVoiceRuntimeChecks",
            targets: ["BuilderVoiceRuntimeChecks"]
        ),
        .executable(
            name: "BuilderVoiceAccuracyChecks",
            targets: ["BuilderVoiceAccuracyChecks"]
        ),
        .executable(
            name: "BuilderVoiceLanguageBench",
            targets: ["BuilderVoiceLanguageBench"]
        ),
        .executable(
            name: "BuilderVoiceCloudLiveChecks",
            targets: ["BuilderVoiceCloudLiveChecks"]
        ),
        .executable(
            name: "BuilderVoiceLinkChecks",
            targets: ["BuilderVoiceLinkChecks"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.6.0"
        )
    ],
    targets: [
        .target(
            name: "BuilderVoiceCore"
        ),
        .target(
            name: "BuilderVoiceStorage",
            dependencies: ["BuilderVoiceCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "BuilderVoiceLink",
            dependencies: ["BuilderVoiceCore"]
        ),
        .target(
            name: "BuilderVoiceRuntime",
            dependencies: [
                "BuilderVoiceCore",
                "whisper",
                "parakeet",
            ]
        ),
        .executableTarget(
            name: "BuilderVoice",
            dependencies: [
                "BuilderVoiceCore",
                "BuilderVoiceStorage",
                "BuilderVoiceRuntime",
                "BuilderVoiceLink",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "BuilderVoiceCoreChecks",
            dependencies: ["BuilderVoiceCore"]
        ),
        .executableTarget(
            name: "BuilderVoiceStorageChecks",
            dependencies: ["BuilderVoiceCore", "BuilderVoiceStorage"]
        ),
        .executableTarget(
            name: "BuilderVoiceRuntimeChecks",
            dependencies: [
                "BuilderVoiceCore",
                "BuilderVoiceRuntime",
            ]
        ),
        .executableTarget(
            name: "BuilderVoiceAccuracyChecks",
            dependencies: [
                "BuilderVoiceCore",
                "BuilderVoiceRuntime",
            ]
        ),
        .executableTarget(
            name: "BuilderVoiceLanguageBench",
            dependencies: [
                "BuilderVoiceCore",
                "BuilderVoiceRuntime",
            ]
        ),
        .executableTarget(
            name: "BuilderVoiceCloudLiveChecks",
            dependencies: ["BuilderVoiceCore"]
        ),
        .executableTarget(
            name: "BuilderVoiceLinkChecks",
            dependencies: ["BuilderVoiceCore", "BuilderVoiceLink"]
        ),
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip",
            checksum: "8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"
        ),
        .binaryTarget(
            name: "parakeet",
            path: "vendor/parakeet.xcframework"
        )
    ]
)
