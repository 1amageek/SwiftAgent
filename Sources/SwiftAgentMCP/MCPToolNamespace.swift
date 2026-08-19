enum MCPToolNamespace {
    private static let modelPrefix = "mcp__"

    static func isValidComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }

    static func isValidServerName(_ value: String) -> Bool {
        guard isValidComponent(value) else {
            return false
        }
        let prefixLength = modelPrefix.utf8.count
            + String(value.utf8.count).utf8.count
            + 1
            + value.utf8.count
            + 2
        return prefixLength < 128
    }

    static func qualifiedName(
        serverName: String,
        toolName: String
    ) throws -> String {
        guard isValidComponent(toolName) else {
            throw MCPToolError.invalidToolNamespace(
                server: serverName,
                tool: toolName
            )
        }
        let qualifiedName = try qualifiedPrefix(serverName: serverName) + toolName
        guard qualifiedName.utf8.count <= 128 else {
            throw MCPToolError.invalidToolNamespace(
                server: serverName,
                tool: toolName
            )
        }
        return qualifiedName
    }

    static func qualifiedPrefix(serverName: String) throws -> String {
        guard isValidServerName(serverName) else {
            throw MCPToolError.invalidToolNamespace(
                server: serverName,
                tool: "*"
            )
        }
        return "\(modelPrefix)\(serverName.utf8.count)_\(serverName)__"
    }
}
