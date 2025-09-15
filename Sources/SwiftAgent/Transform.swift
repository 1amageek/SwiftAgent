//
//  Transform.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation


/// A step that performs a simple transformation using a closure
///
/// Use `Transform` when you need to perform a straightforward transformation
/// of data without the complexity of a full step implementation.
///
/// Example:
/// ```swift
/// struct DataNormalizer: Agent {
///     var body: some Step<RawData, NormalizedData> {
///         // Preprocess data
///         Transform { raw in
///             raw.preprocessed()
///         }
///
///         // Apply normalization
///         Transform { data in
///             data.normalized()
///         }
///     }
/// }
/// ```
public struct Transform<Input: Sendable, Output: Sendable>: Step {
    /// The transformation closure
    private let transformer: (Input) async throws -> Output
    
    /// Creates a new transform step with the specified transformation closure
    ///
    /// - Parameter transformer: A closure that transforms the input into the output
    public init(
        transformer: @escaping (Input) async throws -> Output
    ) {
        self.transformer = transformer
    }
    
    /// Executes the transform step on the input
    ///
    /// - Parameter input: The value to transform
    /// - Returns: The transformed value
    /// - Throws: Any error that occurs during the transformation
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        try await transformer(input)
    }
}
