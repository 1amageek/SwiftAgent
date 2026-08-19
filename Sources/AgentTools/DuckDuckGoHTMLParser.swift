import Foundation

enum DuckDuckGoHTMLParser {
    static func parse(
        _ html: String,
        limit: Int
    ) throws -> [WebSearchResult] {
        let expression = try NSRegularExpression(
            pattern: #"<a([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let hrefExpression = try NSRegularExpression(
            pattern: #"href\s*=\s*[\"']([^\"']+)[\"']"#,
            options: [.caseInsensitive]
        )
        let classExpression = try NSRegularExpression(
            pattern: #"class\s*=\s*[\"']([^\"']+)[\"']"#,
            options: [.caseInsensitive]
        )
        let tagExpression = try NSRegularExpression(
            pattern: #"<[^>]+>"#,
            options: [.caseInsensitive]
        )

        let matches = expression.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        )
        var seenURLs: Set<URL> = []
        var results: [WebSearchResult] = []
        for match in matches {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let attributes = String(html[attributesRange])
            guard let className = firstCapture(
                in: attributes,
                expression: classExpression
            ),
            className.split(whereSeparator: { $0.isWhitespace })
                .contains("result__a"),
            let href = firstCapture(
                in: attributes,
                expression: hrefExpression
            ),
            let url = resultURL(from: href),
            seenURLs.insert(url).inserted else {
                continue
            }

            let rawTitle = String(html[titleRange])
            let titleWithoutTags = tagExpression.stringByReplacingMatches(
                in: rawTitle,
                range: NSRange(rawTitle.startIndex..., in: rawTitle),
                withTemplate: ""
            )
            let title = HTMLToMarkdown.decodeHTMLEntities(titleWithoutTags)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                continue
            }
            results.append(WebSearchResult(
                title: title,
                url: url,
                snippet: ""
            ))
            if results.count == limit {
                break
            }
        }
        return results
    }

    private static func firstCapture(
        in value: String,
        expression: NSRegularExpression
    ) -> String? {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let capture = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[capture])
    }

    private static func resultURL(from href: String) -> URL? {
        let decoded = HTMLToMarkdown.decodeHTMLEntities(href)
        guard let baseURL = URL(string: "https://html.duckduckgo.com"),
              let candidate = URL(
            string: decoded,
            relativeTo: baseURL
        )?.absoluteURL else {
            return nil
        }
        let host = candidate.host.map(WebOrigin.normalize) ?? ""
        if host == "duckduckgo.com"
            || host.hasSuffix(".duckduckgo.com") {
            guard let components = URLComponents(
                url: candidate,
                resolvingAgainstBaseURL: false
            ),
            let target = components.queryItems?.first(
                where: { $0.name == "uddg" }
            )?.value,
            let targetURL = URL(string: target) else {
                return nil
            }
            return validatedResultURL(targetURL)
        }
        return validatedResultURL(candidate)
    }

    private static func validatedResultURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}
