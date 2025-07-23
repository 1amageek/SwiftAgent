# SwiftAgent

SwiftAgent is a powerful Swift framework for building AI agents using a declarative SwiftUI-like syntax. It provides a type-safe, composable way to create complex agent workflows while maintaining Swift's expressiveness.

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

// Use in a ModelStep
let step = ModelStep<String, Story>(session: session) { input in
    input
}
```

### Supported Providers

Through OpenFoundationModels, SwiftAgent supports:
- OpenAI (GPT-4o, GPT-4o Mini, o1, o3)
- Anthropic (Claude 3 Opus, Sonnet, Haiku)
- Google (Gemini Pro, Flash)
- Ollama (Local models)
- Apple's Foundation Models (via SystemLanguageModel)

## Built-in Steps

### Transform

Convert data from one type to another:

```swift
Transform<String, Int> { input in
    Int(input) ?? 0
}
```

### ModelStep

Generate structured output using AI models:

```swift
@Generable
struct Story {
    @Guide(description: "The story title")
    let title: String
    @Guide(description: "The story content")
    let content: String
}

ModelStep<String, Story>(
    session: session
) { input in
    "Write a story about: \(input)"
}
```

### StringModelStep

Generate string output using AI models:

```swift
StringModelStep<String>(
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

## Example: Simple Writer Agent

```swift
import SwiftAgent
import OpenFoundationModels

public struct Writer: Agent {
    public typealias Input = String
    public typealias Output = String
    
    public init() {}
    
    public var body: some Step<Input, Output> {
        StringModelStep<String>(
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

### Adding Model Providers

To use specific AI models, add the corresponding OpenFoundationModels provider:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
    .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
]
```

## Getting Started

1. **Add SwiftAgent to your project** using Swift Package Manager

2. **Choose a model provider** and add its dependency

3. **Create your first agent**:

```swift
import SwiftAgent
import OpenFoundationModels

struct MyAgent: Agent {
    var body: some Step<String, String> {
        StringModelStep<String>(
            instructions: "You are a helpful assistant."
        ) { input in
            input
        }
    }
}
```

4. **Run your agent**:

```swift
let agent = MyAgent()
let result = try await agent.run("Hello, world!")
print(result)
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