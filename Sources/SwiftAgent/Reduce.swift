//
//  Reduce.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation


/// A step that combines elements of a collection into a single value
///
/// Use `Reduce` when you need to process a collection of elements sequentially,
/// accumulating a result as you go. Each element is processed with access to the
/// current accumulated result and the element's index.
///
/// Example:
/// ```swift
/// struct MetricAggregator: Agent {
///     var body: some Step<[Metric], Summary> {
///         Reduce(initial: Summary()) { summary, metric, index in
///             // Process each metric and update summary
///             Transform { input in
///                 summary.adding(metric, at: index)
///             }
///         }
///     }
/// }
/// ```
public struct Reduce<Input: Collection & Sendable, Output: Sendable>: Step where Input.Element: Sendable {
    /// A closure that produces a step to process each element and accumulate the result
    private let process: (Output, Input.Element, Int) -> any Step<Output, Output>
    
    /// The initial value for the reduction
    private let initial: Output
    
    /// Creates a new reduce step with the specified initial value and processing step
    ///
    /// - Parameters:
    ///   - initial: The initial value to start the reduction
    ///   - process: A closure that produces a step to process each element.
    ///             The closure receives the current accumulated value, the element,
    ///             and the element's index in the collection.
    public init(
        initial: Output,
        @StepBuilder process: @escaping (Output, Input.Element, Int) -> any Step<Output, Output>
    ) {
        self.initial = initial
        self.process = process
    }
    
    /// Executes the reduce step on the input collection
    ///
    /// - Parameter input: The collection to reduce
    /// - Returns: The final accumulated value
    /// - Throws: Any error that occurs during the reduction process
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        var result = initial
        var index = 0
        
        for element in input {
            let step = process(result, element, index)
            result = try await step.run(result)
            index += 1
        }
        
        return result
    }
}

