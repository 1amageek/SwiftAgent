enum WebRequestHeaderPolicy {
    private static let prohibitedNames: Set<String> = [
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

    static func validate(_ headers: [String: String]) throws {
        var normalizedNames: Set<String> = []
        for (name, value) in headers {
            let normalizedName = name.lowercased()
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy(isTokenScalar),
                  value.unicodeScalars.allSatisfy(isFieldValueScalar),
                  normalizedNames.insert(normalizedName).inserted else {
                throw WebHTTPError.invalidRequestHeader(name)
            }
            guard !prohibitedNames.contains(normalizedName) else {
                throw WebHTTPError.prohibitedRequestHeader(name)
            }
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
