import Foundation
import MCP
import SwiftAgent

enum MCPSchemaConverter {
    static func convert(_ schema: GenerationSchema) throws -> MCPValue {
        let data = try JSONEncoder().encode(schema)
        return try JSONDecoder().decode(MCPValue.self, from: data)
    }
}
