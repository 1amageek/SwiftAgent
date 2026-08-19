import Foundation

public struct WebDocumentCacheConfiguration: Sendable {
    public let timeToLive: TimeInterval
    public let maximumEntries: Int
    public let maximumTotalBodyBytes: Int

    public init(
        timeToLive: TimeInterval = 15 * 60,
        maximumEntries: Int = 64,
        maximumTotalBodyBytes: Int = 20 * 1_024 * 1_024
    ) {
        self.timeToLive = timeToLive
        self.maximumEntries = maximumEntries
        self.maximumTotalBodyBytes = maximumTotalBodyBytes
    }

    public static let disabled = Self(
        timeToLive: 0,
        maximumEntries: 0,
        maximumTotalBodyBytes: 0
    )

    func validate() throws {
        guard timeToLive.isFinite, timeToLive >= 0 else {
            throw WebHTTPError.invalidCacheConfiguration(
                "timeToLive must be finite and nonnegative"
            )
        }
        guard maximumEntries >= 0, maximumTotalBodyBytes >= 0 else {
            throw WebHTTPError.invalidCacheConfiguration(
                "entry and byte limits must be nonnegative"
            )
        }
        let isDisabled = timeToLive == 0
            && maximumEntries == 0
            && maximumTotalBodyBytes == 0
        let isEnabled = timeToLive > 0
            && maximumEntries > 0
            && maximumTotalBodyBytes > 0
        guard isDisabled || isEnabled else {
            throw WebHTTPError.invalidCacheConfiguration(
                "all limits must be zero to disable caching or positive to enable it"
            )
        }
    }
}
