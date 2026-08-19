public struct RollupPolicy: Sendable, Codable, Hashable {
    public let availabilityRule: RollupRule
    public let degradationMode: DegradationMode

    public init(
        availabilityRule: RollupRule,
        degradationMode: DegradationMode = .partialCapability
    ) {
        self.availabilityRule = availabilityRule
        self.degradationMode = degradationMode
    }
}
