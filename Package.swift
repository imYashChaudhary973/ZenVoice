// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ZenVoice",
    platforms: [
        .macOS(.v14)
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
            name: "ZenVoiceRuntime",
            dependencies: ["ZenVoiceCore", "whisper"]
        ),
        .target(
            name: "ZenVoiceRefinementRuntime",
            dependencies: ["ZenVoiceCore", "LlamaFramework"]
        ),
        .executableTarget(
            name: "ZenVoice",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceStorage",
                "ZenVoiceRuntime",
                "ZenVoiceRefinementRuntime"
            ]
        ),
        .executableTarget(
            name: "ZenVoiceCoreChecks",
            dependencies: ["ZenVoiceCore"]
        ),
        .executableTarget(
            name: "ZenVoiceStorageChecks",
            dependencies: ["ZenVoiceStorage"]
        ),
        .executableTarget(
            name: "ZenVoiceRuntimeChecks",
            dependencies: [
                "ZenVoiceCore",
                "ZenVoiceRuntime",
                "ZenVoiceRefinementRuntime"
            ]
        ),
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip",
            checksum: "8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"
        ),
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b9637/llama-b9637-xcframework.zip",
            checksum: "46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7"
        )
    ]
)
