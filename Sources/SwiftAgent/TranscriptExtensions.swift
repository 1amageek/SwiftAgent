//
//  TranscriptExtensions.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

// MARK: - Transcript Tool Call Extraction

extension Transcript {

    /// Extracts tool call records from transcript entries.
    ///
    /// This function pairs tool calls with their corresponding outputs
    /// and creates `ToolCallRecord` instances for tracking.
    ///
    /// - Parameter entries: The transcript entries to extract from.
    /// - Returns: Array of tool call records.
    public static func extractToolCalls(from entries: [Transcript.Entry]) -> [ToolCallRecord] {
        var records: [ToolCallRecord] = []
        var toolOutputs: [String: (output: String, toolCallID: String)] = [:]

        // First pass: collect all tool outputs
        for entry in entries {
            if case .toolOutput(let output) = entry {
                let outputText = output.segments.compactMap { segment -> String? in
                    if case .text(let textSegment) = segment {
                        return textSegment.content
                    }
                    return nil
                }.joined()
                toolOutputs[output.id] = (output: outputText, toolCallID: output.id)
            }
        }

        // Second pass: create records from tool calls
        for entry in entries {
            if case .toolCalls(let toolCalls) = entry {
                for toolCall in toolCalls {
                    // Find output by matching tool call ID with tool output ID pattern
                    // Tool outputs typically have IDs that relate to tool call IDs
                    let output = findToolOutput(
                        for: toolCall.id,
                        toolName: toolCall.toolName,
                        in: entries
                    )

                    let record = ToolCallRecord(
                        id: toolCall.id,
                        toolName: toolCall.toolName,
                        arguments: toolCall.arguments,
                        output: output ?? "",
                        success: output != nil,
                        error: output == nil ? "No output found" : nil,
                        duration: .zero // Duration not available at transcript level
                    )
                    records.append(record)
                }
            }
        }

        return records
    }

    /// Finds the tool output for a specific tool call.
    private static func findToolOutput(
        for toolCallID: String,
        toolName: String,
        in entries: [Transcript.Entry]
    ) -> String? {
        // Look for tool output entries that follow the tool call
        var foundToolCall = false

        for entry in entries {
            if case .toolCalls(let toolCalls) = entry {
                if toolCalls.contains(where: { $0.id == toolCallID }) {
                    foundToolCall = true
                }
            }

            if foundToolCall, case .toolOutput(let output) = entry {
                // Match by tool name since IDs may differ
                if output.toolName == toolName {
                    return output.segments.compactMap { segment -> String? in
                        if case .text(let textSegment) = segment {
                            return textSegment.content
                        }
                        return nil
                    }.joined()
                }
            }
        }

        return nil
    }
}

// MARK: - Transcript Analysis

extension Transcript {

    /// Returns all tool calls in the transcript.
    public var allToolCalls: [Transcript.ToolCall] {
        self.compactMap { entry in
            if case .toolCalls(let toolCalls) = entry {
                return Array(toolCalls)
            }
            return nil
        }.flatMap { $0 }
    }

    /// Returns all tool outputs in the transcript.
    public var allToolOutputs: [Transcript.ToolOutput] {
        self.compactMap { entry in
            if case .toolOutput(let output) = entry {
                return output
            }
            return nil
        }
    }

    /// Returns the number of tool calls in the transcript.
    public var toolCallCount: Int {
        allToolCalls.count
    }

    /// Returns unique tool names that were called.
    public var calledToolNames: Set<String> {
        Set(allToolCalls.map { $0.toolName })
    }
}

// MARK: - ToolCallRecord Batch Creation

extension Array where Element == ToolCallRecord {

    /// Creates tool call records from transcript entries.
    public static func from(transcript entries: [Transcript.Entry]) -> [ToolCallRecord] {
        Transcript.extractToolCalls(from: entries)
    }

    /// Creates tool call records from a transcript.
    public static func from(transcript: Transcript) -> [ToolCallRecord] {
        // Use map to avoid type inference issues with Array initializer
        let entries: [Transcript.Entry] = transcript.map { $0 }
        return Transcript.extractToolCalls(from: entries)
    }
}
