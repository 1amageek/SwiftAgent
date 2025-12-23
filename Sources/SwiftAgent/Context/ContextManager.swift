//
//  ContextManager.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation
import OpenFoundationModels

/// Manages context window usage and automatic compaction.
///
/// `ContextManager` is an actor that monitors token usage, triggers
/// compaction when thresholds are exceeded, and coordinates with
/// the hook system for intervention points.
///
/// ## Example
///
/// ```swift
/// let manager = ContextManager(
///     contextWindowSize: 128_000,
///     compactionThreshold: 0.80,
///     strategy: SlidingWindowCompactionStrategy()
/// )
///
/// // Check usage
/// let usage = await manager.calculateUsage(for: transcript)
/// print("Using \(usage.usagePercentage)% of context")
///
/// // Compact if needed
/// let result = try await manager.compactIfNeeded(
///     transcript: transcript,
///     hookManager: hookManager
/// )
/// ```
public actor ContextManager {

    // MARK: - Configuration

    /// Maximum context window size in tokens.
    public let contextWindowSize: Int

    /// Threshold (0.0 to 1.0) at which to trigger compaction.
    public let compactionThreshold: Double

    /// Warning threshold for usage notifications.
    public let warningThreshold: Double

    /// The compaction strategy to use.
    public let strategy: any CompactionStrategy

    /// Tokens to reserve for the response.
    public let reservedResponseTokens: Int

    // MARK: - State

    /// Last calculated usage.
    private var lastUsage: ContextUsage?

    /// Number of compactions performed.
    private var compactionCount: Int = 0

    /// Total tokens saved through compaction.
    private var totalTokensSaved: Int = 0

    /// Entry indices that should be preserved during compaction.
    private var preservedIndices: Set<Int> = []

    // MARK: - Token Estimation

    /// Average characters per token (approximation).
    /// Claude models typically use ~4 characters per token for English.
    private let charsPerToken: Double = 4.0

    // MARK: - Initialization

    /// Creates a context manager.
    ///
    /// - Parameters:
    ///   - contextWindowSize: Maximum tokens for the model (default: 128,000 for Claude).
    ///   - compactionThreshold: Ratio to trigger compaction (default: 0.80).
    ///   - warningThreshold: Ratio for warning notifications (default: 0.70).
    ///   - strategy: Compaction strategy (default: Hybrid).
    ///   - reservedResponseTokens: Tokens reserved for response (default: 4,000).
    public init(
        contextWindowSize: Int = 128_000,
        compactionThreshold: Double = 0.80,
        warningThreshold: Double = 0.70,
        strategy: any CompactionStrategy = HybridCompactionStrategy(),
        reservedResponseTokens: Int = 4_000
    ) {
        precondition(compactionThreshold > 0 && compactionThreshold <= 1.0,
                     "compactionThreshold must be between 0 and 1")
        precondition(warningThreshold > 0 && warningThreshold <= compactionThreshold,
                     "warningThreshold must be between 0 and compactionThreshold")

        self.contextWindowSize = contextWindowSize
        self.compactionThreshold = compactionThreshold
        self.warningThreshold = warningThreshold
        self.strategy = strategy
        self.reservedResponseTokens = reservedResponseTokens
    }

    /// Creates a context manager from configuration.
    ///
    /// - Parameter configuration: The context configuration.
    public init(configuration: ContextConfiguration) {
        self.contextWindowSize = configuration.contextWindowSize
        self.compactionThreshold = configuration.compactionThreshold
        self.warningThreshold = configuration.warningThreshold
        self.strategy = configuration.strategy
        self.reservedResponseTokens = configuration.reservedResponseTokens
    }

    // MARK: - Usage Calculation

    /// Calculates current context usage for a transcript.
    ///
    /// - Parameter transcript: The transcript to analyze.
    /// - Returns: Current usage statistics.
    public func calculateUsage(for transcript: Transcript) -> ContextUsage {
        let estimatedTokens = estimateTokens(for: transcript)

        var toolCallCount = 0
        var responseCount = 0

        for entry in transcript {
            switch entry {
            case .toolCalls:
                toolCallCount += 1
            case .response:
                responseCount += 1
            default:
                break
            }
        }

        let usage = ContextUsage(
            estimatedTokens: estimatedTokens,
            contextWindowSize: contextWindowSize - reservedResponseTokens,
            entryCount: transcript.count,
            toolCallCount: toolCallCount,
            responseCount: responseCount
        )

        lastUsage = usage
        return usage
    }

    /// Estimates token count for a transcript.
    ///
    /// Uses character-based estimation with adjustments for
    /// different entry types.
    private func estimateTokens(for transcript: Transcript) -> Int {
        var totalChars = 0

        for entry in transcript {
            totalChars += estimateEntryCharacters(entry)
        }

        return Int(Double(totalChars) / charsPerToken)
    }

    /// Estimates character count for a single entry.
    private func estimateEntryCharacters(_ entry: Transcript.Entry) -> Int {
        switch entry {
        case .instructions(let instructions):
            // Instructions include system prompt and tool definitions
            // Add overhead for formatting
            return instructions.description.count + 500

        case .prompt(let prompt):
            return prompt.description.count

        case .response(let response):
            return response.description.count

        case .toolCalls(let toolCalls):
            return toolCalls.reduce(0) { total, call in
                total + call.toolName.count + 100 // Arguments are already counted in toolName + overhead
            }

        case .toolOutput(let output):
            return output.description.count
        }
    }

    // MARK: - Compaction

    /// Result of a compaction operation.
    public struct CompactionResult: Sendable {
        /// Original token count before compaction.
        public let originalTokens: Int
        /// Token count after compaction.
        public let compactedTokens: Int
        /// Number of tokens saved.
        public let tokensSaved: Int
        /// Number of entries removed.
        public let entriesRemoved: Int
        /// Whether compaction was actually performed.
        public let wasCompacted: Bool
        /// Name of the strategy used.
        public let strategyName: String
        /// Summary of what was compacted.
        public let summary: String
    }

    /// Checks if compaction is needed for the given transcript.
    ///
    /// - Parameter transcript: The transcript to check.
    /// - Returns: `true` if usage exceeds the compaction threshold.
    public func needsCompaction(for transcript: Transcript) -> Bool {
        let usage = calculateUsage(for: transcript)
        return usage.usageRatio >= compactionThreshold
    }

    /// Checks if the usage is at warning level.
    ///
    /// - Parameter transcript: The transcript to check.
    /// - Returns: `true` if usage exceeds the warning threshold but not compaction threshold.
    public func isAtWarningLevel(for transcript: Transcript) -> Bool {
        let usage = calculateUsage(for: transcript)
        return usage.usageRatio >= warningThreshold && usage.usageRatio < compactionThreshold
    }

    /// Compacts the transcript if usage exceeds threshold.
    ///
    /// This method:
    /// 1. Calculates current usage
    /// 2. Applies compaction strategy if threshold exceeded
    /// 3. Returns compacted transcript
    ///
    /// - Parameters:
    ///   - transcript: The transcript to potentially compact.
    ///   - sessionID: The session ID for context.
    /// - Returns: Tuple of (compacted entries, compaction result).
    public func compactIfNeeded(
        transcript: Transcript,
        sessionID: String? = nil
    ) async throws -> ([Transcript.Entry], CompactionResult) {
        let usage = calculateUsage(for: transcript)

        // Check if compaction is needed
        guard usage.usageRatio >= compactionThreshold else {
            return (Array(transcript), CompactionResult(
                originalTokens: usage.estimatedTokens,
                compactedTokens: usage.estimatedTokens,
                tokensSaved: 0,
                entriesRemoved: 0,
                wasCompacted: false,
                strategyName: strategy.name,
                summary: "No compaction needed (\(usage.usagePercentage)% < \(Int(compactionThreshold * 100))%)"
            ))
        }

        // Calculate target tokens (aim for 60% usage after compaction)
        let targetTokens = Int(Double(contextWindowSize - reservedResponseTokens) * 0.60)

        // Create compaction context
        let compactionContext = CompactionContext(
            sessionID: sessionID ?? "",
            currentUsage: usage,
            triggerThreshold: compactionThreshold,
            preservedIndices: preservedIndices
        )

        // Apply compaction strategy
        let compactedResult = try await strategy.compact(
            transcript: transcript,
            targetTokens: targetTokens,
            context: compactionContext
        )

        // Calculate savings
        let newTokens = estimateTokensForEntries(compactedResult.entries)
        let tokensSaved = usage.estimatedTokens - newTokens

        // Update statistics
        compactionCount += 1
        totalTokensSaved += tokensSaved

        return (compactedResult.entries, CompactionResult(
            originalTokens: usage.estimatedTokens,
            compactedTokens: newTokens,
            tokensSaved: tokensSaved,
            entriesRemoved: compactedResult.removedCount,
            wasCompacted: true,
            strategyName: strategy.name,
            summary: compactedResult.summary
        ))
    }

    /// Estimates tokens for an array of entries.
    private func estimateTokensForEntries(_ entries: [Transcript.Entry]) -> Int {
        var totalChars = 0
        for entry in entries {
            totalChars += estimateEntryCharacters(entry)
        }
        return Int(Double(totalChars) / charsPerToken)
    }

    // MARK: - Preservation

    /// Marks an entry index as preserved (will not be removed during compaction).
    ///
    /// - Parameter index: The entry index to preserve.
    public func preserveEntry(at index: Int) {
        preservedIndices.insert(index)
    }

    /// Removes preservation for an entry index.
    ///
    /// - Parameter index: The entry index to unpreserve.
    public func unpreserveEntry(at index: Int) {
        preservedIndices.remove(index)
    }

    /// Clears all preserved entries.
    public func clearPreservedEntries() {
        preservedIndices.removeAll()
    }

    /// Gets all preserved entry indices.
    public var allPreservedIndices: Set<Int> {
        preservedIndices
    }

    // MARK: - Statistics

    /// Statistics about compaction operations.
    public struct Statistics: Sendable {
        /// Number of compaction operations performed.
        public let compactionCount: Int
        /// Total tokens saved across all compactions.
        public let totalTokensSaved: Int
        /// Last calculated usage (if available).
        public let lastUsage: ContextUsage?
        /// Name of the current strategy.
        public let currentStrategy: String
    }

    /// Gets current compaction statistics.
    public var statistics: Statistics {
        Statistics(
            compactionCount: compactionCount,
            totalTokensSaved: totalTokensSaved,
            lastUsage: lastUsage,
            currentStrategy: strategy.name
        )
    }

    /// Resets statistics.
    public func resetStatistics() {
        compactionCount = 0
        totalTokensSaved = 0
        lastUsage = nil
    }

    // MARK: - Factory Methods

    /// Creates a manager optimized for long conversations.
    ///
    /// Uses a lower threshold and summarization strategy.
    public static func forLongConversations(
        contextWindowSize: Int = 128_000
    ) -> ContextManager {
        ContextManager(
            contextWindowSize: contextWindowSize,
            compactionThreshold: 0.75,
            warningThreshold: 0.65,
            strategy: SlidingWindowCompactionStrategy(windowSize: 30)
        )
    }

    /// Creates a manager optimized for tool-heavy workflows.
    ///
    /// Uses a higher threshold and priority-based strategy.
    public static func forToolIntensiveWorkflows(
        contextWindowSize: Int = 128_000
    ) -> ContextManager {
        ContextManager(
            contextWindowSize: contextWindowSize,
            compactionThreshold: 0.85,
            warningThreshold: 0.75,
            strategy: PriorityCompactionStrategy(
                typePriorities: [
                    "instructions": 100,
                    "prompt": 80,
                    "response": 60,
                    "toolCalls": 40,
                    "toolOutput": 20
                ]
            )
        )
    }
}
