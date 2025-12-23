//
//  ContextUsage.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Statistics about context window usage.
///
/// `ContextUsage` provides real-time tracking of token consumption
/// and context window utilization for an agent session.
///
/// ## Example
///
/// ```swift
/// let usage = await contextManager.calculateUsage(for: transcript)
/// print("Using \(usage.usagePercentage)% of context")
///
/// if usage.isAboveCriticalThreshold() {
///     // Trigger compaction
/// }
/// ```
public struct ContextUsage: Sendable, Codable, Equatable {

    /// Estimated tokens used by the current transcript.
    public let estimatedTokens: Int

    /// Maximum context window size for the model.
    public let contextWindowSize: Int

    /// Number of entries in the transcript.
    public let entryCount: Int

    /// Number of tool call entries.
    public let toolCallCount: Int

    /// Number of response entries.
    public let responseCount: Int

    /// Timestamp when this usage was calculated.
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        estimatedTokens: Int,
        contextWindowSize: Int,
        entryCount: Int,
        toolCallCount: Int,
        responseCount: Int,
        timestamp: Date = Date()
    ) {
        self.estimatedTokens = estimatedTokens
        self.contextWindowSize = contextWindowSize
        self.entryCount = entryCount
        self.toolCallCount = toolCallCount
        self.responseCount = responseCount
        self.timestamp = timestamp
    }

    // MARK: - Computed Properties

    /// Usage ratio (0.0 to 1.0).
    public var usageRatio: Double {
        guard contextWindowSize > 0 else { return 0 }
        return Double(estimatedTokens) / Double(contextWindowSize)
    }

    /// Percentage of context used (0 to 100).
    public var usagePercentage: Int {
        Int(usageRatio * 100)
    }

    /// Remaining tokens available.
    public var remainingTokens: Int {
        max(0, contextWindowSize - estimatedTokens)
    }

    /// Whether the context is empty.
    public var isEmpty: Bool {
        entryCount == 0
    }

    // MARK: - Threshold Checks

    /// Whether the usage is above the warning threshold.
    ///
    /// - Parameter threshold: Warning threshold ratio (default: 0.70 = 70%).
    /// - Returns: `true` if usage exceeds the threshold.
    public func isAboveWarningThreshold(_ threshold: Double = 0.70) -> Bool {
        usageRatio >= threshold
    }

    /// Whether the usage is above the critical threshold.
    ///
    /// - Parameter threshold: Critical threshold ratio (default: 0.80 = 80%).
    /// - Returns: `true` if usage exceeds the threshold.
    public func isAboveCriticalThreshold(_ threshold: Double = 0.80) -> Bool {
        usageRatio >= threshold
    }

    /// Whether the usage is below the target threshold after compaction.
    ///
    /// - Parameter threshold: Target threshold ratio (default: 0.60 = 60%).
    /// - Returns: `true` if usage is at or below the threshold.
    public func isBelowTargetThreshold(_ threshold: Double = 0.60) -> Bool {
        usageRatio <= threshold
    }
}

// MARK: - CustomStringConvertible

extension ContextUsage: CustomStringConvertible {

    public var description: String {
        """
        ContextUsage(
            tokens: \(estimatedTokens)/\(contextWindowSize) (\(usagePercentage)%),
            entries: \(entryCount),
            tools: \(toolCallCount),
            responses: \(responseCount)
        )
        """
    }
}

// MARK: - Factory Methods

extension ContextUsage {

    /// Creates an empty usage instance.
    ///
    /// - Parameter contextWindowSize: Maximum context window size.
    /// - Returns: A `ContextUsage` with zero usage.
    public static func empty(contextWindowSize: Int) -> ContextUsage {
        ContextUsage(
            estimatedTokens: 0,
            contextWindowSize: contextWindowSize,
            entryCount: 0,
            toolCallCount: 0,
            responseCount: 0
        )
    }
}
