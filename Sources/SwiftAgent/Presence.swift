// MARK: - Presence
// Declaration of existence for agents
// Inspired by Bonjour's service announcement mechanism

import Foundation

// MARK: - Default TTL Values (inspired by Bonjour)

/// Standard TTL for presence announcements (75 minutes, same as Bonjour's kStandardTTL)
public let kStandardPresenceTTL: TimeInterval = 4500

/// Short TTL for transient presences (2 minutes)
public let kShortPresenceTTL: TimeInterval = 120

/// Long TTL for stable presences (2 hours)
public let kLongPresenceTTL: TimeInterval = 7200

/// Goodbye TTL (0 seconds - indicates the presence is being withdrawn)
public let kGoodbyePresenceTTL: TimeInterval = 0

/// Presence - Declaration of existence
///
/// An agent broadcasts its Presence to announce:
/// 1. Who it is (Identity)
/// 2. What it can receive (Perceptions)
/// 3. How long this presence is valid (TTL)
///
/// Inspired by Bonjour's service announcement mechanism:
/// - TTL enables cache management and stale presence detection
/// - Perceptions define the agent's input capabilities
///
/// Other agents discover Presence to find potential communication partners.
/// Communication is possible when the sender's output capability matches
/// the receiver's Perception.
public struct Presence<ID: Hashable & Sendable & Codable>: Sendable, Identifiable, Codable {

    /// Identity - who is this agent
    public let id: ID

    /// Perception identifiers - what can this agent receive
    /// Examples: ["visual", "auditory", "network"]
    public let perceptions: [String]

    /// When this presence was declared
    public let timestamp: Date

    /// Time-to-live in seconds - how long this presence should be considered valid
    /// Inspired by Bonjour's TTL mechanism for cache management
    public let ttl: TimeInterval

    /// Sequence number for ordering multiple announcements
    /// Used for conflict detection and resolution
    public let sequenceNumber: UInt64

    // MARK: - Initialization

    /// Create a new Presence
    /// - Parameters:
    ///   - id: The agent's identity
    ///   - perceptions: List of perception identifiers the agent can receive
    ///   - timestamp: When this presence was created (defaults to now)
    ///   - ttl: Time-to-live in seconds (default: kStandardPresenceTTL)
    ///   - sequenceNumber: Sequence number for ordering (default: 0)
    public init(
        id: ID,
        perceptions: [String],
        timestamp: Date = Date(),
        ttl: TimeInterval = kStandardPresenceTTL,
        sequenceNumber: UInt64 = 0
    ) {
        self.id = id
        self.perceptions = perceptions
        self.timestamp = timestamp
        self.ttl = ttl
        self.sequenceNumber = sequenceNumber
    }

    /// Create a Presence from an array of Perception objects
    /// - Parameters:
    ///   - id: The agent's identity
    ///   - perceptions: Array of Perception objects
    ///   - timestamp: When this presence was created (defaults to now)
    ///   - ttl: Time-to-live in seconds (default: kStandardPresenceTTL)
    ///   - sequenceNumber: Sequence number for ordering (default: 0)
    public init<P: Perception>(
        id: ID,
        perceptions: [P],
        timestamp: Date = Date(),
        ttl: TimeInterval = kStandardPresenceTTL,
        sequenceNumber: UInt64 = 0
    ) {
        self.id = id
        self.perceptions = perceptions.map { $0.identifier }
        self.timestamp = timestamp
        self.ttl = ttl
        self.sequenceNumber = sequenceNumber
    }

    /// Create a Presence from an array of existential Perception objects
    /// - Parameters:
    ///   - id: The agent's identity
    ///   - perceptions: Array of any Perception objects
    ///   - timestamp: When this presence was created (defaults to now)
    ///   - ttl: Time-to-live in seconds (default: kStandardPresenceTTL)
    ///   - sequenceNumber: Sequence number for ordering (default: 0)
    public init(
        id: ID,
        perceptions: [any Perception],
        timestamp: Date = Date(),
        ttl: TimeInterval = kStandardPresenceTTL,
        sequenceNumber: UInt64 = 0
    ) {
        self.id = id
        self.perceptions = perceptions.map { $0.identifier }
        self.timestamp = timestamp
        self.ttl = ttl
        self.sequenceNumber = sequenceNumber
    }

