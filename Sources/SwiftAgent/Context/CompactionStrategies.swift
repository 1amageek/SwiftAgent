//
//  CompactionStrategies.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

// MARK: - TruncationCompactionStrategy

/// Removes oldest entries to reduce context size.
///
/// This strategy preserves:
/// - Instructions (always kept at the beginning)
/// - Recent entries (configurable count)
/// - Entries marked as preserved
///
/// ## Example
///
/// ```swift
/// let strategy = TruncationCompactionStrategy(
///     preserveRecentCount: 10,
///     preserveToolOutputs: true
/// )
/// ```
public struct TruncationCompactionStrategy: CompactionStrategy {

    public let name = "truncation"
    public let description = "Removes oldest entries, keeping recent context"

    /// Number of recent entries to always preserve.
    public let preserveRecentCount: Int

    /// Whether to preserve all tool outputs.
    public let preserveToolOutputs: Bool

    // MARK: - Initialization

    public init(
        preserveRecentCount: Int = 10,
        preserveToolOutputs: Bool = true
    ) {
        self.preserveRecentCount = preserveRecentCount
        self.preserveToolOutputs = preserveToolOutputs
    }

    // MARK: - CompactionStrategy

    public func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript {
        let entries = Array(transcript)
        guard entries.count > preserveRecentCount else {
            return .unchanged(transcript)
        }

        var preserved: [Transcript.Entry] = []
        var removed = 0

        // Always keep instructions (first entry if it's instructions)
        var startIndex = 0
        if case .instructions = entries.first {
            preserved.append(entries[0])
            startIndex = 1
        }

        // Determine which entries to keep
        let recentStartIndex = max(startIndex, entries.count - preserveRecentCount)

        for (index, entry) in entries.enumerated() {
            if index < startIndex {
                continue // Already handled instructions
            }

            // Keep if it's in the recent entries
            if index >= recentStartIndex {
                preserved.append(entry)
                continue
            }

            // Keep if marked as preserved
            if context.preservedIndices.contains(index) {
                preserved.append(entry)
                continue
            }

            // Keep tool outputs if configured
            if preserveToolOutputs, case .toolOutput = entry {
                preserved.append(entry)
                continue
            }

            // Remove this entry
            removed += 1
        }

        return CompactedTranscript(
            entries: preserved,
            removedCount: removed,
            summarizedCount: 0,
            summary: "Truncated \(removed) old entries, kept \(preserved.count)"
        )
    }

    public func estimateSavings(for transcript: Transcript) async -> Int {
        let entries = Array(transcript)
        let removable = max(0, entries.count - preserveRecentCount - 1)
        return removable
    }
}

// MARK: - PriorityCompactionStrategy

/// Removes entries based on priority scores.
///
/// Priority is determined by:
/// - Entry type (instructions > prompts > responses > tool outputs)
/// - Recency (more recent = higher priority)
/// - Custom priority tags (via preserved indices)
///
/// ## Example
///
/// ```swift
/// let strategy = PriorityCompactionStrategy(
///     typePriorities: [
///         "instructions": 100,
///         "prompt": 50,
///         "response": 40,
///         "toolCalls": 30,
///         "toolOutput": 20
///     ],
///     recencyWeight: 0.5
/// )
/// ```
public struct PriorityCompactionStrategy: CompactionStrategy {

    public let name = "priority"
    public let description = "Removes low-priority entries first"

    /// Priority scores by entry type (higher = more important).
    public let typePriorities: [String: Int]

    /// Weight for recency in priority calculation (0.0 to 1.0).
    public let recencyWeight: Double

    // MARK: - Initialization

    public init(
        typePriorities: [String: Int]? = nil,
        recencyWeight: Double = 0.5
    ) {
        self.typePriorities = typePriorities ?? [
            "instructions": 100,
            "prompt": 50,
            "response": 40,
            "toolCalls": 30,
            "toolOutput": 20
        ]
        self.recencyWeight = min(1.0, max(0.0, recencyWeight))
    }

    // MARK: - CompactionStrategy

    public func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript {
        let entries = Array(transcript)
        guard entries.count > 2 else {
            return .unchanged(transcript)
        }

        // Calculate priority for each entry
        var scoredEntries: [(index: Int, entry: Transcript.Entry, priority: Double)] = []

        for (index, entry) in entries.enumerated() {
            let priority = calculatePriority(
                entry: entry,
                index: index,
                totalCount: entries.count,
                isPreserved: context.preservedIndices.contains(index)
            )
            scoredEntries.append((index, entry, priority))
        }

        // Sort by priority (highest first)
        scoredEntries.sort { $0.priority > $1.priority }

        // Keep high-priority entries until we're at target
        let estimatedTokensPerEntry = context.currentUsage.estimatedTokens / max(1, entries.count)
        let maxEntriesToKeep = targetTokens / max(1, estimatedTokensPerEntry)

        let keptEntries = Array(scoredEntries.prefix(maxEntriesToKeep))
            .sorted { $0.index < $1.index }
            .map { $0.entry }

        let removed = entries.count - keptEntries.count

        return CompactedTranscript(
            entries: keptEntries,
            removedCount: removed,
            summarizedCount: 0,
            summary: "Removed \(removed) low-priority entries"
        )
    }

    private func calculatePriority(
        entry: Transcript.Entry,
        index: Int,
        totalCount: Int,
        isPreserved: Bool
    ) -> Double {
        // Start with type priority
        let typeName: String
        switch entry {
        case .instructions:
            typeName = "instructions"
        case .prompt:
            typeName = "prompt"
        case .response:
            typeName = "response"
        case .toolCalls:
            typeName = "toolCalls"
        case .toolOutput:
            typeName = "toolOutput"
        @unknown default:
            typeName = "unknown"
        }

        var priority = Double(typePriorities[typeName] ?? 10)

        // Add recency bonus
        let recencyScore = Double(index) / Double(max(1, totalCount - 1)) * 50.0
        priority += recencyScore * recencyWeight

        // Boost preserved entries
        if isPreserved {
            priority += 100
        }

        return priority
    }
}

