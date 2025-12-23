//
//  ContextConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Configuration for context management.
///
/// Use this to configure how context is managed for an agent session,
/// including automatic compaction thresholds and strategies.
///
/// ## Example
///
/// ```swift
/// // Use default settings
/// let config = ContextConfiguration.default
///
/// // Customize for long conversations
/// let config = ContextConfiguration.longConversation
///
/// // Full customization
/// let config = ContextConfiguration(
///     contextWindowSize: 200_000,
///     compactionThreshold: 0.85,
///     strategy: PriorityCompactionStrategy()
/// )
/// ```
public struct ContextConfiguration: Sendable {

    /// Whether context management is enabled.
    public var enabled: Bool

    /// Maximum context window size in tokens.
    public var contextWindowSize: Int

    /// Threshold (0.0 to 1.0) at which to trigger compaction.
    public var compactionThreshold: Double

    /// Warning threshold for notifications (0.0 to 1.0).
    public var warningThreshold: Double

    /// Tokens to reserve for the response.
    public var reservedResponseTokens: Int

    /// The compaction strategy to use.
    public var strategy: any CompactionStrategy

    /// Whether to automatically compact when threshold is exceeded.
    public var autoCompact: Bool

    // MARK: - Initialization

    /// Creates a context configuration.
    ///
    /// - Parameters:
    ///   - enabled: Whether context management is enabled (default: true).
    ///   - contextWindowSize: Maximum context window size in tokens (default: 128,000).
    ///   - compactionThreshold: Ratio to trigger compaction (default: 0.80).
    ///   - warningThreshold: Ratio for warning notifications (default: 0.70).
    ///   - reservedResponseTokens: Tokens reserved for response (default: 4,000).
    ///   - strategy: Compaction strategy (default: HybridCompactionStrategy).
    ///   - autoCompact: Whether to auto-compact (default: true).
    public init(
        enabled: Bool = true,
        contextWindowSize: Int = 128_000,
        compactionThreshold: Double = 0.80,
        warningThreshold: Double = 0.70,
        reservedResponseTokens: Int = 4_000,
        strategy: any CompactionStrategy = HybridCompactionStrategy(),
        autoCompact: Bool = true
    ) {
        self.enabled = enabled
        self.contextWindowSize = contextWindowSize
        self.compactionThreshold = compactionThreshold
        self.warningThreshold = warningThreshold
        self.reservedResponseTokens = reservedResponseTokens
        self.strategy = strategy
        self.autoCompact = autoCompact
    }

    // MARK: - Factory Methods

    /// Disabled context management.
    public static let disabled = ContextConfiguration(enabled: false)

    /// Default configuration for Claude models.
    ///
    /// - Context window: 128,000 tokens
    /// - Compaction threshold: 80%
    /// - Warning threshold: 70%
    /// - Strategy: Hybrid
    public static let `default` = ContextConfiguration()

    /// Configuration for long conversation sessions.
    ///
    /// Uses a lower threshold and sliding window strategy for
    /// conversations that span many turns.
    ///
    /// - Context window: 128,000 tokens
    /// - Compaction threshold: 75%
    /// - Strategy: SlidingWindow with 30 entries
    public static var longConversation: ContextConfiguration {
        ContextConfiguration(
            compactionThreshold: 0.75,
            warningThreshold: 0.65,
            strategy: SlidingWindowCompactionStrategy(windowSize: 30)
        )
    }

    /// Configuration for tool-intensive workflows.
    ///
    /// Uses a higher threshold and priority-based strategy to
    /// preserve important tool interactions.
    ///
    /// - Context window: 128,000 tokens
    /// - Compaction threshold: 85%
    /// - Strategy: Priority-based
    public static var toolIntensive: ContextConfiguration {
        ContextConfiguration(
            compactionThreshold: 0.85,
            warningThreshold: 0.75,
            strategy: PriorityCompactionStrategy()
        )
    }

