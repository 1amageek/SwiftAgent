import Foundation

/// Authorizes administrator-controlled origins by exact scheme, host, and port.
///
/// This policy intentionally does not treat arbitrary public host names as
/// trusted and does not claim to pin DNS resolution. Use a `WebHTTPClient`
/// with endpoint binding when untrusted origins must be fetched.
public struct TrustedOriginsWebURLPolicy: WebURLPolicy {
    private let origins: Set<WebOrigin>
    private let policyIdentifier: String

    public init(
        origins: Set<WebOrigin>,
        policyIdentifier: String = "trusted-origins"
    ) {
        self.origins = origins
        self.policyIdentifier = policyIdentifier
    }

    public func authorize(_ url: URL) async throws -> AuthorizedWebURL {
        guard url.user == nil, url.password == nil else {
            throw WebHTTPError.userInformationNotAllowed
        }
        let origin = try WebOrigin(url: url)
        guard origins.contains(origin) else {
            throw WebHTTPError.originNotAuthorized(origin.description)
        }

        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw WebHTTPError.invalidURL(url.absoluteString)
        }
        components.fragment = nil
        guard let normalizedURL = components.url else {
            throw WebHTTPError.invalidURL(url.absoluteString)
        }
        return AuthorizedWebURL(
            url: normalizedURL,
            policyIdentifier: policyIdentifier
        )
    }
}
