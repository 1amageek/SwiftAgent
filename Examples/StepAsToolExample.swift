//
//  StepAsToolExample.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation
import SwiftAgent
import OpenFoundationModels

// MARK: - Example Steps

/// A simple Step that can be used directly as a Tool
/// Note: This Step includes name and description properties for Tool conformance
struct UppercaseStep: Step, Tool, Sendable {
    // Tool requirements - developer's responsibility
    let name = "uppercase"
    let description = "Converts input text to uppercase format"
    
    // Step implementation
    func run(_ input: String) async throws -> String {
        input.uppercased()
    }
}

/// A Step that calculates string statistics
struct TextAnalysisStep: Step {
    struct Input: Sendable, ConvertibleFromGeneratedContent {
        let text: String
        
        init(text: String) {
            self.text = text
        }
        
        init(_ content: GeneratedContent) throws {
            guard case .text(let text) = content else {
                throw ConversionError.invalidContent("Expected text content")
            }
            self.text = text
        }
    }
    
    struct Output: Sendable, PromptRepresentable {
        let characterCount: Int
        let wordCount: Int
        let lineCount: Int
        
        var promptRepresentation: Prompt {
            Prompt("""
            Text Analysis Results:
            - Characters: \(characterCount)
            - Words: \(wordCount)
            - Lines: \(lineCount)
            """)
        }
    }
    
    func run(_ input: Input) async throws -> Output {
        let text = input.text
        let words = text.split(separator: " ").count
        let lines = text.split(separator: "\n").count
        
        return Output(
            characterCount: text.count,
            wordCount: words,
            lineCount: lines
        )
    }
}

/// A Step that reverses text - can be used directly as a Tool
struct ReverseTextStep: Step, Tool, Sendable {
    // Tool properties (developer's responsibility)
    let name = "reverse_text"
    let description = "Reverses the input text character by character"
    
    // Step implementation
    func run(_ input: String) async throws -> String {
        String(input.reversed())
    }
}

/// Legacy Step without Tool properties
struct LegacyProcessingStep: Step, Sendable {
    // This Step doesn't have name/description, so it needs StepTool wrapper
    func run(_ input: String) async throws -> String {
        input.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Example Usage

@MainActor
func demonstrateStepAsToolUsage() async throws {
    print("=== Step as Tool Examples ===\n")
    
    // Example 1: Direct Step as Tool (NEW!)
    print("1. Direct Step as Tool:")
    let uppercaseStep = UppercaseStep()
    
    // Can be used directly as a Tool
    let tools: [any Tool] = [uppercaseStep]  // No wrapper needed!
    print("Tool name: \(uppercaseStep.name)")
    print("Tool description: \(uppercaseStep.description)")
    
    // Call it as a Tool
    let result1 = try await uppercaseStep.call(arguments: "hello world")
    print("Result: \(result1)\n")
    
    // Example 2: Using asTool convenience method
    print("2. asTool Convenience Method:")
    let analysisStep = TextAnalysisStep()
    let analysisTool = analysisStep.asTool(
        name: "text_analysis",
        description: "Analyzes text and returns statistics"
    )
    
    let analysisInput = TextAnalysisStep.Input(text: "Hello\nWorld\nFrom SwiftAgent")
    let result2 = try await analysisTool.call(arguments: analysisInput)
    print("Analysis result: \(result2.promptRepresentation.text)\n")
    
    // Example 3: Another Direct Step as Tool
    print("3. Direct Step as Tool (ReverseTextStep):")
    let reverseStep = ReverseTextStep()
    
    // Can be used directly in a Tool array
    let moreTool: [any Tool] = [reverseStep]
    print("Tool: \(reverseStep.name) - \(reverseStep.description)")
    
    // Works as both Step and Tool
    let stepResult = try await reverseStep.run("SwiftAgent")
    print("As Step: \(stepResult)")
    
    let toolResult = try await reverseStep.call(arguments: "SwiftAgent")
    print("As Tool: \(toolResult)\n")
    
    // Example 4: SimpleStepTool
    print("4. SimpleStepTool:")
    let echoTool = SimpleStepTool<String, String>(
        name: "echo",
        description: "Echoes the input with a prefix"
    ) { input in
        "Echo: \(input)"
    }
    
    let echoResult = try await echoTool.run("Hello!")
    print("Echo result: \(echoResult)\n")
    
    // Example 5: Legacy Step with StepTool wrapper
    print("5. Legacy Step with StepTool Wrapper:")
    let legacyStep = LegacyProcessingStep()
    
    // Legacy Step needs wrapper since it lacks name/description
    let legacyTool = StepTool(
        name: "process_text",
        description: "Converts to lowercase and replaces spaces with underscores",
        step: legacyStep
    )
    
    let legacyResult = try await legacyTool.call(arguments: "Hello World")
    print("Legacy tool result: \(legacyResult)\n")
    
    // Example 6: Using with LanguageModelSession
    print("6. LanguageModelSession Integration:")
    print("""
    // Direct Step as Tool usage:
    let directTools: [any Tool] = [
        UppercaseStep(),      // Direct usage!
        ReverseTextStep(),    // Direct usage!
        legacyTool            // Wrapper for legacy Steps
    ]
    
    let session = LanguageModelSession(
        model: model,
        tools: directTools
    )
    """)
}

// MARK: - Helper Types

enum ConversionError: Error {
    case invalidContent(String)
}

// MARK: - Direct Tool/Step Implementation Example

/// Example of a production-ready Step that works as both Step and Tool
struct ProductionStep: Step, Tool, Sendable {
    // Tool metadata (required for Tool conformance)
    let name = "format_json"
    let description = "Formats a JSON string with proper indentation"
    
    // Step implementation
    func run(_ input: String) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let result = String(data: formatted, encoding: .utf8) else {
            throw FormatError.invalidJSON
        }
        return result
    }
    
    enum FormatError: Error {
        case invalidJSON
    }
}

// MARK: - Main Entry Point

@main
struct StepAsToolExample {
    static func main() async {
        do {
            try await demonstrateStepAsToolUsage()
            
            // Additional example: Production Step
            print("\n7. Production-Ready Step/Tool:")
            let jsonStep = ProductionStep()
            
            // Use as Tool
            let jsonTools: [any Tool] = [jsonStep]
            print("Tool registered: \(jsonStep.name)")
            
            // Format some JSON
            let uglyJSON = "{\"name\":\"SwiftAgent\",\"version\":\"1.0\"}"
            let prettyJSON = try await jsonStep.run(uglyJSON)
            print("Formatted JSON:\n\(prettyJSON)")
            
            print("\n✅ All examples completed successfully!")
        } catch {
            print("❌ Error: \(error)")
        }
    }
}