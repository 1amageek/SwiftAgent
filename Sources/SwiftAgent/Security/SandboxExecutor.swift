//
//  SandboxExecutor.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// macOS sandbox-exec wrapper for secure command execution.
///
/// Uses the macOS sandbox-exec utility to run commands in a restricted
/// environment with limited network and filesystem access.
///
/// ## Example
///
/// ```swift
/// let config = SandboxExecutor.Configuration.standard
///
/// let result = try await SandboxExecutor.execute(
///     executable: "/usr/bin/ls",
///     arguments: ["-la"],
///     workingDirectory: "/tmp",
///     configuration: config
/// )
/// ```
public struct SandboxExecutor: Sendable {

    /// Configuration for the sandbox environment.
    ///
    /// This type is `Codable` to support serialization in middleware metadata.
    public struct Configuration: Sendable, Codable {

        /// Network access policy.
        public var networkPolicy: NetworkPolicy

        /// File access policy.
        public var filePolicy: FilePolicy

        /// Whether to allow spawning subprocesses.
        public var allowSubprocesses: Bool

        /// Network access policies.
        public enum NetworkPolicy: String, Sendable, Codable {
            /// No network access.
            case none
            /// Allow local network only (localhost, LAN).
            case local
            /// Full network access.
            case full
        }

        /// File access policies.
        ///
        /// - Note: Read access is unrestricted for `readOnly` and `workingDirectoryOnly`
        ///   to support build tools that need system headers and libraries.
        ///   Only write access is restricted.
        public enum FilePolicy: Sendable, Codable {
            /// No write access. Reads are unrestricted.
            case readOnly

            /// Write access restricted to working directory and temp.
            /// Reads are unrestricted.
            case workingDirectoryOnly

            /// Custom path restrictions for both read and write.
            case custom(read: [String], write: [String])
        }

        /// Creates a sandbox configuration.
        public init(
            networkPolicy: NetworkPolicy = .local,
            filePolicy: FilePolicy = .workingDirectoryOnly,
            allowSubprocesses: Bool = true
        ) {
            self.networkPolicy = networkPolicy
            self.filePolicy = filePolicy
            self.allowSubprocesses = allowSubprocesses
        }

        // MARK: - Presets

        /// No sandbox (disabled).
        ///
        /// Use this when you don't want any sandboxing. The middleware
        /// will skip sandbox execution and run commands directly.
        ///
        /// ## Usage
        ///
        /// ```swift
        /// // Used internally by ToolPipeline.default
        /// SandboxMiddleware(configuration: .none)
        /// ```
        public static var none: Configuration {
            Configuration(
                networkPolicy: .full,
                filePolicy: .workingDirectoryOnly,
                allowSubprocesses: true
            )
        }

        /// Whether this configuration effectively disables sandboxing.
        public var isDisabled: Bool {
            // Consider disabled if it's the same as .none
            guard networkPolicy == .full, allowSubprocesses == true else {
                return false
            }
            // Check if filePolicy is workingDirectoryOnly
            if case .workingDirectoryOnly = filePolicy {
                return true
            }
            return false
        }

        /// Standard sandbox: local network, working directory write.
        public static var standard: Configuration {
            Configuration(
                networkPolicy: .local,
                filePolicy: .workingDirectoryOnly,
                allowSubprocesses: true
            )
        }

        /// Restrictive sandbox: no network, read-only.
        public static var restrictive: Configuration {
            Configuration(
                networkPolicy: .none,
                filePolicy: .readOnly,
                allowSubprocesses: false
            )
        }

        /// Permissive sandbox: full network, working directory write.
        public static var permissive: Configuration {
            Configuration(
                networkPolicy: .full,
                filePolicy: .workingDirectoryOnly,
                allowSubprocesses: true
            )
        }
    }

    /// Error thrown when sandbox execution fails.
    public struct SandboxError: Error, LocalizedError {
        public let reason: String
        public let underlyingError: Error?

        public init(reason: String, underlyingError: Error? = nil) {
            self.reason = reason
            self.underlyingError = underlyingError
        }

