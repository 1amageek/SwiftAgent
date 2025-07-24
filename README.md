# SwiftAgent

SwiftAgent is a powerful Swift framework for building AI agents using a declarative SwiftUI-like syntax. It provides a type-safe, composable way to create complex agent workflows while maintaining Swift's expressiveness.

## Architecture Overview

```mermaid
graph TB
    subgraph "Core Protocols"
        Step["Step<Input, Output>"]
        Agent["Agent: Step"]
        
        Step --> Agent
    end
    
    subgraph "OpenFoundationModels Integration"
        Tool["Tool Protocol"]
        LMS["LanguageModelSession"]
        Generable["@Generable"]
    end
    
    subgraph "Built-in Steps"
        subgraph "Transform"
            Transform["Transform"]
            Map["Map"]
            Reduce["Reduce"]
            Join["Join"]
        end
        
        subgraph "Control Flow"
            Loop["Loop"]
            Parallel["Parallel"]
            Race["Race"]
        end
        
        subgraph "AI Generation"
            Generate["Generate<T>"]
            GenerateText["GenerateText"]
        end
    end
    
    subgraph "Safety & Monitoring"
        Guardrails["Guardrails"]
        Tracer["AgentTracer"]
    end
    
    subgraph "Tools"
        FST["FileSystemTool"]
        GT["GitTool"]
        ECT["ExecuteCommandTool"]
        UFT["URLFetchTool"]
    end
    
    Step --> Transform
    Step --> Map
    Step --> Loop
    Step --> Parallel
    Step --> Generate
    Step --> GenerateText
    
    Agent --> Guardrails
    Agent --> Tracer
    
    Generate --> LMS
    GenerateText --> LMS
    
    Tool --> FST
    Tool --> GT
    Tool --> ECT
    Tool --> UFT
```

## Features

- 🎯 **Declarative Syntax**: Build agents using familiar SwiftUI-like syntax
- 🔄 **Composable Steps**: Chain multiple steps together seamlessly
- 🛠️ **Type-Safe Tools**: Define and use tools with compile-time type checking
- 🤖 **Model-Agnostic**: Works with any AI model through OpenFoundationModels
- 📦 **Modular Design**: Create reusable agent components
- 🔄 **Async/Await Support**: Built for modern Swift concurrency
- 🎭 **Protocol-Based**: Flexible and extensible architecture
- 📊 **State Management**: Memory and Relay for state handling
- 🔍 **Monitoring**: Built-in tracing and guardrails support

## Core Components

### Steps

Steps are the fundamental building blocks in SwiftAgent. They process input and produce output in a type-safe manner:

```swift
public protocol Step<Input, Output> {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    
    func run(_ input: Input) async throws -> Output
}
```

### Agents

Agents are high-level abstractions that combine steps to create complex workflows:

```swift
public protocol Agent: Step {
    associatedtype Body: Step
    
    @StepBuilder var body: Self.Body { get }
    var maxTurns: Int { get }
    var guardrails: [any Guardrail] { get }
    var tracer: AgentTracer? { get }
}
```

## AI Model Integration

SwiftAgent uses OpenFoundationModels for AI model integration, supporting any model provider:

### Using Different Model Providers

```swift
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

// Create a session with OpenAI
let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(apiKey: "your-api-key"),
    instructions: Instructions("You are a helpful assistant.")
)

// Use in a Generate step
let step = Generate<String, Story>(session: session) { input in
    input
}
```

### Supported Providers

Currently supported:
- **OpenAI** (GPT-4o, GPT-4o Mini, o1, o3) - ✅ Available now

Coming soon through OpenFoundationModels:
- **Anthropic** (Claude 3 Opus, Sonnet, Haiku) - 🚧 In development
- **Google** (Gemini Pro, Flash) - 🚧 In development
- **Ollama** (Local models) - 🚧 In development
- **Apple's Foundation Models** (via SystemLanguageModel) - 🚧 In development

## Built-in Steps

### Transform

Convert data from one type to another:

```swift
Transform<String, Int> { input in
    Int(input) ?? 0
}
```

### Generate

Generate structured output using AI models:

