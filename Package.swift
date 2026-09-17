// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ZenVoice",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ZenVoice", targets: ["ZenVoice"]),
        .executable(name: "ZenVoiceCoreChecks", targets: ["ZenVoiceCoreChecks"]),
        .executable(
            name: "ZenVoiceStorageChecks",
            targets: ["ZenVoiceStorageChecks"]
        ),
        .executable(
            name: "ZenVoiceRuntimeChecks",
            targets: ["ZenVoiceRuntimeChecks"]
        ),
        .executable(
            name: "ZenVoiceAccuracyChecks",
            targets: ["ZenVoiceAccuracyChecks"]
        ),
        .executable(
            name: "ZenVoiceLanguageBench",
            targets: ["ZenVoiceLanguageBench"]
        ),
        .executable(
            name: "ZenVoiceLinkChecks",
            targets: ["ZenVoiceLinkChecks"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            from: "1.24.2"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.6.0"
        ),
        .package(
            url: "https://github.com/ontypehq/mlx-swift-asr",
            branch: "main"
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            from: "1.1.6"
        )
    ],
    targets: [
        .target(
            name: "ZenVoiceCore"
        ),
        .target(
            name: "ZenVoiceStorage",
            dependencies: ["ZenVoiceCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "ZenVoiceLink",
            dependencies: ["ZenVoiceCore"]
        ),
        .target(
            name: "ZenVoiceRuntime",
            dependencies: [
                "ZenVoiceCore",
                "whisper",
                "parakeet",
                .product(
                    name: "onnxruntime",
                    package: "onnxruntime-swift-package-manager"
                ),
                .product(name: "MLXASR", package: "mlx-swift-asr"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "ZenVoice",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceStorage",
                "ZenVoiceRuntime",
                "ZenVoiceLink",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "ZenVoiceCoreChecks",
            dependencies: ["ZenVoiceCore"]
        ),
        .executableTarget(
            name: "ZenVoiceStorageChecks",
            dependencies: ["ZenVoiceCore", "ZenVoiceStorage"]
        ),
        .executableTarget(
            name: "ZenVoiceRuntimeChecks",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceRuntime",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "ZenVoiceAccuracyChecks",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceRuntime",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "ZenVoiceLanguageBench",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceRuntime",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "ZenVoiceLinkChecks",
            dependencies: ["ZenVoiceCore", "ZenVoiceLink"]
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
    ],
    swiftLanguageModes: [.v5]
)
