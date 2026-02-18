//
//  WaitForInput.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/21.
//


/// - Note: Use `AgentSession` with `AgentTransport` instead for transport-agnostic input handling.
@available(*, deprecated, message: "Use AgentSession with AgentTransport instead")
public struct WaitForInput: Step {
    public typealias Input = String
    public typealias Output = String
    
    private let prompt: String
    
    public init(prompt: String = "Enter input: ") {
        self.prompt = prompt
    }
    
    @discardableResult
    public func run(_ input: String) async throws -> String {
        print("\n\(prompt)", terminator: "")
        guard let userInput = readLine(), !userInput.isEmpty else {
            throw WaitForInputError.emptyInput
        }
        return userInput
    }
}

public enum WaitForInputError: Error {
    case emptyInput
}
