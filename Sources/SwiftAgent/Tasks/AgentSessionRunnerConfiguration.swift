//
//  AgentSessionRunnerConfiguration.swift
//  SwiftAgent
//

import Foundation

/// Local execution environment for `AgentSessionRunner`.
///
/// The configuration is intentionally not part of `AgentTaskEnvelope`: tools,
/// model instructions, approval handlers, and middleware are local authority.
public struct AgentSessionRunnerConfiguration: Sendable {
    public var tools: [any Tool]
    public var runtimeConfiguration: ToolRuntimeConfiguration
    public var approvalHandler: (any ApprovalHandler)?
    public var eventHandler: (@Sendable (AgentTaskEvent) async -> Void)?

    private let makeInstructions: @Sendable () -> Instructions
    private let makeStep: @Sendable () -> AnyStep<Prompt, String>

    public init<S: Step & Sendable>(
        tools: [any Tool] = [],
        runtimeConfiguration: ToolRuntimeConfiguration = .default,
        approvalHandler: (any ApprovalHandler)? = nil,
        eventHandler: (@Sendable (AgentTaskEvent) async -> Void)? = nil,
        @InstructionsBuilder instructions: @escaping @Sendable () -> Instructions,
        @StepBuilder step: @escaping @Sendable () -> S
    ) where S.Input == Prompt, S.Output == String {
        self.tools = tools
        self.runtimeConfiguration = runtimeConfiguration
        self.approvalHandler = approvalHandler
        self.eventHandler = eventHandler
        self.makeInstructions = instructions
        self.makeStep = { AnyStep(step()) }
    }

    func instructions() -> Instructions {
        makeInstructions()
    }

    func step() -> AnyStep<Prompt, String> {
        makeStep()
    }
}
