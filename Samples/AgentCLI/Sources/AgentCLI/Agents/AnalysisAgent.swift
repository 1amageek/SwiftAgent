//
//  AnalysisAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

/// An analysis agent that provides structured output for analytical tasks
public struct AnalysisAgent: Agent {
    let configuration: AgentConfiguration
    
    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }
    
    public var body: some Step<String, String> {
        StringModelStep<String>(
            session: createLanguageModelSession(),
            transform: { input in
                """
                Analyze the following topic thoroughly and provide structured insights.
                
                Format your response as follows:
                ## Analysis Summary
                [Provide a comprehensive summary of the analyzed topic]
                
                ## Key Insights
                [List 3-5 key insights or findings, numbered]
                
                ## Recommendations
                [Provide actionable recommendations based on the analysis]
                
                ## Confidence Level
                [State your confidence level as a percentage (e.g., 85%)]
                
                Topic to analyze: \(input)
                """
            }
        )
    }
    
    private func createLanguageModelSession() -> LanguageModelSession {
        return LanguageModelSession(
            model: createModel(),
            guardrails: .default,
            tools: [],
            instructions: Instructions("""
            You are an analytical AI assistant that provides structured analysis of topics, problems, or data.
            Your analysis should be thorough, evidence-based, and actionable.
            Always include a confidence level based on the available information.
            """)
        )
    }
    
    private func createModel() -> any LanguageModel {
        switch configuration.model.lowercased() {
        case "gpt-4o":
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        case "o1-preview":
            return OpenAIModelFactory.o3(apiKey: configuration.apiKey)
        case "o1-mini":
            return OpenAIModelFactory.o4Mini(apiKey: configuration.apiKey)
        case "gpt-3.5-turbo":
            return OpenAIModelFactory.gpt4oMini(apiKey: configuration.apiKey)
        default:
            if configuration.verbose {
                print("Unknown model '\(configuration.model)', falling back to gpt-4o")
            }
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        }
    }
}