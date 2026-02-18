//
//  SwiftAgentSpanAttributes.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation

/// OpenTelemetry-compliant span attributes for SwiftAgent
public enum SwiftAgentSpanAttributes {
    // MARK: - Agent Attributes
    /// The type of agent being executed
    public static let agentType = "swiftagent.agent.type"
    
    /// The version of the agent
    public static let agentVersion = "swiftagent.agent.version"
    
    /// The maximum number of turns allowed for the agent
    public static let agentMaxTurns = "swiftagent.agent.max_turns"
    
    // MARK: - Step Attributes
    /// The type of step being executed
    public static let stepType = "swiftagent.step.type"
    
    /// The index of the step in a sequence
    public static let stepIndex = "swiftagent.step.index"
    
    /// The total number of steps in a sequence
    public static let stepCount = "swiftagent.step.count"
    
    // MARK: - LLM/AI Model Attributes
    /// The provider of the language model (e.g., "openai", "anthropic")
    public static let modelProvider = "llm.provider"
    
    /// The name/ID of the model (e.g., "gpt-4o", "llama-3")
    public static let modelName = "llm.model"
    
    /// The number of tokens in the prompt
    public static let promptTokens = "llm.usage.prompt_tokens"
    
    /// The number of tokens in the completion
    public static let completionTokens = "llm.usage.completion_tokens"
    
    /// The total number of tokens used
    public static let totalTokens = "llm.usage.total_tokens"
    
    /// The temperature parameter used for generation
    public static let temperature = "llm.temperature"
    
    /// The maximum tokens parameter
    public static let maxTokens = "llm.max_tokens"
    
    // MARK: - Tool Attributes
    /// The name of the tool being executed
    public static let toolName = "swiftagent.tool.name"
    
    /// Whether the tool execution was successful
    public static let toolSuccess = "swiftagent.tool.success"
    
    /// The type of operation performed by the tool
    public static let toolOperation = "swiftagent.tool.operation"

    // MARK: - Input/Output Attributes
    /// The type of input data
    public static let inputType = "swiftagent.input.type"
    
    /// The size of input data (if applicable)
    public static let inputSize = "swiftagent.input.size"
    
    /// The type of output data
    public static let outputType = "swiftagent.output.type"
    
    /// The size of output data (if applicable)
    public static let outputSize = "swiftagent.output.size"
    
    // MARK: - Error Attributes
    /// The type of error that occurred
    public static let errorType = "swiftagent.error.type"
    
    /// Whether this was a retry attempt
    public static let retryAttempt = "swiftagent.retry.attempt"
    
    /// The maximum number of retries allowed
    public static let retryMax = "swiftagent.retry.max"
}