// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ZenVoiceProxy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZenVoiceProxy", targets: ["ZenVoiceProxy"])
    ],
    targets: [
        .executableTarget(name: "ZenVoiceProxy")
    ]
)
