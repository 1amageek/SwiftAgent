// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SwiftAgent",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
        .library(name: "SwiftAgentSkills", targets: ["SwiftAgentSkills"]),
        .library(name: "SwiftAgentSymbio", targets: ["SwiftAgentSymbio"]),
        .library(name: "SwiftAgentSymbioAgentAdapter", targets: ["SwiftAgentSymbioAgentAdapter"]),
        .library(name: "SwiftAgentSymbioPeerConnectivity", targets: ["SwiftAgentSymbioPeerConnectivity"]),
        .library(name: "SwiftAgentMCP", targets: ["SwiftAgentMCP"]),
        .library(name: "SwiftAgentPlugins", targets: ["SwiftAgentPlugins"]),
        .library(name: "AgentTools", targets: ["AgentTools"]),
    ],
    traits: [
        .trait(name: "OpenFoundationModels"),
        .default(enabledTraits: []),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.4.1"),
        .package(url: "https://github.com/apple/swift-metrics.git", "2.11.0" ..< "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.1")),
        .package(url: "https://github.com/1amageek/swift-skills.git", from: "0.2.1"),
        .package(url: "https://github.com/1amageek/swift-peer-connectivity.git", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/1amageek/swift-networking.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.18.0"),
    ],
    targets: [
        .target(
            name: "SwiftAgent",
            dependencies: [
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Instrumentation", package: "swift-distributed-tracing"),
                .product(name: "Metrics", package: "swift-metrics"),
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
                .product(name: "SwiftSkill", package: "swift-skills"),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels", condition: .when(traits: ["OpenFoundationModels"])),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentSymbio",
            dependencies: [
                .product(name: "NetworkingCore", package: "swift-networking"),
            ],
            swiftSettings: []
        ),
        .target(
            name: "SwiftAgentSymbioAgentAdapter",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentSymbio",
                .product(name: "NetworkingCore", package: "swift-networking"),
                .product(name: "NetworkingFoundationCompat", package: "swift-networking"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentSymbioPeerConnectivity",
            dependencies: [
                "SwiftAgentSymbio",
                .product(name: "PeerConnectivity", package: "swift-peer-connectivity"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NetworkingCore", package: "swift-networking"),
                .product(name: "NetworkingFoundationCompat", package: "swift-networking"),
                .product(name: "NetworkingTime", package: "swift-networking"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentMCP",
            dependencies: [
                "SwiftAgent",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .target(
            name: "SwiftAgentPlugins",
            dependencies: [
                "SwiftAgent",
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
                "SwiftAgentPlugins",
                "AgentTools",
                .product(name: "MetricsTestKit", package: "swift-metrics"),
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
                "SwiftAgentSymbioAgentAdapter",
                .product(name: "NetworkingCore", package: "swift-networking"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "SwiftAgentSymbioPeerConnectivityTests",
            dependencies: [
                "SwiftAgentSymbio",
                "SwiftAgentSymbioPeerConnectivity",
                .product(name: "PeerConnectivity", package: "swift-peer-connectivity"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NetworkingCore", package: "swift-networking"),
                .product(name: "NetworkingTime", package: "swift-networking"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "SwiftAgentSkillsTests",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentSkills",
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
        .testTarget(
            name: "SwiftAgentMCPTests",
            dependencies: [
                "SwiftAgent",
                "SwiftAgentMCP",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: [
                .define("OpenFoundationModels", .when(traits: ["OpenFoundationModels"])),
            ]
        ),
    ]
)
