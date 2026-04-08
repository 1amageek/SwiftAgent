//
//  PluginHookMiddleware.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Executes plugin lifecycle hooks around every tool invocation.
public struct PluginHookMiddleware: ToolMiddleware, Sendable {
    public let hookRunner: PluginHookRunner

    public init(hookRunner: PluginHookRunner) {
        self.hookRunner = hookRunner
    }

    public func handle(
        _ context: ToolContext,
        next: @escaping Next
    ) async throws -> ToolResult {
        let preResult = try await hookRunner.runPreToolUse(
            toolName: context.toolName,
            toolInput: context.arguments
        )
        if preResult.failed {
            throw PluginHookError.failed(messages: preResult.messages)
        }
        if preResult.denied {
            throw PluginHookError.denied(messages: preResult.messages)
        }

        var updatedContext = context
        if let updatedInput = preResult.updatedInput {
            updatedContext = updatedContext.updating(arguments: updatedInput)
        }
        updatedContext = updatedContext.mergingMetadata(metadata(from: preResult))

        let result = try await next(updatedContext)

        if result.success {
            let postResult = try await hookRunner.runPostToolUse(
                toolName: updatedContext.toolName,
                toolInput: updatedContext.arguments,
                toolOutput: result.output,
                isError: false
            )
            if postResult.failed {
                return .failure(PluginHookError.failed(messages: postResult.messages), duration: result.duration)
            }
            if postResult.denied {
                return .failure(PluginHookError.denied(messages: postResult.messages), duration: result.duration)
            }
            return result
        }

        let failureResult = try await hookRunner.runPostToolUseFailure(
            toolName: updatedContext.toolName,
            toolInput: updatedContext.arguments,
            toolError: result.output
        )
        if failureResult.failed {
            return .failure(PluginHookError.failed(messages: failureResult.messages), duration: result.duration)
        }
        if failureResult.denied {
            return .failure(PluginHookError.denied(messages: failureResult.messages), duration: result.duration)
        }
        return result
    }

    private func metadata(from result: PluginHookRunResult) -> [String: String] {
        var metadata: [String: String] = [:]
        if let authorizationDecision = result.authorizationDecision {
            metadata[ToolAuthorizationMetadata.decisionKey] = authorizationDecision.rawValue
        }
        if let authorizationReason = result.authorizationReason {
            metadata[ToolAuthorizationMetadata.reasonKey] = authorizationReason
        }
        return metadata
    }
}
