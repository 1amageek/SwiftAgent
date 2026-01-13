// swift-tools-version: 6.2
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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels-Claude.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "AgentCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),
                .product(name: "OpenFoundationModelsOpenAI", package: "OpenFoundationModels-OpenAI"),
                .product(name: "OpenFoundationModelsClaude", package: "OpenFoundationModels-Claude")
            ]
        )
    ]
)