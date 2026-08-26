// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TeacherRestPrototype",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "teacher-rest-prototype",
            targets: ["TeacherRestPrototype"]
        )
    ],
    targets: [
        .executableTarget(name: "TeacherRestPrototype")
    ]
)
