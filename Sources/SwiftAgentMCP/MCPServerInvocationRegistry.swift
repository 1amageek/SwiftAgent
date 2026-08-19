import Foundation
import MCP

/// Owns tool invocations that outlive the upstream server's receive loop.
actor MCPServerInvocationRegistry {
    private let maximumConcurrentInvocations: Int
    private var invocations: [UUID: Task<CallTool.Result, Error>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var isShuttingDown = false

    init(maximumConcurrentInvocations: Int = 128) {
        self.maximumConcurrentInvocations = maximumConcurrentInvocations
    }

    func call(
        tool: any MCPServerTool,
        arguments: [String: MCP.Value]?
    ) async throws -> CallTool.Result {
        guard !isShuttingDown else {
            throw CancellationError()
        }
        guard invocations.count < maximumConcurrentInvocations else {
            throw MCPServerError.invocationCapacityExceeded(
                maximumConcurrentInvocations
            )
        }

        let invocationID = UUID()
        let task = Task {
            try await tool.call(arguments: arguments)
        }
        invocations[invocationID] = task

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            invocations.removeValue(forKey: invocationID)
            return result
        } catch is CancellationError {
            let isOwnershipCancellation = isShuttingDown || Task.isCancelled
            invocations.removeValue(forKey: invocationID)
            guard !isOwnershipCancellation else {
                throw CancellationError()
            }
            throw MCPServerError.unexpectedToolCancellation(tool.name)
        } catch {
            invocations.removeValue(forKey: invocationID)
            throw error
        }
    }

    func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }

        isShuttingDown = true
        let activeInvocations = Array(invocations.values)
        for invocation in activeInvocations {
            invocation.cancel()
        }

        let task = Task {
            for invocation in activeInvocations {
                _ = await invocation.result
            }
        }
        shutdownTask = task
        await task.value
        invocations.removeAll(keepingCapacity: false)
    }
}
