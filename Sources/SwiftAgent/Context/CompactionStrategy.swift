//
//  CompactionStrategy.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// A strategy for compacting conversation context when approaching limits.
///
/// Implement this protocol to define custom compaction behaviors.
/// The framework provides several built-in strategies:
///
/// - ``TruncationCompactionStrategy``: Removes oldest entries
/// - ``SummarizationCompactionStrategy``: Summarizes older entries using LLM
/// - ``PriorityCompactionStrategy``: Removes entries based on priority scores
/// - ``HybridCompactionStrategy``: Combines multiple strategies
///
/// ## Example
///
/// ```swift
/// struct CustomStrategy: CompactionStrategy {
///     let name = "custom"
///     let description = "My custom compaction logic"
///
///     func compact(
///         transcript: Transcript,
///         targetTokens: Int,
///         context: CompactionContext
///     ) async throws -> CompactedTranscript {
///         // Custom compaction logic
///     }
/// }
/// ```
public protocol CompactionStrategy: Sendable {

    /// A unique identifier for this strategy.
    var name: String { get }

    /// A human-readable description of what this strategy does.
    var description: String { get }

    /// Compacts the given transcript to reduce token usage.
    ///
    /// - Parameters:
    ///   - transcript: The current transcript to compact.
    ///   - targetTokens: Target token count after compaction.
    ///   - context: Additional context for compaction decisions.
    /// - Returns: A compacted transcript with metadata.
    func compact(
        transcript: Transcript,
        targetTokens: Int,
        context: CompactionContext
    ) async throws -> CompactedTranscript

    /// Estimates the tokens that would be saved by this strategy.
    ///
    /// This is used for deciding which strategy to apply without
    /// actually performing the compaction.
    ///
    /// - Parameter transcript: The transcript to analyze.
    /// - Returns: Estimated tokens that would be removed.
    func estimateSavings(for transcript: Transcript) async -> Int
}

// MARK: - Default Implementation

extension CompactionStrategy {

    public func estimateSavings(for transcript: Transcript) async -> Int {
        // Default: estimate 30% savings
        return Int(Double(transcript.count) * 0.3)
    }
}

// MARK: - CompactionContext

/// Context information for compaction decisions.
///
/// Provides all the information a compaction strategy needs to make
/// intelligent decisions about what to keep and what to remove.
public struct CompactionContext: Sendable {

    /// The session ID.
    public let sessionID: String

    /// Current token usage.
    public let currentUsage: ContextUsage

    /// The threshold that triggered compaction.
    public let triggerThreshold: Double

    /// Important entry indices that should be preserved if possible.
    public let preservedIndices: Set<Int>

    /// Custom metadata for strategy-specific decisions.
    public let metadata: [String: String]

    // MARK: - Initialization

    public init(
        sessionID: String,
        currentUsage: ContextUsage,
        triggerThreshold: Double,
        preservedIndices: Set<Int> = [],
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.currentUsage = currentUsage
        self.triggerThreshold = triggerThreshold
        self.preservedIndices = preservedIndices
        self.metadata = metadata
    }
}

// MARK: - CompactedTranscript

/// Result of a compaction operation.
///
/// Contains the compacted transcript along with metadata about
/// what was removed or modified.
public struct CompactedTranscript: Sendable {

    /// The compacted transcript entries.
    public let entries: [Transcript.Entry]

    /// Number of entries that were removed.
    public let removedCount: Int

    /// Number of entries that were summarized.
    public let summarizedCount: Int

    /// Summary of what was compacted (for debugging/logging).
    public let summary: String

    // MARK: - Initialization

    public init(
        entries: [Transcript.Entry],
        removedCount: Int = 0,
        summarizedCount: Int = 0,
        summary: String = ""
    ) {
        self.entries = entries
        self.removedCount = removedCount
        self.summarizedCount = summarizedCount
        self.summary = summary
    }

    /// Creates a result indicating no compaction was performed.
    public static func unchanged(_ transcript: Transcript) -> CompactedTranscript {
        CompactedTranscript(
            entries: Array(transcript),
            removedCount: 0,
            summarizedCount: 0,
            summary: "No compaction performed"
        )
    }
}

// MARK: - CompactionError

/// Errors that can occur during compaction.
public enum CompactionError: Error, LocalizedError {

    /// The transcript is already below the target size.
    case alreadyBelowTarget

    /// The transcript cannot be compacted further without losing critical data.
    case cannotCompactFurther

    /// An error occurred during summarization.
    case summarizationFailed(underlying: Error)

    /// The strategy is not applicable to the current transcript.
    case strategyNotApplicable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyBelowTarget:
            return "Transcript is already below target token count"
        case .cannotCompactFurther:
            return "Cannot compact further without losing critical data"
        case .summarizationFailed(let error):
            return "Summarization failed: \(error.localizedDescription)"
        case .strategyNotApplicable(let reason):
            return "Strategy not applicable: \(reason)"
        }
    }
}
