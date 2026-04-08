//
//  PluginHookRunner.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Executes aggregated plugin hooks and parses the structured JSON contract used by `claw-code`.
public struct PluginHookRunner: Sendable {
    public let hooks: PluginHooks

    public init(hooks: PluginHooks) {
        self.hooks = hooks
    }

    public init(registry: PluginRegistry) throws {
        self.hooks = try registry.aggregatedHooks()
    }

    public func runPreToolUse(
        toolName: String,
        toolInput: String
    ) async throws -> PluginHookRunResult {
        try await runCommands(
            event: .preToolUse,
            commands: hooks.preToolUse,
            toolName: toolName,
            toolInput: toolInput,
            toolOutput: nil,
            isError: false
        )
    }

    public func runPostToolUse(
        toolName: String,
        toolInput: String,
        toolOutput: String,
        isError: Bool
    ) async throws -> PluginHookRunResult {
        try await runCommands(
            event: .postToolUse,
            commands: hooks.postToolUse,
            toolName: toolName,
            toolInput: toolInput,
            toolOutput: toolOutput,
            isError: isError
        )
    }

    public func runPostToolUseFailure(
        toolName: String,
        toolInput: String,
        toolError: String
    ) async throws -> PluginHookRunResult {
        try await runCommands(
            event: .postToolUseFailure,
            commands: hooks.postToolUseFailure,
            toolName: toolName,
            toolInput: toolInput,
            toolOutput: toolError,
            isError: true
        )
    }

    private func runCommands(
        event: PluginHookEvent,
        commands: [String],
        toolName: String,
        toolInput: String,
        toolOutput: String?,
        isError: Bool
    ) async throws -> PluginHookRunResult {
        guard !commands.isEmpty else {
            return .allow()
        }

        var accumulated = PluginHookRunResult.allow()
        let payload = try hookPayload(
            event: event,
            toolName: toolName,
            toolInput: toolInput,
            toolOutput: toolOutput,
            isError: isError
        )

        for command in commands {
            try Task.checkCancellation()

            let outcome = try runCommand(
                command,
                event: event,
                toolName: toolName,
                toolInput: toolInput,
                toolOutput: toolOutput,
                isError: isError,
                payload: payload
            )
            accumulated = merge(current: accumulated, with: outcome.parsed)

            switch outcome.kind {
            case .allow:
                continue
            case .deny:
                return PluginHookRunResult(
                    denied: true,
                    messages: accumulated.messages,
                    authorizationDecision: accumulated.authorizationDecision,
                    authorizationReason: accumulated.authorizationReason,
                    updatedInput: accumulated.updatedInput
                )
            case .failed:
                return PluginHookRunResult(
                    denied: accumulated.denied,
                    failed: true,
                    messages: accumulated.messages,
                    authorizationDecision: accumulated.authorizationDecision,
                    authorizationReason: accumulated.authorizationReason,
                    updatedInput: accumulated.updatedInput
                )
            }
        }

        return accumulated
    }

    private func runCommand(
        _ command: String,
        event: PluginHookEvent,
        toolName: String,
        toolInput: String,
        toolOutput: String?,
        isError: Bool,
        payload: String
    ) throws -> HookCommandOutcome {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["HOOK_EVENT"] = event.rawValue
        environment["HOOK_TOOL_NAME"] = toolName
        environment["HOOK_TOOL_INPUT"] = toolInput
        environment["HOOK_TOOL_IS_ERROR"] = isError ? "1" : "0"
        if let toolOutput {
            environment["HOOK_TOOL_OUTPUT"] = toolOutput
        }
        process.environment = environment

        if FileManager.default.fileExists(atPath: command) {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [command]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-lc", command]
        }

        do {
            try process.run()
        } catch {
            return HookCommandOutcome(
                kind: .failed,
                parsed: ParsedPluginHookOutput(
                    messages: [
                        "\(event.rawValue) hook `\(command)` failed to start for `\(toolName)`: \(error.localizedDescription)"
                    ]
                )
            )
        }

        if let data = payload.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = parseHookOutput(stdout)

        switch process.terminationStatus {
        case 0:
            if parsed.denied {
                return HookCommandOutcome(kind: .deny, parsed: parsed)
            }
            return HookCommandOutcome(kind: .allow, parsed: parsed)
        case 2:
            return HookCommandOutcome(
                kind: .deny,
                parsed: parsed.withFallbackMessage("\(event.rawValue) hook denied tool `\(toolName)`")
            )
        default:
            let message = formatHookFailure(
                command: command,
                status: process.terminationStatus,
                stdout: parsed.messages.first,
                stderr: stderr
            )
            return HookCommandOutcome(
                kind: .failed,
                parsed: parsed.withFallbackMessage(message)
            )
        }
    }

