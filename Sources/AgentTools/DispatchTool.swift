//
//  DispatchTool.swift
//  AgentTools
//
//  Sub-LLM delegation tool for recursive reasoning.
//

import Foundation
import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels
#endif

/// A tool that delegates sub-tasks to separate LLM sessions for recursive reasoning.
///
/// Inspired by RLM (Recursive Language Models), `DispatchTool` creates fresh
/// `LanguageModelSession` instances with access to the shared `Notebook` for
/// context storage, and optionally itself for recursive delegation.
///
/// ## Operations
/// - `query`: Single sub-LLM call with task and context
/// - `query_batched`: Parallel sub-LLM calls with multiple tasks sharing context
///
/// ## Sub-session capabilities
/// - **Notebook**: Read/write shared scratchpad (same storage as parent)
/// - **Dispatch**: Recursive delegation (depth-limited to prevent infinite recursion)
/// - **Runtime middleware**: Sub-session tools execute through `ToolRuntime`
///   so permission, event, and metrics middleware can observe nested tool use
///
/// ## Typical workflow (RLM pattern)
/// 1. Parent stores large data in Notebook
/// 2. Parent calls Dispatch to analyze chunks in parallel via `query_batched`
/// 3. Sub-sessions read from Notebook, store partial results back
/// 4. Parent reads aggregated results from Notebook
public struct DispatchTool: Tool {
    public typealias Arguments = DispatchInput
    public typealias Output = DispatchOutput

    public static let name = "Dispatch"
    public var name: String { Self.name }

    /// Maximum recursion depth for nested Dispatch calls.
    public static let defaultMaxDepth = 3

    /// Task separator for `query_batched` operation.
    public static let batchSeparator = "\n---\n"

