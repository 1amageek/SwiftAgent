import Foundation

enum MCPEnvironmentVariableExpander {
    static func expand(
        _ source: String,
        using environment: [String: String]
    ) throws -> String {
        let expression = try NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
        let sourceRange = NSRange(source.startIndex..., in: source)
        let matches = expression.matches(in: source, range: sourceRange)
        var result = source

        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let replacementRange = Range(match.range, in: result) else {
                continue
            }
            let name = String(source[nameRange])
            guard let value = environment[name] else {
                throw MCPConfigurationError.missingEnvironmentVariable(name)
            }
            result.replaceSubrange(replacementRange, with: value)
        }
        return result
    }
}
