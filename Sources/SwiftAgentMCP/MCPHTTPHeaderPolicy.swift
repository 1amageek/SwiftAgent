enum MCPHTTPHeaderPolicy {
    private static let prohibitedNames: Set<String> = [
        "authorization",
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "proxy-connection",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    ]

    static func validate(
        _ headers: [String: String],
        server: String
    ) throws {
        var normalizedNames: Set<String> = []
        for (name, value) in headers {
            let normalizedName = name.lowercased()
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy(isTokenScalar),
                  value.unicodeScalars.allSatisfy(isFieldValueScalar),
                  normalizedNames.insert(normalizedName).inserted else {
                throw MCPConfigurationError.invalidHTTPHeader(
                    server: server,
                    name: name
                )
            }
            guard !prohibitedNames.contains(normalizedName) else {
                throw MCPConfigurationError.prohibitedHTTPHeader(
                    server: server,
                    name: name
                )
            }
        }
    }

    static func validateAuthorizationValue(
        _ value: String,
        server: String
    ) throws {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy(isFieldValueScalar) else {
            throw MCPConfigurationError.invalidAuthorizationValue(server: server)
        }
    }

    static func validateOAuthScope(
        _ value: String,
        server: String
    ) throws {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.value == 33
                      || (35...91).contains(scalar.value)
                      || (93...126).contains(scalar.value)
              }) else {
            throw MCPConfigurationError.invalidAuthorizationValue(server: server)
        }
    }

    private static func isTokenScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126:
            return true
        default:
            return false
        }
    }

    private static func isFieldValueScalar(_ scalar: UnicodeScalar) -> Bool {
        scalar.value == 9 || (scalar.value >= 32 && scalar.value != 127)
    }
}