    public static let description = """
    Launch a sub-session to handle a focused sub-task autonomously.

    Usage:
    - Sub-sessions have access to the shared Notebook for reading/writing data and can recursively dispatch further sub-tasks (depth-limited)
    - The sub-session has NO access to the parent's conversation history. Provide all necessary context in the "context" field or store it in Notebook beforehand
    - Launch multiple sub-tasks concurrently whenever possible to maximize performance
    - Provide clear, detailed prompts so the sub-session can work autonomously and return exactly the information you need
    - Clearly tell the sub-session whether you expect it to produce analysis or just gather information

    Operations:
    - "query": Single sub-task with task description and context
    - "query_batched": Parallel execution of multiple independent sub-tasks (separate tasks with "\\n---\\n")

    When to use:
    - Open-ended codebase searches requiring multiple rounds of globbing and grepping
    - Analyzing different chunks of data stored in Notebook in parallel
    - Focused reasoning on a specific sub-problem without polluting the parent context
    - Multiple independent questions that can be processed in parallel via query_batched
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        DispatchInput.generationSchema
    }

    // MARK: - Properties

    private let notebookStorage: NotebookStorage
    private let currentDepth: Int
    private let maxDepth: Int
    private let runtimeConfiguration: ToolRuntimeConfiguration
    private let additionalTools: [any Tool]
    private let instructions: String

    #if OpenFoundationModels
    private let languageModel: any LanguageModel

    /// Creates a DispatchTool with a language model and shared notebook.
    ///
    /// - Parameters:
    ///   - languageModel: The language model for sub-sessions.
    ///   - notebookStorage: Shared notebook storage. Defaults to a new instance.
    ///   - maxDepth: Maximum recursion depth. Defaults to 3.
    ///   - currentDepth: Current recursion depth. Defaults to 0.
    public init(
        languageModel: any LanguageModel,
        notebookStorage: NotebookStorage = NotebookStorage(),
        maxDepth: Int = defaultMaxDepth,
        currentDepth: Int = 0,
        runtimeConfiguration: ToolRuntimeConfiguration = .default,
        additionalTools: [any Tool] = [],
        instructions: String? = nil
    ) {
        self.languageModel = languageModel
        self.notebookStorage = notebookStorage
        self.maxDepth = maxDepth
        self.currentDepth = currentDepth
        self.runtimeConfiguration = runtimeConfiguration
        self.additionalTools = additionalTools
        self.instructions = instructions ?? Self.defaultInstructions
    }
    #else
    /// Creates a DispatchTool with shared notebook.
    ///
    /// - Parameters:
    ///   - notebookStorage: Shared notebook storage. Defaults to a new instance.
    ///   - maxDepth: Maximum recursion depth. Defaults to 3.
    ///   - currentDepth: Current recursion depth. Defaults to 0.
    public init(
        notebookStorage: NotebookStorage = NotebookStorage(),
        maxDepth: Int = defaultMaxDepth,
        currentDepth: Int = 0,
        runtimeConfiguration: ToolRuntimeConfiguration = .default,
        additionalTools: [any Tool] = [],
        instructions: String? = nil
    ) {
        self.notebookStorage = notebookStorage
        self.maxDepth = maxDepth
        self.currentDepth = currentDepth
        self.runtimeConfiguration = runtimeConfiguration
        self.additionalTools = additionalTools
        self.instructions = instructions ?? Self.defaultInstructions
    }
    #endif

    // MARK: - Tool Execution

    public func call(arguments: DispatchInput) async throws -> DispatchOutput {
        switch arguments.operation.lowercased() {
        case "query":
            return try await executeQuery(task: arguments.task, context: arguments.context)
        case "query_batched":
            return try await executeQueryBatched(tasks: arguments.task, context: arguments.context)
        default:
            throw DispatchError.invalidOperation(arguments.operation)
        }
    }

    // MARK: - Single Query

    private func executeQuery(task: String, context: String) async throws -> DispatchOutput {
        do {
            let result = try await runSubtask(task: task, context: context)
            return DispatchOutput(
                content: result.content,
                success: true,
                operation: "query",
                taskCount: 1,
                sessionIDs: [result.sessionID]
            )
        } catch {
            throw DispatchError.sessionFailed(error.localizedDescription)
        }
    }

    // MARK: - Batched Query (Parallel)

    private func executeQueryBatched(tasks: String, context: String) async throws -> DispatchOutput {
        let taskList = tasks
            .components(separatedBy: Self.batchSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !taskList.isEmpty else {
            throw DispatchError.emptyBatch
        }

        // Best-effort: collect successes, don't cancel others on individual failure
        let results: [(Int, Result<SubtaskResult, Error>)] = await withTaskGroup(
            of: (Int, Result<SubtaskResult, Error>).self
        ) { group in
            for (index, task) in taskList.enumerated() {
                group.addTask {
                    do {
                        let result = try await runSubtask(task: task, context: context)
                        return (index, .success(result))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            var collected: [(Int, Result<SubtaskResult, Error>)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Sort by original index to preserve order
        let sortedResults = results.sorted { $0.0 < $1.0 }

        var successes: [String] = []
        var failures: [String] = []
        var sessionIDs: [String] = []
        for (index, result) in sortedResults {
            switch result {
            case .success(let subtask):
                sessionIDs.append(subtask.sessionID)
                successes.append("[\(index + 1)/\(taskList.count)] \(subtask.content)")
            case .failure(let error):
                failures.append("[\(index + 1)/\(taskList.count)] ERROR: \(error.localizedDescription)")
            }
        }

        guard !successes.isEmpty else {
            throw DispatchError.allTasksFailed(count: taskList.count)
        }

        let allParts = successes + (failures.isEmpty ? [] : failures)
        let content = allParts.joined(separator: "\n\n---\n\n")

        return DispatchOutput(
            content: content,
            success: failures.isEmpty,
            operation: "query_batched",
            taskCount: taskList.count,
            sessionIDs: sessionIDs
        )
    }

    // MARK: - Session Factory

    private struct SubtaskResult: Sendable {
        let sessionID: String
        let content: String
    }

    private func runSubtask(task: String, context: String) async throws -> SubtaskResult {
        let prompt = buildPrompt(task: task, context: context)
        let sessionID = UUID().uuidString
        let envelope = makeEnvelope(sessionID: sessionID, prompt: prompt)
        let runnerConfiguration = makeRunnerConfiguration(sessionID: sessionID)

        #if OpenFoundationModels
        let runner = AgentSessionRunner(model: languageModel, configuration: runnerConfiguration)
        #else
        let runner = AgentSessionRunner(configuration: runnerConfiguration)
        #endif

        let result = try await runner.run(envelope)
        guard result.status == .completed, let content = result.finalOutput else {
            throw DispatchError.sessionFailed(result.error?.message ?? "Sub-session ended with status \(result.status.rawValue)")
        }
        return SubtaskResult(sessionID: sessionID, content: content)
    }

    private func makeEnvelope(sessionID: String, prompt: String) -> AgentTaskEnvelope {
        var metadata: [String: String] = [
            "dispatchDepth": "\(currentDepth)",
        ]
        if let parent = AgentSessionContext.current {
            metadata["parentSessionID"] = parent.sessionID
            metadata["parentTurnID"] = parent.turnID
        }

        return AgentTaskEnvelope(
            requesterID: AgentSessionContext.current?.sessionID,
            sessionID: sessionID,
            relation: .delegated(parentTaskID: nil),
            input: .text(prompt),
            metadata: metadata
        )
    }

    private func makeRunnerConfiguration(sessionID: String) -> AgentSessionRunnerConfiguration {
        let instructions = self.instructions
        return AgentSessionRunnerConfiguration(
            tools: makeSubTools(),
            runtimeConfiguration: runtimeConfiguration
        ) {
            Instructions {
                instructions
                "Dispatch sub-session ID: \(sessionID)"
            }
        } step: {
            GenerateText<Prompt>()
        }
    }

    private func makeSubTools() -> [any Tool] {
        var tools: [any Tool] = [
            NotebookTool(storage: notebookStorage)
        ]
        tools.append(contentsOf: additionalTools)

        // Add recursive Dispatch if depth allows
        if currentDepth < maxDepth {
            #if OpenFoundationModels
            tools.append(DispatchTool(
                languageModel: languageModel,
                notebookStorage: notebookStorage,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1,
                runtimeConfiguration: runtimeConfiguration,
                additionalTools: additionalTools,
                instructions: instructions
            ))
            #else
            tools.append(DispatchTool(
                notebookStorage: notebookStorage,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1,
                runtimeConfiguration: runtimeConfiguration,
                additionalTools: additionalTools,
                instructions: instructions
            ))
            #endif
        }

        return tools
    }

    // MARK: - Private

    private func buildPrompt(task: String, context: String) -> String {
        if context.isEmpty {
            return task
        }
        return """
        <context>
        \(context)
        </context>

