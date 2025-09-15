//
//  Map.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation


/// A step that transforms each element in a collection using a specified step
///
/// Use `Map` when you need to process each element in a collection independently.
/// The transformation is applied to each element in sequence, with access to the element's index.
///
/// Example:
/// ```swift
/// struct DocumentProcessor: Agent {
///     var body: some Step<[Document], [ProcessedDocument]> {
///         Map { document, index in
///             // Process each document
///             DocumentAnalyzer()
///
///             // Add metadata
///             Transform { doc in
///                 doc.addingMetadata(processedAt: index)
///             }
///         }
///     }
/// }
/// ```
public struct Map<InElement: Sendable, OutElement: Sendable>: Step {
    public typealias Input = [InElement]
    public typealias Output = [OutElement]
    
    /// A closure that produces a step to transform each element
    private let transform: (InElement, Int) -> AnyStep<InElement, OutElement>
    
    /// Creates a new map step with the specified transformation
    ///
    /// - Parameter transform: A closure that produces a step to transform each element.
    ///                       The closure receives the element and its index in the collection.
    public init(
        @StepBuilder transform: @escaping (
            InElement,
            Int
        ) -> AnyStep<InElement, OutElement>
    ) {
        self.transform = transform
    }
    
    /// Executes the map step on the input collection
    ///
    /// - Parameter input: The collection to transform
    /// - Returns: An array containing the transformed elements
    /// - Throws: Any error that occurs during the transformation of elements
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        var results: [OutElement] = []
        var index = 0
        
        for element in input {
            let step = transform(element, index)
            let partialOutput = try await step.run(element)
            results.append(partialOutput)
            index += 1
        }
        
        return results
    }
}

