//
//  Join.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation


/// A step that joins strings together
///
/// Use `Join` when you need to concatenate strings with a specified separator.
///
/// Example:
/// ```swift
/// struct TextProcessor: Agent {
///     var body: some Step<String, String> {
///         Join(separator: " ")
///     }
/// }
/// ```
public struct Join: Step {
    
    public typealias Input = [String]
    public typealias Output = String
    
    /// The separator to use between joined strings
    private let separator: String
    
    /// Creates a new join step with the specified separator
    ///
    /// - Parameter separator: The string to use between joined elements
    public init(separator: String = "") {
        self.separator = separator
    }
    
    /// Executes the join step on the input string
    ///
    /// - Parameter input: The string to process
    /// - Returns: The joined string
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        input.joined(separator: separator)
    }
}


