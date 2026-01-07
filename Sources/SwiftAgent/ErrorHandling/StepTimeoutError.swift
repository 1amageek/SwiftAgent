//
//  StepTimeoutError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// An error that indicates a step execution exceeded its timeout duration.
///
/// `StepTimeoutError` is thrown when a step wrapped with `.timeout()` does not
/// complete within the specified duration.
///
/// ## Usage
///
/// ```swift
/// do {
///     let result = try await myStep
///         .timeout(.seconds(10))
///         .run(input)
/// } catch let error as StepTimeoutError {
///     print("Step timed out after \(error.duration)")
/// }
/// ```
///
/// ## Error Handling
///
/// You can handle timeout errors at different levels of your agent hierarchy:
///
/// ```swift
/// // Using Try-Catch
/// Try {
///     FetchStep()
///         .timeout(.seconds(10))
/// } catch: { error in
///     FallbackStep()
/// }
///
/// // In Agent's run method
/// func run(_ input: Query) async throws -> Report {
///     do {
///         return try await body.run(input)
///     } catch let error as StepTimeoutError {
///         return try await SimplifiedAgent().run(input)
///     }
/// }
/// ```
public struct StepTimeoutError: Error, LocalizedError, Sendable {

    /// The duration that was exceeded.
    public let duration: Duration

    /// The name of the step that timed out, if available.
    public let stepName: String?

    /// Creates a new timeout error.
    ///
    /// - Parameters:
    ///   - duration: The timeout duration that was exceeded.
    ///   - stepName: An optional name identifying the step that timed out.
    public init(duration: Duration, stepName: String? = nil) {
        self.duration = duration
        self.stepName = stepName
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        if let name = stepName {
            return "Step '\(name)' timed out after \(duration)"
        }
        return "Step timed out after \(duration)"
    }

    public var failureReason: String? {
        "The operation did not complete within the specified time limit."
    }

    public var recoverySuggestion: String? {
        "Consider increasing the timeout duration, simplifying the operation, or providing a fallback using Try { } catch: { }."
    }
}
