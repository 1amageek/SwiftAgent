//
//  Monitor.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation



/// A step that monitors input and output of a wrapped step
public struct Monitor<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output
    
    private let step: S
    private let onInput: ((Input) async -> Void)?
    private let onOutput: ((Output) async -> Void)?
    private let onError: ((Error) async -> Void)?
    private let onComplete: ((TimeInterval) async -> Void)?
    
    internal init(
        step: S,
        onInput: ((Input) async -> Void)? = nil,
        onOutput: ((Output) async -> Void)? = nil,
        onError: ((Error) async -> Void)? = nil,
        onComplete: ((TimeInterval) async -> Void)? = nil
    ) {
        self.step = step
        self.onInput = onInput
        self.onOutput = onOutput
        self.onError = onError
        self.onComplete = onComplete
    }
    
    public func run(_ input: Input) async throws -> Output {
        let startTime = Date()
        
        // Monitor input
        await onInput?(input)
        
        do {
            // Run the wrapped step
            let output = try await step.run(input)
            
            // Monitor output
            await onOutput?(output)
            
            // Monitor completion with duration
            let duration = Date().timeIntervalSince(startTime)
            await onComplete?(duration)
            
            return output
        } catch {
            // Monitor error
            await onError?(error)
            
            // Still call onComplete even on error
            let duration = Date().timeIntervalSince(startTime)
            await onComplete?(duration)
            
            throw error
        }
    }
}

// Extension for modifier-style usage
extension Step {
    /// Adds a monitor for the input of this step
    /// - Parameter handler: A closure that receives the input
    /// - Returns: A Monitor wrapping this step
    public func onInput(_ handler: @escaping (Input) async -> Void) -> Monitor<Self> {
        Monitor<Self>(step: self, onInput: handler)
    }
    
    /// Adds a monitor for the output of this step
    /// - Parameter handler: A closure that receives the output
    /// - Returns: A Monitor wrapping this step
    public func onOutput(_ handler: @escaping (Output) async -> Void) -> Monitor<Self> {
        Monitor<Self>(step: self, onOutput: handler)
    }
    
    /// Adds a monitor for errors of this step
    /// - Parameter handler: A closure that receives the error
    /// - Returns: A Monitor wrapping this step
    public func onError(_ handler: @escaping (Error) async -> Void) -> Monitor<Self> {
        Monitor<Self>(step: self, onError: handler)
    }
    
    /// Adds a monitor for completion of this step
    /// - Parameter handler: A closure that receives the execution duration
    /// - Returns: A Monitor wrapping this step
    public func onComplete(_ handler: @escaping (TimeInterval) async -> Void) -> Monitor<Self> {
        Monitor<Self>(step: self, onComplete: handler)
    }
    
    /// Adds monitors for both input and output of this step
    /// - Parameters:
    ///   - inputHandler: A closure that receives the input
    ///   - outputHandler: A closure that receives the output
    /// - Returns: A Monitor wrapping this step
    public func monitor(
        input inputHandler: @escaping (Input) async -> Void,
        output outputHandler: @escaping (Output) async -> Void
    ) -> Monitor<Self> {
        Monitor<Self>(step: self, onInput: inputHandler, onOutput: outputHandler)
    }
    
    /// Adds comprehensive monitoring for this step
    /// - Parameters:
    ///   - onInput: A closure that receives the input
    ///   - onOutput: A closure that receives the output
    ///   - onError: A closure that receives any error
    ///   - onComplete: A closure that receives the execution duration
    /// - Returns: A Monitor wrapping this step
    public func monitor(
        onInput: ((Input) async -> Void)? = nil,
        onOutput: ((Output) async -> Void)? = nil,
        onError: ((Error) async -> Void)? = nil,
        onComplete: ((TimeInterval) async -> Void)? = nil
    ) -> Monitor<Self> {
        Monitor<Self>(
            step: self,
            onInput: onInput,
            onOutput: onOutput,
            onError: onError,
            onComplete: onComplete
        )
    }
}
