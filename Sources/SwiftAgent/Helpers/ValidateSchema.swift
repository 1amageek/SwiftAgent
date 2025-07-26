//
//  ValidateSchema.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A step that validates generated content against a schema
public struct ValidateSchema<T: Codable & Sendable>: Step {
    
    public typealias Input = String
    public typealias Output = T
    
    /// Creates a new ValidateSchema
    /// - Parameter type: The expected output type
    public init(type: T.Type) {
        // Empty init as we don't need schema anymore
    }
    
    public func run(_ input: Input) async throws -> Output {
        guard let data = input.data(using: .utf8) else {
            throw ModelError.invalidInput("Cannot convert input to data")
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ModelError.generationFailed("Failed to decode structured data: \(error.localizedDescription)")
        }
    }
}