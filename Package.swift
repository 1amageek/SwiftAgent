// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAgent",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "SwiftAgent",
            targets: ["SwiftAgent"]),
        .library(
            name: "SwiftAgentSymbio",
            targets: ["SwiftAgentSymbio"]),
        .library(
            name: "SwiftAgentMCP",
            targets: ["SwiftAgentMCP"]),
        .library(
            name: "AgentTools",
            targets: ["AgentTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", branch: "1.6.1"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        .package(url: "https://github.com/1amageek/swift-actor-runtime.git", from: "0.2.0"),
        .package(url: "https://github.com/1amageek/swift-discovery.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftAgent",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime")
            ]
        ),
        .target(
            name: "SwiftAgentSymbio",
            dependencies: [
                "SwiftAgent",
                .product(name: "Discovery", package: "swift-discovery"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime")
            ]
        ),
        .target(
            name: "SwiftAgentMCP",
            dependencies: [
                "SwiftAgent",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .target(
            name: "AgentTools",
            dependencies: [
                "SwiftAgent",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels")
            ]
        ),
        .testTarget(
            name: "SwiftAgentTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels")
            ]
        ),
        .testTarget(
            name: "AgentsTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels")
            ]
        ),
        .testTarget(
            name: "SwiftAgentSymbioTests",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentSymbio"
            ]
        ),
    ]
)
