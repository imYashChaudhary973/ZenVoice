// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ZenVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZenVoice", targets: ["ZenVoice"]),
        .executable(name: "ZenVoiceCoreChecks", targets: ["ZenVoiceCoreChecks"])
    ],
    targets: [
        .target(
            name: "ZenVoiceCore"
        ),
        .executableTarget(
            name: "ZenVoice",
            dependencies: ["ZenVoiceCore"]
        ),
        .executableTarget(
            name: "ZenVoiceCoreChecks",
            dependencies: ["ZenVoiceCore"]
        )
    ]
)
