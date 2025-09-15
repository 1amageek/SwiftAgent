//
//  Guardrails.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/17.
//

import Foundation

// MARK: - Guardrail Protocol

/// A protocol that defines a guardrail for validating inputs or outputs in agent workflows.
///
/// Guardrails provide safety and validation mechanisms that run in parallel with agent execution,
/// enabling early detection of problematic inputs or outputs.
public protocol Guardrail: Sendable {
    /// The type of data this guardrail can validate
    associatedtype Input: Sendable
    
    /// Validates the input and returns the result
    /// - Parameter input: The data to validate
    /// - Returns: The validation result
    func check(_ input: Input) async throws -> GuardrailResult
}

// MARK: - Guardrail Result

/// The result of a guardrail validation
public enum GuardrailResult: Sendable {
    /// The validation passed
    case passed
    
    /// The validation failed with a specific reason
    case failed(reason: String)
    
    /// The validation passed but with a warning
    case warning(message: String)
    
    /// Whether this result indicates a failure
    public var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
    
    /// Whether this result indicates a warning
    public var isWarning: Bool {
        if case .warning = self {
            return true
        }
        return false
    }
}

// MARK: - Guardrail Errors

/// Errors that can occur during guardrail validation
public enum GuardrailError: Error, LocalizedError {
    /// Input validation failed
    case inputViolation(String)
    
    /// Output validation failed
    case outputViolation(String)
    
    /// Multiple guardrails failed
    case multipleViolations([String])
    
    public var errorDescription: String? {
        switch self {
        case .inputViolation(let reason):
            return "Input guardrail violation: \(reason)"
        case .outputViolation(let reason):
            return "Output guardrail violation: \(reason)"
        case .multipleViolations(let reasons):
            return "Multiple guardrail violations: \(reasons.joined(separator: ", "))"
        }
    }
}

// MARK: - Guardrail Step Wrapper

/// A step wrapper that applies guardrails to input and output validation
public struct GuardrailStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output
    
    private let step: S
    private let inputGuardrails: [any Guardrail]
    private let outputGuardrails: [any Guardrail]
    
    /// Creates a new guardrail step wrapper
    /// - Parameters:
    ///   - step: The step to wrap
    ///   - inputGuardrails: Guardrails to apply to input validation
    ///   - outputGuardrails: Guardrails to apply to output validation
    public init(
        step: S,
        inputGuardrails: [any Guardrail] = [],
        outputGuardrails: [any Guardrail] = []
    ) {
        self.step = step
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        // Check input guardrails
        var inputFailures: [String] = []
        for guardrail in inputGuardrails {
            if let stringInput = input as? String {
                // Try to cast to ContentSafetyGuardrail
                if let contentGuardrail = guardrail as? ContentSafetyGuardrail {
                    let result = try await contentGuardrail.check(stringInput)
                    if case .failed(let reason) = result {
                        inputFailures.append(reason)
                    }
                }
                // Try to cast to TokenLimitGuardrail
                else if let tokenGuardrail = guardrail as? TokenLimitGuardrail {
                    let result = try await tokenGuardrail.check(stringInput)
                    if case .failed(let reason) = result {
                        inputFailures.append(reason)
                    }
                }
                // Try to cast to SensitiveDataGuardrail
                else if let sensitiveGuardrail = guardrail as? SensitiveDataGuardrail {
                    let result = try await sensitiveGuardrail.check(stringInput)
                    if case .failed(let reason) = result {
                        inputFailures.append(reason)
                    }
                }
            }
        }
        
        if !inputFailures.isEmpty {
            if inputFailures.count == 1 {
                throw GuardrailError.inputViolation(inputFailures[0])
            } else {
                throw GuardrailError.multipleViolations(inputFailures)
            }
        }
        
        // Execute the wrapped step
        let output = try await step.run(input)
        
        // Check output guardrails
        var outputFailures: [String] = []
        for guardrail in outputGuardrails {
            if let stringOutput = output as? String {
                // Try to cast to ContentSafetyGuardrail
                if let contentGuardrail = guardrail as? ContentSafetyGuardrail {
                    let result = try await contentGuardrail.check(stringOutput)
                    if case .failed(let reason) = result {
                        outputFailures.append(reason)
                    }
                }
                // Try to cast to TokenLimitGuardrail
                else if let tokenGuardrail = guardrail as? TokenLimitGuardrail {
                    let result = try await tokenGuardrail.check(stringOutput)
                    if case .failed(let reason) = result {
                        outputFailures.append(reason)
                    }
                }
                // Try to cast to SensitiveDataGuardrail
                else if let sensitiveGuardrail = guardrail as? SensitiveDataGuardrail {
                    let result = try await sensitiveGuardrail.check(stringOutput)
                    if case .failed(let reason) = result {
                        outputFailures.append(reason)
                    }
                }
            }
        }
        
        if !outputFailures.isEmpty {
            if outputFailures.count == 1 {
                throw GuardrailError.outputViolation(outputFailures[0])
            } else {
                throw GuardrailError.multipleViolations(outputFailures)
            }
        }
        
        return output
    }
}

