//
//  HookResult.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// The result of a hook execution.
///
/// Hooks return results that can influence the execution flow,
/// modify inputs/outputs, or provide feedback to the system.
public enum HookResult: Sendable {

    // MARK: - Control Flow

    /// Continue with the operation as normal.
    case `continue`

    /// Block the operation entirely.
    ///
    /// - Parameter reason: Optional explanation for blocking.
    case block(reason: String?)

    /// Stop the agent entirely.
    ///
    /// - Parameters:
    ///   - reason: Message shown to user.
    ///   - output: Optional final output.
    case stop(reason: String, output: String?)

    // MARK: - Permission Decisions

    /// Allow the operation (for permission-related hooks).
    case allow

    /// Deny the operation (for permission-related hooks).
    ///
    /// - Parameter reason: Optional explanation for denial.
    case deny(reason: String?)

    /// Require user confirmation.
    case ask

    // MARK: - Modification

    /// Allow with modified input.
    ///
    /// - Parameter modifiedInput: The modified JSON-encoded input.
    case allowWithModifiedInput(String)

    /// Continue with modified prompt (for userPromptSubmit).
    ///
    /// - Parameter modifiedPrompt: The modified prompt text.
    case continueWithModifiedPrompt(String)

    /// Add context message to the conversation.
    ///
    /// - Parameter message: The context message to add.
    case addContext(String)

    // MARK: - Output Control

    /// Suppress output from being shown/logged.
    case suppressOutput

    /// Replace output with custom message.
    ///
    /// - Parameter output: The replacement output.
    case replaceOutput(String)
}

// MARK: - Properties

extension HookResult {

    /// Whether this result allows the operation to proceed.
    public var allowsExecution: Bool {
        switch self {
        case .continue, .allow, .allowWithModifiedInput, .continueWithModifiedPrompt, .addContext:
            return true
        case .block, .deny, .stop:
            return false
        case .ask:
            return false // Needs further confirmation
        case .suppressOutput, .replaceOutput:
            return true
        }
    }

    /// Whether this result modifies input/output.
    public var modifiesData: Bool {
        switch self {
        case .allowWithModifiedInput, .continueWithModifiedPrompt, .addContext, .replaceOutput:
            return true
        default:
            return false
        }
    }

    /// Whether this result stops the agent.
    public var stopsAgent: Bool {
        switch self {
        case .stop:
            return true
        default:
            return false
        }
    }
}

// MARK: - Aggregation

/// Result of aggregating multiple hook results.
public struct AggregatedHookResult: Sendable {

    /// The final decision (most restrictive wins).
    public let decision: HookResult

    /// Modified input (if any hook modified it).
    public let modifiedInput: String?

    /// Context messages to add.
    public let contextMessages: [String]

    /// Whether to suppress output.
    public let suppressOutput: Bool

    /// Combined reasons from all hooks.
    public let reasons: [String]

    /// Creates an aggregated result.
    public init(
        decision: HookResult,
        modifiedInput: String? = nil,
        contextMessages: [String] = [],
        suppressOutput: Bool = false,
        reasons: [String] = []
    ) {
        self.decision = decision
        self.modifiedInput = modifiedInput
        self.contextMessages = contextMessages
        self.suppressOutput = suppressOutput
        self.reasons = reasons
    }

    /// Aggregates multiple hook results.
    ///
    /// Rules:
    /// - `stop` takes precedence over everything
    /// - `block`/`deny` takes precedence over `ask`
    /// - `ask` takes precedence over `allow`/`continue`
    /// - Modifications are applied in order
    public static func aggregate(_ results: [HookResult]) -> AggregatedHookResult {
        var finalDecision: HookResult = .continue
        var modifiedInput: String?
        var contextMessages: [String] = []
        var suppressOutput = false
        var reasons: [String] = []

        for result in results {
            switch result {
            case .stop(let reason, _):
                // Stop takes highest precedence
                return AggregatedHookResult(
                    decision: result,
                    modifiedInput: modifiedInput,
                    contextMessages: contextMessages,
                    suppressOutput: suppressOutput,
                    reasons: reasons + [reason]
                )

            case .block(let reason), .deny(let reason):
                // Block/Deny takes precedence over ask/allow
                if case .stop = finalDecision {
                    // Keep stop
                } else {
                    finalDecision = result
                    if let r = reason {
                        reasons.append(r)
                    }
                }

            case .ask:
                // Ask takes precedence over allow/continue
                switch finalDecision {
                case .stop, .block, .deny:
                    break // Keep more restrictive
                default:
                    finalDecision = .ask
                }

            case .allowWithModifiedInput(let input):
                modifiedInput = input
                if case .continue = finalDecision {
                    finalDecision = .allow
                }

            case .continueWithModifiedPrompt(let prompt):
                modifiedInput = prompt

            case .addContext(let message):
                contextMessages.append(message)

            case .suppressOutput:
                suppressOutput = true

            case .replaceOutput(let output):
                modifiedInput = output

            case .allow:
                if case .continue = finalDecision {
                    finalDecision = .allow
                }

            case .continue:
                break // Default, no change
            }
        }

        return AggregatedHookResult(
            decision: finalDecision,
            modifiedInput: modifiedInput,
            contextMessages: contextMessages,
            suppressOutput: suppressOutput,
            reasons: reasons
        )
    }
}

// MARK: - CustomStringConvertible

extension HookResult: CustomStringConvertible {

    public var description: String {
        switch self {
        case .continue:
            return "Continue"
        case .block(let reason):
            return "Block: \(reason ?? "No reason")"
        case .stop(let reason, _):
            return "Stop: \(reason)"
        case .allow:
            return "Allow"
        case .deny(let reason):
            return "Deny: \(reason ?? "No reason")"
        case .ask:
            return "Ask"
        case .allowWithModifiedInput:
            return "Allow (modified)"
        case .continueWithModifiedPrompt:
            return "Continue (modified prompt)"
        case .addContext(let msg):
            return "Add context: \(msg.prefix(50))..."
        case .suppressOutput:
            return "Suppress output"
        case .replaceOutput:
            return "Replace output"
        }
    }
}
