//
//  MessageTransform.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A transform that converts SwiftAgent types to OpenFoundationModels types
public struct ModelInputTransform<Input: Sendable, Output: Sendable>: Step {
    
    public typealias Input = Input
    public typealias Output = Output
    
    private let transform: (Input) -> Output
    
    /// Creates a new ModelInputTransform
    /// - Parameter transform: A closure to transform the input
    public init(transform: @escaping (Input) -> Output) {
        self.transform = transform
    }
    
    public func run(_ input: Input) async throws -> Output {
        return transform(input)
    }
}

/// A transform that converts OpenFoundationModels responses to SwiftAgent types
public struct ModelOutputTransform<Input: Sendable, Output: Sendable>: Step {
    
    public typealias Input = Input
    public typealias Output = Output
    
    private let transform: (Input) -> Output
    
    /// Creates a new ModelOutputTransform
    /// - Parameter transform: A closure to transform the output
    public init(transform: @escaping (Input) -> Output) {
        self.transform = transform
    }
    
    public func run(_ input: Input) async throws -> Output {
        return transform(input)
    }
}

/// A transform that converts SwiftAgent messages to OpenFoundationModels format
public struct MessageToModelTransform: Step {
    
    public typealias Input = [ChatMessage]
    public typealias Output = String
    
    public init() {}
    
    public func run(_ input: Input) async throws -> Output {
        return input.map { message in
            let role = message.role.rawValue
            let content = message.content.compactMap { content in
                switch content {
                case .text(let text):
                    return text
                case .image:
                    return "[Image]"
                }
            }.joined(separator: " ")
            return "\(role): \(content)"
        }.joined(separator: "\n")
    }
}

/// A transform that converts string responses to ChatMessage format
public struct ModelToMessageTransform: Step {
    
    public typealias Input = String
    public typealias Output = [ChatMessage]
    
    private let role: ChatMessage.Role
    
    /// Creates a new ModelToMessageTransform
    /// - Parameter role: The role for the generated message
    public init(role: ChatMessage.Role = .assistant) {
        self.role = role
    }
    
    public func run(_ input: Input) async throws -> Output {
        return [ChatMessage(role: role, content: [.text(input)])]
    }
}


/// A transform that converts structured data to Generable format
public struct GenerableTransform<T: Codable & Sendable>: Step {
    
    public typealias Input = T
    public typealias Output = String
    
    public init() {}
    
    public func run(_ input: Input) async throws -> Output {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(input)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// A transform that parses JSON string to structured data
public struct JSONParseTransform<T: Codable & Sendable>: Step {
    
    public typealias Input = String
    public typealias Output = T
    
    public init() {}
    
    public func run(_ input: Input) async throws -> Output {
        guard let data = input.data(using: .utf8) else {
            throw ModelError.invalidInput("Cannot convert string to data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

// String already conforms to Generable in OpenFoundationModels

/// A convenience structure for basic text generation
@Generable
public struct TextGenerable {
    @Guide(description: "The generated text content")
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

/// ChatMessage structure for compatibility
public struct ChatMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }
    
    public enum Content: Codable, Sendable {
        case text(String)
        case image(Data)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let imageData = try? container.decode(Data.self) {
                self = .image(imageData)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode Content"
                )
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .image(let data):
                try container.encode(data)
            }
        }
    }
    
    public let role: Role
    public let content: [Content]
    
    public init(role: Role, content: [Content]) {
        self.role = role
        self.content = content
    }
}