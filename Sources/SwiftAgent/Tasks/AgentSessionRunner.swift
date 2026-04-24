//
//  AgentSessionRunner.swift
//  SwiftAgent
//

import Foundation

/// Programmatic one-shot runner for an `AgentTaskEnvelope`.
///
/// `AgentSession` owns a transport loop. `AgentSessionRunner` owns one task
/// execution and is intended for dispatch, coordination, and peer execution.
public struct AgentSessionRunner: Sendable {
    private let configuration: AgentSessionRunnerConfiguration

    #if OpenFoundationModels
    private let model: any LanguageModel

    public init(
        model: any LanguageModel,
        configuration: AgentSessionRunnerConfiguration
    ) {
        self.model = model
        self.configuration = configuration
    }
    #else
    public init(configuration: AgentSessionRunnerConfiguration) {
        self.configuration = configuration
    }
    #endif

    /// Runs a single task and returns its terminal result.
    @discardableResult
    public func run(_ envelope: AgentTaskEnvelope) async throws -> AgentTaskResult {
        await emit(.taskStarted(AgentTaskStarted(
            taskID: envelope.id,
            correlationID: envelope.correlationID,
            sessionID: envelope.sessionID,
            turnID: envelope.turnID
        )))

        let runResult: RunResult
        if let deadline = envelope.policy.deadline, Date() > deadline {
            runResult = await emitAdmissionFailure(
                envelope: envelope,
                status: .timedOut,
                error: AgentSessionRunnerError.deadlineExceeded(deadline)
            )
        } else {
            let executor = AgentTurnExecutor(
                conversation: makeConversation(for: envelope),
                approvalHandler: configuration.approvalHandler
            ) { event in
                await emit(.runEvent(AgentTaskRunEvent(
                    taskID: envelope.id,
                    correlationID: envelope.correlationID,
                    event: event
                )))
            }
            runResult = await executor.execute(request: envelope.runRequest)
        }

        let result = AgentTaskResult(envelope: envelope, runResult: runResult)
        await emit(.taskCompleted(AgentTaskCompleted(result: result)))
        return result
    }

    /// Runs a task and exposes task-scoped events as an async stream.
    public func stream(
        _ envelope: AgentTaskEnvelope
    ) -> AsyncThrowingStream<AgentTaskEvent, Error> {
        AsyncThrowingStream { continuation in
            var streamingConfiguration = configuration
            let inheritedHandler = configuration.eventHandler
            streamingConfiguration.eventHandler = { event in
                await inheritedHandler?(event)
                continuation.yield(event)
            }

            #if OpenFoundationModels
            let runner = AgentSessionRunner(model: model, configuration: streamingConfiguration)
            #else
            let runner = AgentSessionRunner(configuration: streamingConfiguration)
            #endif

            let task = Task {
                do {
                    _ = try await runner.run(envelope)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func makeConversation(for envelope: AgentTaskEnvelope) -> Conversation {
        let runtime = ToolRuntime(configuration: runtimeConfiguration(for: envelope.policy.toolScope))

        #if OpenFoundationModels
        let languageModelSession = LanguageModelSession(model: model, tools: runtime.publicTools()) {
            configuration.instructions()
        }
        #else
        let languageModelSession = LanguageModelSession(tools: runtime.publicTools()) {
            configuration.instructions()
        }
        #endif

        return Conversation(
            id: envelope.sessionID,
            languageModelSession: languageModelSession
        ) {
            configuration.step()
        }
    }

    private func runtimeConfiguration(for toolScope: AgentToolScope) -> ToolRuntimeConfiguration {
        switch toolScope {
        case .all:
            var runtimeConfiguration = configuration.runtimeConfiguration
            runtimeConfiguration.register(configuration.tools)
            return runtimeConfiguration

        case .none:
            return ToolRuntimeConfiguration(
                middleware: configuration.runtimeConfiguration.middleware
            )

        case .listed(let names):
            let allowed = Set(names)
            var runtimeConfiguration = ToolRuntimeConfiguration(
                middleware: configuration.runtimeConfiguration.middleware,
                publicTools: configuration.runtimeConfiguration.publicTools.filter { allowed.contains($0.name) },
                hiddenTools: configuration.runtimeConfiguration.hiddenTools.filter { allowed.contains($0.name) }
            )
            runtimeConfiguration.register(configuration.tools.filter { allowed.contains($0.name) })
            return runtimeConfiguration
        }
    }

    private func emitAdmissionFailure(
        envelope: AgentTaskEnvelope,
        status: RunStatus,
        error: any Error
    ) async -> RunResult {
        let start = ContinuousClock.now
        await emit(.runEvent(AgentTaskRunEvent(
            taskID: envelope.id,
            correlationID: envelope.correlationID,
            event: .runStarted(RunEvent.RunStarted(
                sessionID: envelope.sessionID,
                turnID: envelope.turnID
            ))
        )))

        let runError = RunEvent.RunError(
            message: error.localizedDescription,
            isFatal: true,
            underlyingError: error,
            sessionID: envelope.sessionID,
            turnID: envelope.turnID
        )

        await emit(.runEvent(AgentTaskRunEvent(
            taskID: envelope.id,
            correlationID: envelope.correlationID,
            event: .error(runError)
        )))

        await emit(.runEvent(AgentTaskRunEvent(
            taskID: envelope.id,
            correlationID: envelope.correlationID,
            event: .runCompleted(RunEvent.RunCompleted(
                sessionID: envelope.sessionID,
                turnID: envelope.turnID,
                status: status
            ))
        )))

        return RunResult(
            sessionID: envelope.sessionID,
            turnID: envelope.turnID,
            status: status,
            error: runError,
            duration: ContinuousClock.now - start
        )
    }

    private func emit(_ event: AgentTaskEvent) async {
        await configuration.eventHandler?(event)
    }
}