        <task>
        \(task)
        </task>
        """
    }

    private static var defaultInstructions: String {
        """
        You are a focused reasoning sub-agent with access to a shared Notebook. \
        Use Notebook to read context data stored by the parent agent and to store your results. \
        Answer the task directly and concisely based on the provided context. \
        If the task is complex, you can use Dispatch to further delegate sub-tasks.
        """
    }
}

// MARK: - Input/Output Types

/// Input structure for dispatch operations.
@Generable
public struct DispatchInput: Sendable {
    @Guide(description: "Operation: 'query' for single sub-task, 'query_batched' for parallel execution (separate tasks with \\n---\\n)", .anyOf(["query", "query_batched"]))
    public let operation: String

    @Guide(description: "Task description. For query_batched, separate multiple tasks with \\n---\\n")
    public let task: String

    @Guide(description: "Shared context for the sub-session(s). The sub-session has no access to conversation history, so provide all necessary context here or reference Notebook keys.")
    public let context: String

    public init(
        operation: String,
        task: String,
        context: String = ""
    ) {
        self.operation = operation
        self.task = task
        self.context = context
    }
}

/// Output structure for dispatch operations.
public struct DispatchOutput: Sendable {
    public let content: String
    public let success: Bool
    public let operation: String
    public let taskCount: Int
    public let sessionIDs: [String]

    public init(
        content: String,
        success: Bool,
        operation: String = "query",
        taskCount: Int = 1,
        sessionIDs: [String] = []
    ) {
        self.content = content
        self.success = success
        self.operation = operation
        self.taskCount = taskCount
        self.sessionIDs = sessionIDs
    }
}

extension DispatchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension DispatchOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let countInfo = taskCount > 1 ? " (\(taskCount) tasks)" : ""
        let sessionInfo = sessionIDs.isEmpty ? "" : "\nSub-sessions: \(sessionIDs.joined(separator: ", "))\n"
        return """
        Dispatch [\(status)] \(operation)\(countInfo)
        \(sessionInfo)

        \(content)
        """
    }
}

// MARK: - Errors

/// Errors that can occur during dispatch operations.
public enum DispatchError: LocalizedError {
    case sessionFailed(String)
    case invalidOperation(String)
    case emptyBatch
    case allTasksFailed(count: Int)

    public var errorDescription: String? {
        switch self {
        case .sessionFailed(let reason):
            return "Dispatch session failed: \(reason)"
        case .invalidOperation(let op):
            return "Invalid operation: '\(op)'. Valid operations: query, query_batched"
        case .emptyBatch:
            return "No tasks provided for query_batched. Separate tasks with \\n---\\n"
        case .allTasksFailed(let count):
            return "All \(count) tasks failed in query_batched"
        }
    }
}
