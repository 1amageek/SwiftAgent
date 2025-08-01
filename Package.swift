// swift-tools-version: 6.0
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
            name: "AgentTools",
            targets: ["AgentTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", branch: "1.6.1"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftAgent",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing")
            ]
        ),
        .target(
            name: "AgentTools",
            dependencies: ["SwiftAgent"]
        ),
        .testTarget(
            name: "SwiftAgentTests",
            dependencies: ["SwiftAgent", "AgentTools"]
        ),
        .testTarget(
            name: "AgentsTests",
            dependencies: ["SwiftAgent", "AgentTools"]
        ),
    ]
)
