// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgentCLI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .executable(
            name: "agent",
            targets: ["AgentCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "AgentCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),
            ]
        )
    ]
)
