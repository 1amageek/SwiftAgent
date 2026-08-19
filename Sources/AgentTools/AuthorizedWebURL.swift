import Foundation

public struct AuthorizedWebURL: Sendable, Hashable {
    public let url: URL
    public let policyIdentifier: String

    public init(url: URL, policyIdentifier: String) {
        self.url = url
        self.policyIdentifier = policyIdentifier
    }
}
