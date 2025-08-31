//
//  Tool+Step.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation
import OpenFoundationModels

// MARK: - Step as Tool Direct Conformance

/// Allows any Step to be used directly as a Tool when it meets the requirements.
/// 
/// When a Step type:
/// - Has Input that conforms to ConvertibleFromGeneratedContent & Generable
/// - Has Output that conforms to PromptRepresentable  
/// - Conforms to Sendable
/// - Defines `name` and `description` properties
///
/// Then it can be used directly as a Tool without any wrapper.
///
/// Example:
/// ```swift
/// struct UppercaseStep: Step, Sendable {
///     // Required for Tool conformance
///     let name = "uppercase"
///     let description = "Converts text to uppercase"
///     
///     func run(_ input: String) async throws -> String {
///         input.uppercased()
///     }
/// }
///
/// // Can be used directly as a Tool
/// let tools: [any Tool] = [UppercaseStep()]
/// ```
extension Step where Self: Tool,
                     Input: Generable,
                     Output: PromptRepresentable {
    
    public typealias Arguments = Input
    
    public var name: String {
        String(describing: type(of: self))
    }
    
    /// The parameter schema for the tool, automatically derived from Input type
    public var parameters: GenerationSchema {
        Input.generationSchema
    }
    
    /// Executes the tool by delegating to the Step's run method
    public func call(arguments: Input) async throws -> Output {
        try await run(arguments)
    }
}
