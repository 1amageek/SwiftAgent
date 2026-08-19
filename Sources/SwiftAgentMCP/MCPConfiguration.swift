import Foundation

/// Decodes `.mcp.json` and converts each enabled entry into a validated connection configuration.
public struct MCPConfiguration: Codable, Sendable {
    public let mcpServers: [String: MCPServerEntry]

    public init(mcpServers: [String: MCPServerEntry] = [:]) {
        self.mcpServers = mcpServers
    }

    public init(from decoder: any Decoder) throws {
        let rawContainer = try decoder.container(
            keyedBy: MCPConfigurationCodingKey.self
        )
        let supportedKeys: Set<String> = [CodingKeys.mcpServers.rawValue]
        if let unknownKey = rawContainer.allKeys
            .map(\.stringValue)
            .filter({ !supportedKeys.contains($0) })
            .sorted()
            .first {
            throw MCPConfigurationError.unknownConfigurationField(unknownKey)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mcpServers = try container.decode(
            [String: MCPServerEntry].self,
            forKey: .mcpServers
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mcpServers, forKey: .mcpServers)
    }

    public static func load(from url: URL) throws -> MCPConfiguration {
        try load(from: Data(contentsOf: url))
    }

    public static func load(from data: Data) throws -> MCPConfiguration {
        try JSONDecoder().decode(MCPConfiguration.self, from: data)
    }

    public static func load(searchPaths: [String]) throws -> MCPConfiguration? {
        for path in searchPaths where FileManager.default.fileExists(atPath: path) {
            return try load(from: URL(fileURLWithPath: path))
        }
        return nil
    }

    public func expandEnvironmentVariables(
        using environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> MCPConfiguration {
        var expanded: [String: MCPServerEntry] = [:]
        expanded.reserveCapacity(mcpServers.count)
        for (name, entry) in mcpServers {
            expanded[name] = try entry.expandingEnvironmentVariables(using: environment)
        }
        return MCPConfiguration(mcpServers: expanded)
    }

    public func serverConfigs() throws -> [MCPServerConfig] {
        try resolvedServerConfigs()
            .filter { $0.isEnabled }
            .map { $0.config }
    }

    public func resolvedServerConfigs() throws -> [(
        config: MCPServerConfig,
        isEnabled: Bool
    )] {
        try mcpServers.sorted { $0.key < $1.key }.map { name, entry in
            (
                config: try entry.serverConfig(name: name),
                isEnabled: entry.disabled != true
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mcpServers
    }
}