```swift
@Generable
struct Story {
    @Guide(description: "The story title")
    let title: String
    @Guide(description: "The story content")
    let content: String
}

Generate<String, Story>(
    session: session
) { input in
    "Write a story about: \(input)"
}
```

### GenerateText

Generate string output using AI models:

```swift
GenerateText<String>(
    instructions: "You are a creative writer."
) { input in
    input
}
```

### Loop

Iterate with a condition:

```swift
Loop(max: 5) { input in
    ProcessingStep()
} until: { output in
    output.meetsQualityCriteria
}
```

### Map

Process collections:

```swift
Map<[String], [Int]> { item, index in
    Transform { str in
        str.count
    }
}
```

### Parallel

Execute steps concurrently:

```swift
Parallel<String, Int> {
    CountWordsStep()
    CountCharactersStep()
    CountLinesStep()
}
```

## Built-in Tools

SwiftAgent includes several pre-built tools:

### FileSystemTool

Read and write files:

```swift
@Generable
struct FileSystemInput {
    @Guide(description: "Operation: 'read' or 'write'")
    let operation: String
    @Guide(description: "File path")
    let path: String
    @Guide(description: "Content to write (for write operation)")
    let content: String?
}
```

### ExecuteCommandTool

Execute shell commands:

```swift
@Generable
struct ExecuteCommandInput {
    @Guide(description: "Command to execute")
    let command: String
    @Guide(description: "Optional timeout in seconds")
    let timeout: Int?
}
```

### URLFetchTool

Fetch content from URLs:

```swift
@Generable
struct URLInput {
    @Guide(description: "URL to fetch")
    let url: String
}
```

### GitTool

Git operations:

```swift
@Generable
struct GitInput {
    @Guide(description: "Git command")
    let command: String
    @Guide(description: "Additional arguments")
    let args: String?
}
```

## Examples

### Simple Writer Agent

```swift
import SwiftAgent
import OpenFoundationModels

public struct Writer: Agent {
    public typealias Input = String
    public typealias Output = String
    
    public init() {}
    
    public var body: some Step<Input, Output> {
        GenerateText<String>(
            instructions: """
                You are a creative writer. 
                Write a compelling story based on the user's request.
                Include interesting characters, plot, and theme.
                """
        ) { input in
            input
        }
    }
}

// Usage
let writer = Writer()
let story = try await writer.run("Write a story about a time-traveling scientist")
```

### Code Analysis Agent with Tools

```swift
import SwiftAgent
import OpenFoundationModels
import AgentTools

struct CodeAnalyzer: Agent {
    typealias Input = String
    typealias Output = AnalysisResult
    
    let session: LanguageModelSession
    
    init(apiKey: String) {
        self.session = LanguageModelSession(
            model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
            tools: [FileSystemTool(), GitTool()],
            instructions: Instructions("""
                You are a code analysis expert.
                Analyze the codebase and provide insights.
                """)
        )
    }
    
    var body: some Step<Input, Output> {
        Generate<String, AnalysisResult>(
            session: session
        ) { request in
            "Analyze the following: \(request)"
        }
    }
}

@Generable
struct AnalysisResult {
    @Guide(description: "Summary of findings")
    let summary: String
    
    @Guide(description: "List of issues found")
    let issues: String  // Space-separated list
    
    @Guide(description: "Recommendations")
    let recommendations: String
}
```

### Multi-Step Research Agent

```swift
struct ResearchAgent: Agent {
    typealias Input = String
    typealias Output = ResearchReport
    
    let session: LanguageModelSession
    
    var body: some Step<Input, Output> {
        // Step 1: Generate search queries
        Transform<String, SearchQueries> { topic in
            SearchQueries(topic: topic)
        }
        
        // Step 2: Search in parallel
        Map<SearchQueries, [SearchResult]> { query, _ in
            URLFetchTool().call(URLInput(url: query.url))
                .map { SearchResult(content: $0) }
        }
        
        // Step 3: Analyze results
        Generate<[SearchResult], ResearchReport>(
            session: session
        ) { results in
            "Synthesize these search results into a comprehensive report: \(results)"
        }
    }
    
    var guardrails: [any Guardrail] {
        [ContentSafetyGuardrail(), TokenLimitGuardrail(maxTokens: 4000)]
    }
    
    var tracer: AgentTracer? {
        ConsoleTracer()
    }
}
```

