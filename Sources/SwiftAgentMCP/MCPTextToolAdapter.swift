import MCP
import SwiftAgent

/// Exposes a SwiftAgent tool whose output is already lossless MCP text.
public struct MCPTextToolAdapter<Base: SwiftAgent.Tool>: MCPServerTool where Base.Output == String {
    private let base: Base

    public init(_ base: Base) {
        self.base = base
    }

    public var name: String { base.name }
    public var description: String { base.description }
    public var parameters: GenerationSchema { base.parameters }

    public func call(arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        try Task.checkCancellation()
        let content = try MCPArgumentConverter.toGeneratedContent(arguments)
        let typedArguments = try Base.Arguments(content)
        let output = try await base.call(arguments: typedArguments)
        try Task.checkCancellation()
        return CallTool.Result(
            content: [.text(text: output, annotations: nil, _meta: nil)]
        )
    }
}
