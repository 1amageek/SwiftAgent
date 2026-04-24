//
//  ToolPipelineCompatibilityTests.swift
//  SwiftAgent
//

import Foundation
import Testing
@testable import SwiftAgent

@Suite("ToolPipeline Compatibility")
struct ToolPipelineCompatibilityTests {
    struct EchoTool: Tool {
        let name = "Echo"
        let description = "Echoes a value"

        @Generable
        struct Arguments: Sendable, Codable {
            @Guide(description: "Value to echo")
            let value: String
        }

        typealias Output = String

        func call(arguments: Arguments) async throws -> String {
            arguments.value
        }
    }

    struct RewriteMiddleware: ToolMiddleware {
        func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
            try await next(context.updating(arguments: #"{"value":"rewritten"}"#))
        }
    }

    @available(*, deprecated, message: "Exercises the deprecated ToolPipeline compatibility shim.")
    @Test("Deprecated ToolPipeline wrap still executes middleware")
    func deprecatedToolPipelineWrapExecutesMiddleware() async throws {
        let pipeline = ToolPipeline.empty
            .use(RewriteMiddleware())
        let wrapped = pipeline.wrap(EchoTool())

        let output = try await wrapped.call(arguments: .init(value: "original"))

        #expect(output == "rewritten")
    }
}
