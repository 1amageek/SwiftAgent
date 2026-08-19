public enum DegradationMode: String, Sendable, Codable, Hashable {
    case failClosed
    case bestEffort
    case partialCapability
}
