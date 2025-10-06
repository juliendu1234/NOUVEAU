// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ARDroneController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ARDroneController",
            targets: ["ARDroneController"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ARDroneController",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