// MARK: - SlidingWindowCompactionStrategy

/// Keeps a sliding window of recent entries.
///
/// Simple and predictable strategy that maintains a fixed window
/// of the most recent conversation turns.
///
/// ## Example
///
/// ```swift
/// let strategy = SlidingWindowCompactionStrategy(windowSize: 20)
/// ```
public struct SlidingWindowCompactionStrategy: CompactionStrategy {

    public let name = "sliding-window"
    public let description = "Keeps a sliding window of recent entries"

    /// Maximum number of entries to keep (excluding instructions).
    public let windowSize: Int

    // MARK: - Initialization

    public init(windowSize: Int = 20) {
        self.windowSize = max(2, windowSize)
    }

    // MARK: - CompactionStrategy

    public func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript {
        let entries = Array(transcript)

        // Separate instructions from content
        var instructions: Transcript.Entry?
        var content: [Transcript.Entry] = []

        for entry in entries {
            if case .instructions = entry {
                instructions = entry
            } else {
                content.append(entry)
            }
        }

        // Keep only the window
        let windowedContent = Array(content.suffix(windowSize))
        var result: [Transcript.Entry] = []

        if let instructions = instructions {
            result.append(instructions)
        }
        result.append(contentsOf: windowedContent)

        let removed = content.count - windowedContent.count

        return CompactedTranscript(
            entries: result,
            removedCount: removed,
            summarizedCount: 0,
            summary: "Kept \(windowedContent.count) recent entries in window"
        )
    }

    public func estimateSavings(for transcript: Transcript) async -> Int {
        let entries = Array(transcript)
        let contentCount = entries.filter { entry in
            if case .instructions = entry { return false }
            return true
        }.count
        return max(0, contentCount - windowSize)
    }
}

// MARK: - HybridCompactionStrategy

/// Combines multiple strategies for optimal compaction.
///
/// Applies strategies in order until target is reached:
/// 1. First strategy attempts compaction
/// 2. If still above target, second strategy is applied
/// 3. Continues until target is reached or all strategies are exhausted
///
/// ## Example
///
/// ```swift
/// let strategy = HybridCompactionStrategy(strategies: [
///     PriorityCompactionStrategy(),
///     SlidingWindowCompactionStrategy(),
///     TruncationCompactionStrategy()
/// ])
/// ```
public struct HybridCompactionStrategy: CompactionStrategy {

    public let name = "hybrid"
    public let description = "Combines priority, window, and truncation strategies"

    public let strategies: [any CompactionStrategy]

    // MARK: - Initialization

    public init(strategies: [any CompactionStrategy]? = nil) {
        self.strategies = strategies ?? [
            PriorityCompactionStrategy(),
            SlidingWindowCompactionStrategy(),
            TruncationCompactionStrategy()
        ]
    }

    // MARK: - CompactionStrategy

    public func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript {
        var currentEntries = Array(transcript)
        var totalRemoved = 0
        var totalSummarized = 0
        var summaries: [String] = []

        // Create a mock transcript for iteration
        for strategy in strategies {
            // Create temporary transcript from current entries
            let tempTranscript = createTranscript(from: currentEntries)

            // Estimate current tokens
            let estimatedTokensPerEntry = context.currentUsage.estimatedTokens / max(1, context.currentUsage.entryCount)
            let currentTokens = currentEntries.count * estimatedTokensPerEntry

            // Check if we're already at target
            if currentTokens <= targetTokens {
                break
            }

            // Apply strategy
            let updatedContext = CompactionContext(
                sessionID: context.sessionID,
                currentUsage: ContextUsage(
                    estimatedTokens: currentTokens,
                    contextWindowSize: context.currentUsage.contextWindowSize,
                    entryCount: currentEntries.count,
                    toolCallCount: context.currentUsage.toolCallCount,
                    responseCount: context.currentUsage.responseCount
                ),
                triggerThreshold: context.triggerThreshold,
                preservedIndices: context.preservedIndices
            )

            let result = try await strategy.compact(
                transcript: tempTranscript,
                targetTokens: targetTokens,
                context: updatedContext
            )

            currentEntries = result.entries
            totalRemoved += result.removedCount
            totalSummarized += result.summarizedCount
            if !result.summary.isEmpty {
                summaries.append("[\(strategy.name)] \(result.summary)")
            }
        }

        return CompactedTranscript(
            entries: currentEntries,
            removedCount: totalRemoved,
            summarizedCount: totalSummarized,
            summary: summaries.joined(separator: "; ")
        )
    }

    public func estimateSavings(for transcript: Transcript) async -> Int {
        var totalSavings = 0
        for strategy in strategies {
            totalSavings += await strategy.estimateSavings(for: transcript)
        }
        return totalSavings / max(1, strategies.count)
    }

    /// Creates a Transcript from entries (helper for iteration).
    private func createTranscript(from entries: [Transcript.Entry]) -> Transcript {
        Transcript(entries: entries)
    }
}

// MARK: - NoOpCompactionStrategy

/// A strategy that performs no compaction.
///
/// Useful for testing or when compaction should be disabled.
public struct NoOpCompactionStrategy: CompactionStrategy {

    public let name = "noop"
    public let description = "Performs no compaction"

    public init() {}

    public func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript {
        .unchanged(transcript)
    }

    public func estimateSavings(for transcript: Transcript) async -> Int {
        0
    }
}
