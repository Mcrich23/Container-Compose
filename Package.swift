// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Container-Compose",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
        .package(url: "https://github.com/mcrich23/container", branch: "add-compose"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(name: "Container-Compose", dependencies: ["Yams", .product(name: "ContainerCLI", package: "container"), .product(name: "ArgumentParser", package: "swift-argument-parser")]),
    ]
)
