// MARK: - Perception
// Signal pathway to consciousness
// Based on the eight consciousnesses model

import Foundation

/// Perception - Signal pathway to consciousness
///
/// Perception represents how an agent receives information from the environment
/// or other agents. It is not a fixed list but extensible based on the agent's
/// physical capabilities.
///
/// Examples:
/// - Visual: Image data from cameras
/// - Auditory: Audio data from microphones
/// - Network: Text messages from other agents
/// - Custom: Any sensor-based input
public protocol Perception: Sendable {
    /// Unique identifier for this perception type
    /// Examples: "visual", "auditory", "network", "tactile"
    var identifier: String { get }

    /// The type of signal this perception handles
    associatedtype Signal: Sendable
}

// MARK: - Standard Signal Types

/// Visual signal containing image data
public struct VisualSignal: Sendable, Codable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let timestamp: Date

    public init(data: Data, width: Int, height: Int, timestamp: Date = Date()) {
        self.data = data
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}

/// Auditory signal containing audio data
public struct AuditorySignal: Sendable, Codable {
    public let data: Data
    public let sampleRate: Int
    public let channels: Int
    public let timestamp: Date

    public init(data: Data, sampleRate: Int, channels: Int, timestamp: Date = Date()) {
        self.data = data
        self.sampleRate = sampleRate
        self.channels = channels
        self.timestamp = timestamp
    }
}

/// Tactile signal containing touch/pressure data
public struct TactileSignal: Sendable, Codable {
    public let pressure: Double
    public let locationX: Double
    public let locationY: Double
    public let timestamp: Date

    /// Computed property for backward compatibility
    public var location: (x: Double, y: Double) {
        (x: locationX, y: locationY)
    }

    public init(pressure: Double, location: (x: Double, y: Double), timestamp: Date = Date()) {
        self.pressure = pressure
        self.locationX = location.x
        self.locationY = location.y
        self.timestamp = timestamp
    }

    public init(pressure: Double, locationX: Double, locationY: Double, timestamp: Date = Date()) {
        self.pressure = pressure
        self.locationX = locationX
        self.locationY = locationY
        self.timestamp = timestamp
    }
}

/// Network signal for agent-to-agent communication
public struct NetworkSignal: Sendable, Codable {
    public let text: String
    public let sourceIdentifier: String
    public let timestamp: Date

    public init(text: String, sourceIdentifier: String, timestamp: Date = Date()) {
        self.text = text
        self.sourceIdentifier = sourceIdentifier
        self.timestamp = timestamp
    }
}