    // MARK: - Goodbye Presence

    /// Create a goodbye presence (announcing withdrawal)
    /// - Returns: A presence with TTL of 0, indicating this agent is leaving
    public func goodbye() -> Presence<ID> {
        Presence(
            id: id,
            perceptions: perceptions,
            timestamp: Date(),
            ttl: kGoodbyePresenceTTL,
            sequenceNumber: sequenceNumber + 1
        )
    }

    /// Whether this is a goodbye announcement (TTL = 0)
    public var isGoodbye: Bool {
        ttl == kGoodbyePresenceTTL
    }
}

// MARK: - Presence Extensions

extension Presence {
    /// Check if this agent can receive a specific perception type
    /// - Parameter identifier: The perception identifier to check
    /// - Returns: true if the agent can receive this perception type
    public func canReceive(_ identifier: String) -> Bool {
        perceptions.contains(identifier)
    }

    /// Check if this agent can receive any of the specified perception types
    /// - Parameter identifiers: The perception identifiers to check
    /// - Returns: true if the agent can receive any of these perception types
    public func canReceiveAny(of identifiers: [String]) -> Bool {
        !Set(perceptions).isDisjoint(with: Set(identifiers))
    }

    /// Check if this agent can receive all of the specified perception types
    /// - Parameter identifiers: The perception identifiers to check
    /// - Returns: true if the agent can receive all of these perception types
    public func canReceiveAll(of identifiers: [String]) -> Bool {
        Set(identifiers).isSubset(of: Set(perceptions))
    }

    /// Create an updated Presence with a new timestamp and incremented sequence number
    /// - Parameter timestamp: The new timestamp (defaults to now)
    /// - Returns: A new Presence with the updated timestamp
    public func refreshed(timestamp: Date = Date()) -> Presence<ID> {
        Presence(
            id: id,
            perceptions: perceptions,
            timestamp: timestamp,
            ttl: ttl,
            sequenceNumber: sequenceNumber + 1
        )
    }

    /// Check if this presence is stale (older than the specified duration)
    /// - Parameter duration: The maximum age before considered stale
    /// - Returns: true if the presence is stale
    public func isStale(after duration: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > duration
    }

    /// Check if this presence has expired based on its TTL
    ///
    /// Note: This calculates expiration from the presence's creation timestamp.
    /// For cached presences, use `CachedPresence.isExpired` which calculates
    /// from the time the presence was received (accounting for network latency).
    /// - Returns: true if the presence has expired
    public var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }

    /// Calculate the expiration date of this presence
    /// - Returns: The date when this presence will expire
    public var expirationDate: Date {
        timestamp.addingTimeInterval(ttl)
    }

    /// Calculate the remaining time before this presence expires
    /// - Returns: The remaining time in seconds, or 0 if already expired
    public var remainingTTL: TimeInterval {
        max(0, ttl - Date().timeIntervalSince(timestamp))
    }

    /// Create a new presence with updated TTL
    /// - Parameter newTTL: The new TTL value
    /// - Returns: A new Presence with the updated TTL
    public func withTTL(_ newTTL: TimeInterval) -> Presence<ID> {
        Presence(
            id: id,
            perceptions: perceptions,
            timestamp: timestamp,
            ttl: newTTL,
            sequenceNumber: sequenceNumber
        )
    }
}

// MARK: - Equatable & Hashable

extension Presence: Equatable where ID: Equatable {
    public static func == (lhs: Presence<ID>, rhs: Presence<ID>) -> Bool {
        lhs.id == rhs.id && lhs.perceptions == rhs.perceptions
    }
}

extension Presence: Hashable where ID: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(perceptions)
    }
}

// MARK: - CustomStringConvertible

extension Presence: CustomStringConvertible {
    public var description: String {
        "Presence(id: \(id), perceptions: \(perceptions), ttl: \(ttl)s)"
    }
}
