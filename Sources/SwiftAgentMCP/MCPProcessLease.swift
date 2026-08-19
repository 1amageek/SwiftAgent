import Foundation
import MCP

#if os(macOS) || os(Linux)

#if canImport(System)
import System
#else
import SystemPackage
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Owns one spawned MCP server process and every parent-side pipe handle.
actor MCPProcessLease {
    private let serverName: String
    private let process: Process
    private let inputWriter: FileHandle
    private let outputReader: FileHandle
    private let errorReader: FileHandle
    private let errorDrainTask: Task<Void, any Error>
    private var inputClosed = false
    private var outputClosed = false
    private var errorClosed = false
    private var errorDrainCompleted = false
    private var shutdownCompleted = false
    private var shutdownOperationID: UUID?
    private var shutdownTask: Task<Result<Void, MCPClientError>, Never>?

    private init(
        serverName: String,
        process: Process,
        inputWriter: FileHandle,
        outputReader: FileHandle,
        errorReader: FileHandle
    ) {
        self.serverName = serverName
        self.process = process
        self.inputWriter = inputWriter
        self.outputReader = outputReader
        self.errorReader = errorReader
        self.errorDrainTask = Task {
            do {
                for try await _ in errorReader.bytes {}
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                throw error
            }
        }
    }

    static func launch(
        serverName: String,
        command: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) throws -> (transport: any Transport, lease: MCPProcessLease) {
        let process = Process()
        let processEnvironment = ProcessInfo.processInfo.environment.merging(
            environment ?? [:]
        ) { _, configured in configured }
        process.executableURL = try resolveExecutable(
            command,
            environment: processEnvironment,
            workingDirectory: workingDirectory,
            serverName: serverName
        )
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = processEnvironment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw MCPClientError.processLaunchFailed(
                server: serverName,
                reason: error.localizedDescription
            )
        }

        let inputWriter = inputPipe.fileHandleForWriting
        let outputReader = outputPipe.fileHandleForReading
        let errorReader = errorPipe.fileHandleForReading
        let transport = StdioTransport(
            input: FileDescriptor(rawValue: outputReader.fileDescriptor),
            output: FileDescriptor(rawValue: inputWriter.fileDescriptor)
        )
        let lease = MCPProcessLease(
            serverName: serverName,
            process: process,
            inputWriter: inputWriter,
            outputReader: outputReader,
            errorReader: errorReader
        )
        return (transport, lease)
    }

    func shutdown() async throws {
        guard !shutdownCompleted else {
            return
        }

        if let shutdownOperationID, let shutdownTask {
            let result = await shutdownTask.value
            finishShutdownOperation(shutdownOperationID)
            try result.get()
            return
        }

        let operationID = UUID()
        let task = Task { [self] () -> Result<Void, MCPClientError> in
            do {
                try await performShutdown()
                return .success(())
            } catch let error as MCPClientError {
                return .failure(error)
            } catch {
                return .failure(.processCleanupFailed(
                    server: serverName,
                    reasons: [error.localizedDescription]
                ))
            }
        }
        shutdownOperationID = operationID
        shutdownTask = task

        let result = await task.value
        finishShutdownOperation(operationID)
        try result.get()
    }

    private func performShutdown() async throws {
        guard !shutdownCompleted else {
            return
        }

        var failures: [String] = []
        if !inputClosed {
            do {
                try inputWriter.close()
                inputClosed = true
            } catch {
                failures.append("closing stdin failed: \(error.localizedDescription)")
            }
        }

        if process.isRunning {
            process.terminate()
            do {
                if try await !waitForExit(within: .seconds(2)) {
                    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
                    if kill(process.processIdentifier, SIGKILL) != 0 {
                        failures.append("SIGKILL failed with errno \(errno)")
                    } else if try await !waitForExit(within: .seconds(2)) {
                        failures.append("process did not exit after SIGKILL")
                    }
                    #else
                    failures.append("forced process termination is unavailable on this platform")
                    #endif
                }
            } catch {
                failures.append("waiting for process exit failed: \(error.localizedDescription)")
            }
        }

        if !outputClosed {
            do {
                try outputReader.close()
                outputClosed = true
            } catch {
                failures.append("closing stdout failed: \(error.localizedDescription)")
            }
        }
        if !errorDrainCompleted {
            errorDrainTask.cancel()
        }
        if !errorClosed {
            do {
                try errorReader.close()
                errorClosed = true
            } catch {
                failures.append("closing stderr failed: \(error.localizedDescription)")
            }
        }

        if !errorDrainCompleted {
            switch await errorDrainTask.result {
            case .success:
                break
            case .failure(let error) where error is CancellationError:
                break
            case .failure(let error):
                failures.append("stderr drain failed: \(error.localizedDescription)")
            }
            errorDrainCompleted = true
        }

        shutdownCompleted = !process.isRunning
            && inputClosed
            && outputClosed
            && errorClosed
            && errorDrainCompleted
        if !failures.isEmpty {
            throw MCPClientError.processCleanupFailed(server: serverName, reasons: failures)
        }
        guard shutdownCompleted else {
            throw MCPClientError.processCleanupFailed(
                server: serverName,
                reasons: ["process resources remain owned after shutdown"]
            )
        }
    }

    private func finishShutdownOperation(_ operationID: UUID) {
        guard shutdownOperationID == operationID else {
            return
        }
        shutdownOperationID = nil
        shutdownTask = nil
    }

    private func waitForExit(within timeout: Duration) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while process.isRunning, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return !process.isRunning
    }

    private static func resolveExecutable(
        _ command: String,
        environment: [String: String],
        workingDirectory: URL?,
        serverName: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = workingDirectory
            ?? URL(
                fileURLWithPath: fileManager.currentDirectoryPath,
                isDirectory: true
            )

        if command.contains("/") {
            let candidate = URL(
                fileURLWithPath: command,
                relativeTo: baseDirectory
            ).standardizedFileURL
            guard fileManager.isExecutableFile(atPath: candidate.path) else {
                throw MCPClientError.processLaunchFailed(
                    server: serverName,
                    reason: "Executable was not found or is not executable: \(candidate.path)"
                )
            }
            return candidate
        }

        let searchPath = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for component in searchPath.split(
            separator: ":",
            omittingEmptySubsequences: false
        ) {
            let directory = component.isEmpty
                ? baseDirectory
                : URL(
                    fileURLWithPath: String(component),
                    relativeTo: baseDirectory
                ).standardizedFileURL
            let candidate = directory
                .appendingPathComponent(command)
                .standardizedFileURL
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw MCPClientError.processLaunchFailed(
            server: serverName,
            reason: "Executable '\(command)' was not found on PATH"
        )
    }
}

#else

/// An uninhabited ownership marker on platforms without child-process stdio.
enum MCPProcessLease: Sendable {}

#endif