    private func merge(
        current: PluginHookRunResult,
        with parsed: ParsedPluginHookOutput
    ) -> PluginHookRunResult {
        PluginHookRunResult(
            denied: current.denied || parsed.denied,
            failed: current.failed,
            messages: current.messages + parsed.messages,
            authorizationDecision: parsed.authorizationDecision ?? current.authorizationDecision,
            authorizationReason: parsed.authorizationReason ?? current.authorizationReason,
            updatedInput: parsed.updatedInput ?? current.updatedInput
        )
    }

    private func parseHookOutput(_ stdout: String) -> ParsedPluginHookOutput {
        guard !stdout.isEmpty else {
            return ParsedPluginHookOutput()
        }
        guard let data = stdout.data(using: .utf8) else {
            return ParsedPluginHookOutput(messages: [stdout])
        }
        let rawValue: Any
        do {
            rawValue = try JSONSerialization.jsonObject(with: data)
        } catch {
            return ParsedPluginHookOutput(messages: [stdout])
        }
        guard let root = rawValue as? [String: Any] else {
            return ParsedPluginHookOutput(messages: [stdout])
        }

        var parsed = ParsedPluginHookOutput()

        if let message = root["systemMessage"] as? String {
            parsed.messages.append(message)
        }
        if let reason = root["reason"] as? String {
            parsed.messages.append(reason)
        }
        if let shouldContinue = root["continue"] as? Bool, shouldContinue == false {
            parsed.denied = true
        }
        if let decision = root["decision"] as? String, decision == "block" {
            parsed.denied = true
        }

        if let hookSpecificOutput = root["hookSpecificOutput"] as? [String: Any] {
            if let additionalContext = hookSpecificOutput["additionalContext"] as? String {
                parsed.messages.append(additionalContext)
            }
            if let override = hookSpecificOutput["permissionDecision"] as? String {
                parsed.authorizationDecision = ToolAuthorizationDecision(rawValue: override)
            }
            if let overrideReason = hookSpecificOutput["permissionDecisionReason"] as? String {
                parsed.authorizationReason = overrideReason
            }
            if let updatedInput = hookSpecificOutput["updatedInput"],
               JSONSerialization.isValidJSONObject(updatedInput),
               let updatedData = try? JSONSerialization.data(withJSONObject: updatedInput, options: [.sortedKeys]),
               let updatedJSON = String(data: updatedData, encoding: .utf8) {
                parsed.updatedInput = updatedJSON
            }
        }

        if parsed.messages.isEmpty {
            parsed.messages.append(stdout)
        }

        return parsed
    }

    private func hookPayload(
        event: PluginHookEvent,
        toolName: String,
        toolInput: String,
        toolOutput: String?,
        isError: Bool
    ) throws -> String {
        let payload: [String: Any]
        switch event {
        case .postToolUseFailure:
            payload = [
                "hook_event_name": event.rawValue,
                "tool_name": toolName,
                "tool_input": parseToolInput(toolInput),
                "tool_input_json": toolInput,
                "tool_error": toolOutput as Any,
                "tool_result_is_error": true,
            ]
        case .preToolUse, .postToolUse:
            payload = [
                "hook_event_name": event.rawValue,
                "tool_name": toolName,
                "tool_input": parseToolInput(toolInput),
                "tool_input_json": toolInput,
                "tool_output": toolOutput as Any,
                "tool_result_is_error": isError,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw PluginError.json("Failed to encode plugin hook payload for `\(toolName)`.")
        }
        return string
    }

    private func parseToolInput(_ toolInput: String) -> Any {
        guard let data = toolInput.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return ["raw": toolInput]
        }
        return value
    }

    private func formatHookFailure(
        command: String,
        status: Int32,
        stdout: String?,
        stderr: String
    ) -> String {
        var message = "Hook `\(command)` exited with status \(status)"
        if let stdout, !stdout.isEmpty {
            message += ": \(stdout)"
        } else if !stderr.isEmpty {
            message += ": \(stderr)"
        }
        return message
    }
}

private struct ParsedPluginHookOutput {
    var messages: [String] = []
    var denied = false
    var authorizationDecision: ToolAuthorizationDecision?
    var authorizationReason: String?
    var updatedInput: String?

    func withFallbackMessage(_ fallback: String) -> ParsedPluginHookOutput {
        var copy = self
        if copy.messages.isEmpty {
            copy.messages.append(fallback)
        }
        return copy
    }
}

private struct HookCommandOutcome {
    enum Kind {
        case allow
        case deny
        case failed
    }

    let kind: Kind
    let parsed: ParsedPluginHookOutput
}
