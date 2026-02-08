// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftAgent",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
        .library(name: "SwiftAgentSkills", targets: ["SwiftAgentSkills"]),
        .library(name: "SwiftAgentSymbio", targets: ["SwiftAgentSymbio"]),
        .library(name: "SwiftAgentMCP", targets: ["SwiftAgentMCP"]),
        .library(name: "AgentTools", targets: ["AgentTools"]),
    ],
    traits: [
        .trait(name: "OpenFoundationModels"),
        .default(enabledTraits: []),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", branch: "1.6.1"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        .package(url: "https://github.com/1amageek/swift-actor-runtime.git", from: "0.2.0"),
        .package(url: "https://github.com/1amageek/swift-discovery.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.3"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.1.1"),
    ],
    targets: [
        .macro(
            name: "SwiftAgentMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "SwiftAgent",
            dependencies: [
                "SwiftAgentMacros",
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime"),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentSkills",
            dependencies: [
                "SwiftAgent",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentSymbio",
            dependencies: [
                "SwiftAgent",
                .product(name: "Discovery", package: "swift-discovery"),
                .product(name: "ActorRuntime", package: "swift-actor-runtime"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentMCP",
            dependencies: [
                "SwiftAgent",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "AgentTools",
            dependencies: [
                "SwiftAgent",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "SwiftAgentTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "AgentsTests",
            dependencies: [
                "SwiftAgent",
                "AgentTools",
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "SwiftAgentSymbioTests",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentSymbio",
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
    ]
)
