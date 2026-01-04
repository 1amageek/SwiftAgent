// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// By default, SwiftAgent uses Apple's FoundationModels framework.
// Set USE_OTHER_MODELS=1 to use OpenFoundationModels for development/testing with other LLM providers.
// Example: USE_OTHER_MODELS=1 swift build
let useOtherModels = ProcessInfo.processInfo.environment["USE_OTHER_MODELS"] != nil

let package = Package(
    name: "SwiftAgent",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
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
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.0.1"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        .package(url: "https://github.com/1amageek/swift-actor-runtime.git", from: "0.2.0"),
        .package(url: "https://github.com/1amageek/swift-discovery.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftAgent",
            dependencies: [
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime")
            ] + (useOtherModels ? [.product(name: "OpenFoundationModels", package: "OpenFoundationModels")] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .target(
            name: "SwiftAgentSymbio",
            dependencies: [
                "SwiftAgent",
                .product(name: "Discovery", package: "swift-discovery"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime")
            ],
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .target(
            name: "SwiftAgentMCP",
            dependencies: [
                "SwiftAgent",
                .product(name: "MCP", package: "swift-sdk")
            ],
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .target(
            name: "AgentTools",
            dependencies: [
                "SwiftAgent"
            ] + (useOtherModels ? [.product(name: "OpenFoundationModels", package: "OpenFoundationModels")] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .testTarget(
            name: "SwiftAgentTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools"
            ] + (useOtherModels ? [.product(name: "OpenFoundationModels", package: "OpenFoundationModels")] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .testTarget(
            name: "AgentsTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools"
            ] + (useOtherModels ? [.product(name: "OpenFoundationModels", package: "OpenFoundationModels")] : []),
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
        .testTarget(
            name: "SwiftAgentSymbioTests",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentSymbio"
            ],
            swiftSettings: useOtherModels ? [.define("USE_OTHER_MODELS")] : []
        ),
    ]
)
