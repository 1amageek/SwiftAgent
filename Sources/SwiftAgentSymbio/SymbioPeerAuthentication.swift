public struct SymbioPeerAuthentication: Sendable, Codable, Hashable {
    public let method: String
    public let subject: String
    public let attributes: [String: String]

    public init(
        method: String,
        subject: String,
        attributes: [String: String] = [:]
    ) {
        self.method = method
        self.subject = subject
        self.attributes = attributes
    }
}