    /// Configuration for minimal context overhead.
    ///
    /// Uses aggressive truncation to keep context small.
    ///
    /// - Context window: 128,000 tokens
    /// - Compaction threshold: 60%
    /// - Strategy: Truncation with 5 recent entries
    public static var minimal: ContextConfiguration {
        ContextConfiguration(
            compactionThreshold: 0.60,
            warningThreshold: 0.50,
            strategy: TruncationCompactionStrategy(preserveRecentCount: 5)
        )
    }

    // MARK: - Builder Methods

    /// Returns a copy with the specified context window size.
    public func withContextWindowSize(_ size: Int) -> ContextConfiguration {
        var copy = self
        copy.contextWindowSize = size
        return copy
    }

    /// Returns a copy with the specified compaction threshold.
    public func withCompactionThreshold(_ threshold: Double) -> ContextConfiguration {
        var copy = self
        copy.compactionThreshold = threshold
        return copy
    }

    /// Returns a copy with the specified warning threshold.
    public func withWarningThreshold(_ threshold: Double) -> ContextConfiguration {
        var copy = self
        copy.warningThreshold = threshold
        return copy
    }

    /// Returns a copy with the specified reserved response tokens.
    public func withReservedResponseTokens(_ tokens: Int) -> ContextConfiguration {
        var copy = self
        copy.reservedResponseTokens = tokens
        return copy
    }

    /// Returns a copy with the specified strategy.
    public func withStrategy(_ strategy: any CompactionStrategy) -> ContextConfiguration {
        var copy = self
        copy.strategy = strategy
        return copy
    }

    /// Returns a copy with auto-compact enabled or disabled.
    public func withAutoCompact(_ enabled: Bool) -> ContextConfiguration {
        var copy = self
        copy.autoCompact = enabled
        return copy
    }

    /// Returns a copy that is enabled.
    public func enabling() -> ContextConfiguration {
        var copy = self
        copy.enabled = true
        return copy
    }

    /// Returns a copy that is disabled.
    public func disabling() -> ContextConfiguration {
        var copy = self
        copy.enabled = false
        return copy
    }
}

// MARK: - CustomStringConvertible

extension ContextConfiguration: CustomStringConvertible {

    public var description: String {
        """
        ContextConfiguration(
            enabled: \(enabled),
            contextWindow: \(contextWindowSize),
            threshold: \(Int(compactionThreshold * 100))%,
            strategy: \(strategy.name),
            autoCompact: \(autoCompact)
        )
        """
    }
}

// MARK: - Validation

extension ContextConfiguration {

    /// Validates the configuration.
    ///
    /// - Throws: An error if the configuration is invalid.
    public func validate() throws {
        guard contextWindowSize > 0 else {
            throw ContextConfigurationError.invalidContextWindowSize
        }

        guard compactionThreshold > 0 && compactionThreshold <= 1.0 else {
            throw ContextConfigurationError.invalidCompactionThreshold
        }

        guard warningThreshold > 0 && warningThreshold <= compactionThreshold else {
            throw ContextConfigurationError.invalidWarningThreshold
        }

        guard reservedResponseTokens >= 0 && reservedResponseTokens < contextWindowSize else {
            throw ContextConfigurationError.invalidReservedTokens
        }
    }
}

/// Errors related to context configuration.
public enum ContextConfigurationError: Error, LocalizedError {
    case invalidContextWindowSize
    case invalidCompactionThreshold
    case invalidWarningThreshold
    case invalidReservedTokens

    public var errorDescription: String? {
        switch self {
        case .invalidContextWindowSize:
            return "Context window size must be greater than 0"
        case .invalidCompactionThreshold:
            return "Compaction threshold must be between 0 and 1"
        case .invalidWarningThreshold:
            return "Warning threshold must be between 0 and compaction threshold"
        case .invalidReservedTokens:
            return "Reserved tokens must be non-negative and less than context window size"
        }
    }
}