// MARK: - Built-in Guardrails

/// A guardrail that checks for content safety by looking for prohibited keywords
public struct ContentSafetyGuardrail: Guardrail {
    public typealias Input = String
    
    private let prohibitedKeywords: Set<String>
    private let caseSensitive: Bool
    
    /// Creates a content safety guardrail
    /// - Parameters:
    ///   - prohibitedKeywords: Keywords that are not allowed
    ///   - caseSensitive: Whether the check should be case sensitive
    public init(prohibitedKeywords: Set<String> = Self.defaultProhibitedKeywords, caseSensitive: Bool = false) {
        self.prohibitedKeywords = caseSensitive ? prohibitedKeywords : Set(prohibitedKeywords.map { $0.lowercased() })
        self.caseSensitive = caseSensitive
    }
    
    public func check(_ input: String) async throws -> GuardrailResult {
        let checkText = caseSensitive ? input : input.lowercased()
        
        for keyword in prohibitedKeywords {
            if checkText.contains(keyword) {
                return .failed(reason: "Content contains prohibited keyword: \(keyword)")
            }
        }
        
        return .passed
    }
    
    public static let defaultProhibitedKeywords: Set<String> = [
        "hate", "violence", "discrimination", "harassment"
    ]
}

/// A guardrail that checks token/character limits
public struct TokenLimitGuardrail: Guardrail {
    public typealias Input = String
    
    private let maxTokens: Int
    private let estimateTokensPerCharacter: Double
    
    /// Creates a token limit guardrail
    /// - Parameters:
    ///   - maxTokens: Maximum number of tokens allowed
    ///   - estimateTokensPerCharacter: Rough estimate of tokens per character (default: 0.25)
    public init(maxTokens: Int, estimateTokensPerCharacter: Double = 0.25) {
        self.maxTokens = maxTokens
        self.estimateTokensPerCharacter = estimateTokensPerCharacter
    }
    
    public func check(_ input: String) async throws -> GuardrailResult {
        let estimatedTokens = Int(Double(input.count) * estimateTokensPerCharacter)
        
        if estimatedTokens > maxTokens {
            return .failed(reason: "Content exceeds token limit: \(estimatedTokens) > \(maxTokens)")
        } else if estimatedTokens > Int(Double(maxTokens) * 0.8) {
            return .warning(message: "Content approaching token limit: \(estimatedTokens)/\(maxTokens)")
        }
        
        return .passed
    }
}

/// A guardrail that checks for sensitive data patterns
public struct SensitiveDataGuardrail: Guardrail {
    public typealias Input = String
    
    private let patterns: [NSRegularExpression]
    
    /// Creates a sensitive data guardrail
    /// - Parameter customPatterns: Additional regex patterns to check for
    public init(customPatterns: [String] = []) {
        let allPatterns = Self.defaultPatterns + customPatterns
        self.patterns = allPatterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }
    
    public func check(_ input: String) async throws -> GuardrailResult {
        let range = NSRange(location: 0, length: input.utf16.count)
        
        for pattern in patterns {
            if pattern.firstMatch(in: input, options: [], range: range) != nil {
                return .failed(reason: "Content contains sensitive data pattern")
            }
        }
        
        return .passed
    }
    
    private static let defaultPatterns: [String] = [
        // Credit card numbers (basic pattern)
        "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b",
        // SSN pattern
        "\\b\\d{3}-\\d{2}-\\d{4}\\b",
        // Email addresses
        "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b"
    ]
}

// MARK: - Step Extensions

public extension Step {
    /// Applies guardrails to this step
    /// - Parameters:
    ///   - inputGuardrails: Guardrails to apply to input validation
    ///   - outputGuardrails: Guardrails to apply to output validation
    /// - Returns: A new step with guardrails applied
    func withGuardrails(
        input inputGuardrails: [any Guardrail] = [],
        output outputGuardrails: [any Guardrail] = []
    ) -> GuardrailStep<Self> {
        GuardrailStep(
            step: self,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails
        )
    }
}