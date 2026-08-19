public enum RollupRule: Sendable, Codable, Hashable {
    case all
    case any
    case quorum(Double)
    case minimumCount(Int)
    case weightedThreshold(Double)
}
