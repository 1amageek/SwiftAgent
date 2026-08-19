import Foundation
import MCP
import SwiftAgent

enum MCPArgumentConverter {
    static func toGeneratedContent(
        _ arguments: [String: MCPValue]?
    ) throws -> GeneratedContent {
        let value: MCPValue = .object(arguments ?? [:])
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MCPServerError.argumentEncodingFailed
        }
        return try GeneratedContent(json: json)
    }
}
