import Foundation

enum HTMLToMarkdown {
    static func convert(_ html: String) throws -> String {
        var result = html
        for tag in ["script", "style", "noscript", "head", "nav", "footer"] {
            result = try removeTag(result, tag: tag)
        }
        for level in 1...6 {
            result = try replacePattern(
                result,
                pattern: "<h\(level)[^>]*>(.*?)</h\(level)>",
                replacement: "\(String(repeating: "#", count: level)) $1\n\n"
            )
        }
        result = try replacePattern(
            result,
            pattern: "<p[^>]*>(.*?)</p>",
            replacement: "$1\n\n"
        )
        result = try replacePattern(
            result,
            pattern: "<br\\s*/?>",
            replacement: "\n"
        )
        for tag in ["strong", "b"] {
            result = try replacePattern(
                result,
                pattern: "<\(tag)[^>]*>(.*?)</\(tag)>",
                replacement: "**$1**"
            )
        }
        for tag in ["em", "i"] {
            result = try replacePattern(
                result,
                pattern: "<\(tag)[^>]*>(.*?)</\(tag)>",
                replacement: "*$1*"
            )
        }
        result = try replacePattern(
            result,
            pattern: "<code[^>]*>(.*?)</code>",
            replacement: "`$1`"
        )
        result = try replacePattern(
            result,
            pattern: "<pre[^>]*>(.*?)</pre>",
            replacement: "```\n$1\n```\n\n"
        )
        result = try replacePattern(
            result,
            pattern: "<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            replacement: "[$2]($1)"
        )
        result = try replacePattern(
            result,
            pattern: "<li[^>]*>(.*?)</li>",
            replacement: "- $1\n"
        )
        result = try replacePattern(
            result,
            pattern: "</?(?:ul|ol)[^>]*>",
            replacement: "\n"
        )
        result = try replacePattern(
            result,
            pattern: "<blockquote[^>]*>(.*?)</blockquote>",
            replacement: "> $1\n\n"
        )
        result = try replacePattern(
            result,
            pattern: "<div[^>]*>(.*?)</div>",
            replacement: "$1\n"
        )
        result = try replacePattern(
            result,
            pattern: "<span[^>]*>(.*?)</span>",
            replacement: "$1"
        )
        result = try replacePattern(
            result,
            pattern: "<[^>]+>",
            replacement: ""
        )
        result = decodeHTMLEntities(result)
        return try cleanWhitespace(result)
    }

    static func decodeHTMLEntities(_ string: String) -> String {
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
        ]
        return entities.reduce(string) { result, entity in
            result.replacingOccurrences(of: entity.0, with: entity.1)
        }
    }

    private static func removeTag(
        _ html: String,
        tag: String
    ) throws -> String {
        try replacePattern(
            html,
            pattern: "<\(tag)[^>]*>.*?</\(tag)>",
            replacement: ""
        )
    }

    private static func replacePattern(
        _ string: String,
        pattern: String,
        replacement: String,
        options: NSRegularExpression.Options = [
            .caseInsensitive,
            .dotMatchesLineSeparators,
        ]
    ) throws -> String {
        let expression = try NSRegularExpression(
            pattern: pattern,
            options: options
        )
        return expression.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: replacement
        )
    }

    private static func cleanWhitespace(_ string: String) throws -> String {
        var result = try replacePattern(
            string,
            pattern: "\n{3,}",
            replacement: "\n\n",
            options: []
        )
        result = try replacePattern(
            result,
            pattern: " {2,}",
            replacement: " ",
            options: []
        )
        return result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