        public var errorDescription: String? {
            if let underlying = underlyingError {
                return "Sandbox error: \(reason) (\(underlying.localizedDescription))"
            }
            return "Sandbox error: \(reason)"
        }
    }

    /// Result of a sandboxed command execution.
    public struct ExecutionResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32
    }

    // MARK: - Execution

    #if os(macOS)

    /// Maximum allowed timeout (24 hours).
    public static let maxTimeout: TimeInterval = 86400

    /// Executes a command in a sandbox (macOS only).
    ///
    /// - Parameters:
    ///   - executable: Path to the executable.
    ///   - arguments: Command arguments.
    ///   - workingDirectory: Working directory for the process.
    ///   - configuration: Sandbox configuration.
    ///   - timeout: Maximum execution time (default: 120 seconds, max: 24 hours).
    /// - Returns: The execution result.
    /// - Throws: `SandboxError` if execution fails or timeout is invalid.
    public static func execute(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        configuration: Configuration,
        timeout: TimeInterval = 120
    ) async throws -> ExecutionResult {
        // Validate timeout to prevent UInt64 overflow
        guard timeout > 0 else {
            throw SandboxError(reason: "Timeout must be positive (got \(timeout))")
        }
        guard timeout <= maxTimeout else {
            throw SandboxError(reason: "Timeout exceeds maximum (\(Int(maxTimeout)) seconds)")
        }

        // Generate sandbox profile
        let profile = generateProfile(configuration, workingDirectory: workingDirectory)

        // Write profile to temporary file
        let profilePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString).sb")

        do {
            try profile.write(to: profilePath, atomically: true, encoding: .utf8)
        } catch {
            throw SandboxError(reason: "Failed to write sandbox profile", underlyingError: error)
        }

        defer {
            try? FileManager.default.removeItem(at: profilePath)
        }

        // Build sandbox-exec command
        let sandboxExecPath = "/usr/bin/sandbox-exec"

        // Check if sandbox-exec exists
        guard FileManager.default.fileExists(atPath: sandboxExecPath) else {
            throw SandboxError(reason: "sandbox-exec not found at \(sandboxExecPath)")
        }

        // Execute the command with timeout
        return try await runProcess(
            sandboxExec: sandboxExecPath,
            profilePath: profilePath.path,
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        )
    }

    private static func runProcess(
        sandboxExec: String,
        profilePath: String,
        executable: String,
        arguments: [String],
        workingDirectory: String,
        timeout: TimeInterval
    ) async throws -> ExecutionResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: sandboxExec)
        process.arguments = ["-f", profilePath, executable] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set minimal environment
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8"
        ]

        // Pre-flight cancellation check
        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        do {
            try process.run()
        } catch {
            throw SandboxError(reason: "Failed to start sandboxed process", underlyingError: error)
        }

        // Use TaskGroup to handle timeout with proper process termination
        return try await withThrowingTaskGroup(of: ExecutionResult.self) { group in
            // Process execution task
            group.addTask {
                // This runs on a background thread via the async bridge
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                return ExecutionResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                )
            }

            // Turn cancellation monitor task
            group.addTask {
                while !Task.isCancelled {
                    if let token = TurnCancellationContext.current, token.isCancelled {
                        if process.isRunning {
                            process.terminate()
                            try await Task.sleep(nanoseconds: 500_000_000)
                            if process.isRunning {
                                kill(process.processIdentifier, SIGKILL)
                            }
                        }
                        throw SandboxError(reason: "Execution cancelled")
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                throw CancellationError()
            }

            // Timeout task - terminates the process if it runs too long
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                // Timeout reached - terminate the process
                if process.isRunning {
                    process.terminate()

                    // Wait briefly for graceful termination
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

                    // Force kill if still running
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }

                throw SandboxError(reason: "Execution timed out after \(timeout) seconds")
            }

            // Wait for first result (either completion or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Profile Generation

    /// Escapes a path string for safe inclusion in SBPL rules.
    ///
    /// Prevents injection attacks where malicious characters in paths
    /// could alter the sandbox profile structure.
    private static func escapeSBPLPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Generates a SBPL (Sandbox Profile Language) profile.
    private static func generateProfile(
        _ config: Configuration,
        workingDirectory: String
    ) -> String {
        var rules: [String] = []

        // Version and default deny
        rules.append("(version 1)")
        rules.append("(deny default)")

        // Process execution (required for the command itself)
        rules.append("(allow process-exec)")

        // Subprocess control
        if config.allowSubprocesses {
            rules.append("(allow process-fork)")
            rules.append("(allow process-exec*)")
        } else {
            rules.append("(deny process-fork)")
        }

        // File access rules
        rules.append(contentsOf: fileAccessRules(for: config.filePolicy, workingDirectory: workingDirectory))

        // Network rules
        rules.append(contentsOf: networkRules(for: config.networkPolicy))

        // System access (required for basic operation)
        rules.append("(allow sysctl-read)")
        rules.append("(allow mach-lookup)")
        rules.append("(allow signal)")
        rules.append("(allow process-info-codesignature)")
        rules.append("(allow process-info-pidinfo)")

        return rules.joined(separator: "\n")
    }

    private static func fileAccessRules(
        for policy: Configuration.FilePolicy,
        workingDirectory: String
    ) -> [String] {
        var rules: [String] = []

        switch policy {
        case .readOnly:
            // Allow all reads, deny all writes
            rules.append("(allow file-read*)")
            rules.append("(deny file-write*)")

        case .workingDirectoryOnly:
            // Allow all reads, write only to working directory and temp
            rules.append("(allow file-read*)")
            rules.append("(allow file-write* (subpath \"\(escapeSBPLPath(workingDirectory))\"))")
            rules.append("(allow file-write* (subpath \"/tmp\"))")
            rules.append("(allow file-write* (subpath \"/private/tmp\"))")
            rules.append("(allow file-write* (subpath \"/private/var/folders\"))")

        case .custom(let read, let write):
            // System paths required for command execution
            rules.append("(allow file-read* (subpath \"/usr\"))")
            rules.append("(allow file-read* (subpath \"/bin\"))")
            rules.append("(allow file-read* (subpath \"/sbin\"))")
            rules.append("(allow file-read* (subpath \"/Library\"))")
            rules.append("(allow file-read* (subpath \"/System\"))")
            rules.append("(allow file-read* (subpath \"/private/var/db\"))")
            rules.append("(allow file-read* (subpath \"/Applications/Xcode.app\"))")
            rules.append("(allow file-read* (subpath \"/opt/homebrew\"))")
            rules.append("(allow file-read* (subpath \"/usr/local\"))")

            // Custom read paths
            for path in read {
                rules.append("(allow file-read* (subpath \"\(escapeSBPLPath(path))\"))")
            }
            // Custom write paths
            for path in write {
                rules.append("(allow file-write* (subpath \"\(escapeSBPLPath(path))\"))")
            }
            // Always allow temp for command execution
            rules.append("(allow file-write* (subpath \"/tmp\"))")
            rules.append("(allow file-write* (subpath \"/private/tmp\"))")
        }

        return rules
    }

    private static func networkRules(for policy: Configuration.NetworkPolicy) -> [String] {
        switch policy {
        case .none:
            return ["(deny network*)"]

        case .local:
            return [
                "(allow network* (local ip))",
                "(allow network* (remote ip \"localhost\"))",
                "(allow network* (remote ip \"127.0.0.1\"))",
                "(allow network* (remote ip \"::1\"))",
                "(deny network* (remote ip))"
            ]

        case .full:
            return ["(allow network*)"]
        }
    }

    #else

    /// Sandbox execution is only available on macOS.
    public static func execute(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        configuration: Configuration,
        timeout: TimeInterval = 120
    ) async throws -> ExecutionResult {
        throw SandboxError(reason: "Sandbox execution is only available on macOS")
    }

    #endif

    // MARK: - Availability Check

    /// Returns whether sandboxing is available on this platform.
    public static var isAvailable: Bool {
        #if os(macOS)
        return FileManager.default.fileExists(atPath: "/usr/bin/sandbox-exec")
        #else
        return false
        #endif
    }
}
