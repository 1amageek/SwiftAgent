import Foundation

/// A CLI connection that reads requests from stdin and renders events to stdout.
public actor StdioConnection: AgentConnection {
    public nonisolated let supportsConcurrentReceive = false

    private let prompt: String
    private let verbose: Bool
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let lineSource: StdioLineSource
    private var inputFinished = false
    private var outputFinished = false
    private var isReceiving = false
    private var isApproving = false
    private var shutdownOperationID: UUID?
    private var shutdownTask: Task<Void, any Error>?
    private var shutdownCompleted = false

    public init(prompt: String = "> ", verbose: Bool = false) {
        self.prompt = prompt
        self.verbose = verbose
        self.output = .standardOutput
        self.errorOutput = .standardError
        self.lineSource = StdioLineSource(input: .standardInput)
    }

    init(
        input: FileHandle,
        output: FileHandle,
        errorOutput: FileHandle,
        prompt: String,
        verbose: Bool
    ) {
        self.prompt = prompt
        self.verbose = verbose
        self.output = output
        self.errorOutput = errorOutput
        self.lineSource = StdioLineSource(input: input)
    }

    public func receive() async throws -> RunRequest? {
        guard !inputFinished else {
            return nil
        }
        guard !isReceiving else {
            throw AgentConnectionError.invalidState("Concurrent stdin receives are not supported")
        }
        isReceiving = true
        defer { isReceiving = false }

        try write(prompt, to: output)
        guard let line = try await lineSource.next() else {
            inputFinished = true
            return nil
        }

        let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.lowercased() == "exit" || input.lowercased() == "quit" {
            inputFinished = true
            return nil
        }
        return RunRequest(input: .text(input))
    }

    public func send(_ event: RunEvent) async throws {
        guard !outputFinished else {
            throw AgentConnectionError.outputClosed
        }

        switch event {
        case .tokenDelta(let delta):
            try write(delta.delta, to: output)
        case .reasoningDelta(let delta):
            if verbose {
                try write("[thinking] \(delta.delta)", to: errorOutput)
            }
        case .runCompleted:
            try write("\n", to: output)
        case .approvalRequired(let request):
            if verbose {
                try write(
                    "[Approval] \(request.toolName): \(request.operationDescription) (risk: \(request.riskLevel))\n",
                    to: output
                )
            }
        case .error(let error):
            try write("[Error] \(error.message)\n", to: errorOutput)
        case .warning(let warning):
            if verbose {
                try write("[Warning] \(warning.message)\n", to: errorOutput)
            }
        case .toolCall(let call), .toolStarted(let call):
            if verbose {
                try write("[Tool] \(call.toolName)\n", to: output)
            }
        case .toolResult(let result), .toolFinished(let result):
            if verbose {
                let status = result.success ? "OK" : "FAIL"
                try write(
                    "[Tool Result] \(result.toolName): \(status) (\(result.duration))\n",
                    to: output
                )
            }
        case .runStarted, .approvalResolved:
            if verbose {
                try write("[Event] \(event)\n", to: output)
            }
        }
    }

    func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        guard !inputFinished, !outputFinished else {
            throw AgentConnectionError.invalidState(
                "The stdio connection is unavailable for approval"
            )
        }
        guard !isReceiving, !isApproving else {
            throw AgentConnectionError.invalidState(
                "Concurrent stdio input ownership is not supported"
            )
        }
        isApproving = true
        defer { isApproving = false }

        try write("\n=== Permission Request ===\n", to: output)
        try write("Approval ID: \(approvalID)\n", to: output)
        try write("Tool: \(request.toolName)\n", to: output)
        try write("Operation: \(request.operationDescription)\n", to: output)
        try write("Risk Level: \(request.riskLevel.rawValue)\n\n", to: output)
        try write(
            "Options: [y] allow once, [a] always allow, "
                + "[n] deny, [b] deny and block\n",
            to: output
        )
        try write("Choice [y/a/n/b]: ", to: output)

        guard let line = try await lineSource.next() else {
            inputFinished = true
            throw AgentConnectionError.inputClosed
        }
        switch line.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased() {
        case "y", "yes":
            return .allowOnce
        case "a", "always":
            return .alwaysAllow
        case "b", "block":
            return .denyAndBlock
        case "n", "no":
            return .deny
        default:
            return .deny
        }
    }

    public func shutdown() async throws {
        if let shutdownOperationID, let shutdownTask {
            let result = await shutdownTask.result
            finishShutdownOperation(
                shutdownOperationID,
                result: result
            )
            try result.get()
            return
        }
        guard !shutdownCompleted else {
            return
        }
        inputFinished = true
        outputFinished = true
        let lineSource = self.lineSource
        let operationID = UUID()
        let task = Task {
            try await lineSource.shutdown()
        }
        shutdownOperationID = operationID
        shutdownTask = task
        let result = await task.result
        finishShutdownOperation(operationID, result: result)
        try result.get()
    }

    private func finishShutdownOperation(
        _ operationID: UUID,
        result: Result<Void, any Error>
    ) {
        guard shutdownOperationID == operationID else {
            return
        }
        shutdownOperationID = nil
        shutdownTask = nil
        if case .success = result {
            shutdownCompleted = true
        }
    }

    private func write(_ string: String, to handle: FileHandle) throws {
        do {
            try handle.write(contentsOf: Data(string.utf8))
        } catch {
            throw AgentConnectionError.outputWriteFailed(error.localizedDescription)
        }
    }
}
