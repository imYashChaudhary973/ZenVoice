// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TeacherRestExtract",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.6"
        )
    ],
    targets: [
        .executableTarget(
            name: "TeacherRestExtract",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