### Interactive Chat Agent with Memory

```swift
struct ChatAgent: Agent {
    typealias Input = String
    typealias Output = String
    
    @Memory var conversationHistory: [String] = []
    let session: LanguageModelSession
    
    var body: some Step<Input, Output> {
        Transform<String, String> { input in
            // Add to conversation history
            conversationHistory.append("User: \(input)")
            
            // Include context in prompt
            let context = conversationHistory.suffix(10).joined(separator: "\n")
            return """
                Conversation history:
                \(context)
                
                Current message: \(input)
                """
        }
        
        GenerateText<String>(
            session: session
        ) { contextualInput in
            contextualInput
        }
        
        Transform<String, String> { response in
            // Save assistant response
            conversationHistory.append("Assistant: \(response)")
            return response
        }
    }
}
```

## Requirements

- Swift 6.0+
- iOS 18.0+ / macOS 15.0+
- Xcode 15.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main")
]
```

### Available Model Providers

Currently available:

```swift
// OpenAI (GPT-4o, GPT-4o Mini, o1, o3)
.package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
```

Coming soon:
- Anthropic (Claude 3 Opus, Sonnet, Haiku)
- Google (Gemini Pro, Flash)
- Ollama (Local models)
- Apple's Foundation Models

### Quick Start Example

```swift
// Complete Package.swift example
import PackageDescription

let package = Package(
    name: "MyAgentProject",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .executable(name: "MyAgent", targets: ["MyAgent"])
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MyAgent",
            dependencies: [
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),
                .product(name: "OpenFoundationModelsOpenAI", package: "OpenFoundationModels-OpenAI")
            ]
        )
    ]
)
```

## Getting Started

### 1. Add SwiftAgent to your Package.swift

```swift
import PackageDescription

let package = Package(
    name: "MyAgentApp",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        // Core SwiftAgent framework
        .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
        
        // Choose your AI provider (example with OpenAI)
        .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
    ],
    targets: [
        .target(
            name: "MyAgentApp",
            dependencies: [
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),  // Optional: for built-in tools
                .product(name: "OpenFoundationModelsOpenAI", package: "OpenFoundationModels-OpenAI")
            ]
        )
    ]
)
```

### 2. Set up your environment

```bash
# For OpenAI
export OPENAI_API_KEY="your-api-key"

# For Anthropic
export ANTHROPIC_API_KEY="your-api-key"
```

### 3. Create your first agent

```swift
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

struct MyAgent: Agent {
    typealias Input = String
    typealias Output = String
    
    let session = LanguageModelSession(
        model: OpenAIModelFactory.gpt4o(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!),
        instructions: Instructions("You are a helpful assistant.")
    )
    
    var body: some Step<Input, Output> {
        GenerateText<String>(
            session: session
        ) { input in
            input
        }
    }
}
```

### 4. Run your agent

```swift
@main
struct MyApp {
    static func main() async throws {
        let agent = MyAgent()
        let result = try await agent.run("Hello, world!")
        print(result)
    }
}
```

## Advanced Features

### Guardrails

Add safety checks to your agents:

```swift
struct ContentGuardrail: Guardrail {
    func validate(_ content: String) throws {
        if content.contains("inappropriate") {
            throw GuardrailError.contentViolation
        }
    }
}

struct MyAgent: Agent {
    var guardrails: [any Guardrail] {
        [ContentGuardrail()]
    }
    
    var body: some Step<String, String> {
        // Agent implementation
    }
}
```

### Tracing

Monitor agent execution:

```swift
struct MyAgent: Agent {
    var tracer: AgentTracer? {
        ConsoleTracer()
    }
    
    var body: some Step<String, String> {
        // Agent implementation
    }
}
```

### Memory

Maintain state across agent runs:

```swift
struct StatefulAgent: Agent {
    @Memory var conversationHistory: [String] = []
    
    var body: some Step<String, String> {
        Transform { input in
            conversationHistory.append(input)
            return conversationHistory.joined(separator: "\n")
        }
    }
}
```

## License

SwiftAgent is available under the MIT license.

## Author

@1amageek