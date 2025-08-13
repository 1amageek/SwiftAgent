# SwiftAgent

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/1amageek/SwiftAgent)

SwiftAgent is a powerful Swift framework for building AI agents using a declarative SwiftUI-like syntax. It provides a type-safe, composable way to create complex agent workflows while maintaining Swift's expressiveness.

## Architecture Overview

```mermaid
graph TB
    subgraph "Core Protocols"
        Step["Step<Input, Output>"]
        Agent["Agent: Step"]
        Model["Model: Step"]
        
        Step --> Agent
        Step --> Model
    end
    
    subgraph "OpenFoundationModels Integration"
        Tool["Tool Protocol"]
        LMS["LanguageModelSession"]
        Generable["@Generable"]
        Prompt["@PromptBuilder"]
        Instructions["@InstructionsBuilder"]
    end
    
    subgraph "Built-in Steps"
        subgraph "Transform Steps"
            Transform["Transform"]
            Map["Map"]
            Reduce["Reduce"]
            Join["Join"]
        end
        
        subgraph "Control Flow"
            Loop["Loop"]
            Parallel["Parallel"]
            Race["Race"]
            WaitForInput["WaitForInput"]
        end
        
        subgraph "AI Generation"
            Generate["Generate<T>"]
            GenerateText["GenerateText"]
        end
    end
    
    subgraph "State Management"
        Memory["@Memory"]
        Relay["Relay<T>"]
        Session["@Session"]
    end
    
    subgraph "Safety & Monitoring"
        Guardrails["Guardrails"]
        Monitor["Monitor"]
        Tracing["Distributed Tracing"]
    end
    
    subgraph "Tools"
        ReadTool["ReadTool"]
        WriteTool["WriteTool"]
        EditTool["EditTool"]
        MultiEditTool["MultiEditTool"]
        GrepTool["GrepTool"]
        GlobTool["GlobTool"]
        GitTool["GitTool"]
        ExecuteCommandTool["ExecuteCommandTool"]
        URLFetchTool["URLFetchTool"]
    end
    
    Step --> Transform
    Step --> Map
    Step --> Loop
    Step --> Parallel
    Step --> Generate
    Step --> GenerateText
    
    Agent --> Guardrails
    Step --> Monitor
    Step --> Tracing
    
    Generate --> LMS
    GenerateText --> LMS
    Session --> LMS
    
    Tool --> ReadTool
    Tool --> WriteTool
    Tool --> EditTool
    Tool --> ExecuteCommandTool
```

## Features

- 🎯 **Declarative Syntax**: Build agents using familiar SwiftUI-like syntax
- 🔄 **Composable Steps**: Chain multiple steps together seamlessly with StepBuilder
- 🛠️ **Type-Safe Tools**: Define and use tools with compile-time type checking
- 🤖 **Model-Agnostic**: Works with any AI model through OpenFoundationModels
- 📦 **Modular Design**: Create reusable agent components
- 🔄 **Async/Await Support**: Built for modern Swift concurrency
- 🎭 **Protocol-Based**: Flexible and extensible architecture
- 📊 **State Management**: Memory and Relay for state handling
- 🎨 **@Session**: Elegant session management with property wrapper
- 🏗️ **Builder APIs**: Dynamic Instructions and Prompt construction with result builders
- 🔍 **Monitoring**: Built-in monitoring and distributed tracing support
- 📡 **OpenTelemetry**: Industry-standard distributed tracing with swift-distributed-tracing
- 🛡️ **Guardrails**: Safety checks for input/output validation
- ⚙️ **Chain Support**: Chain up to 8 steps with type-safe composition

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
}
```

## Session Management

SwiftAgent provides elegant session management through the `@Session` property wrapper, enabling reusable and shared language model sessions across your agents.

### @Session Property Wrapper

The `@Session` wrapper simplifies session creation and management:

```swift
struct MyAgent {
    // Create a session with InstructionsBuilder
    @Session {
        "You are a helpful assistant"
        "Be concise and accurate"
        if debugMode {
            "Include debug information"
        }
    }
    var session
    
    // Or with explicit initialization
    @Session
    var customSession = LanguageModelSession(
        model: OpenAIModelFactory.gpt4o(apiKey: apiKey)
    ) {
        Instructions("You are an expert")
    }
}
```

### Using Sessions with Generate Steps

Pass sessions to Generate steps using the `$` prefix for Relay access:

```swift
struct ContentAgent {
    @Session {
        "You are a content creator"
        "Focus on clarity and engagement"
    }
    var session
    
    var body: some Step {
        GenerateText(session: $session) { input in
            Prompt {
                "Create content about: \(input)"
                if detailed {
                    "Include comprehensive details"
                }
            }
        }
    }
}
```

## AI Model Integration

SwiftAgent uses OpenFoundationModels for AI model integration, providing a unified interface for multiple AI providers:

### Dynamic Instructions with InstructionsBuilder

```swift
// Build instructions dynamically with conditions and loops
let session = LanguageModelSession {
    "You are an AI assistant"
    
    if userPreferences.verbose {
        "Provide detailed explanations"
    }
    
    for expertise in userExpertiseAreas {
        "You have expertise in \(expertise)"
    }
    
    "Always be helpful and accurate"
}
```

### Dynamic Prompts with PromptBuilder

```swift
// Build prompts dynamically
GenerateText(session: $session) { input in
    Prompt {
        "User request: \(input)"
        
        if includeContext {
            "Context: \(contextInfo)"
        }
        
        for example in relevantExamples {
            "Example: \(example)"
        }
        
        "Please provide a comprehensive response"
    }
}
```

### Using Model Providers

SwiftAgent works with any AI provider through OpenFoundationModels. Configure your preferred provider:

```swift
import SwiftAgent
import OpenFoundationModels
// Import your chosen provider package
// e.g., OpenFoundationModelsOpenAI, OpenFoundationModelsOllama, etc.

// Create a session with your chosen model
@Session
var session = LanguageModelSession(
    model: YourModelFactory.create(apiKey: "your-api-key")
) {
    Instructions("You are a helpful assistant.")
}
```

### Available Provider Packages

SwiftAgent is provider-agnostic. Choose from available OpenFoundationModels provider packages:

- [OpenFoundationModels-OpenAI](https://github.com/1amageek/OpenFoundationModels-OpenAI) - OpenAI models (GPT-4o, etc.)
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama) - Local models via Ollama
- [OpenFoundationModels-Anthropic](https://github.com/1amageek/OpenFoundationModels-Anthropic) - Anthropic Claude models
- Additional providers available through the OpenFoundationModels ecosystem

## Built-in Steps

### Transform

Convert data from one type to another:

```swift
Transform<String, Int> { input in
    Int(input) ?? 0
}
```

### Generate

Generate structured output using AI models with Builder APIs:

```swift
@Generable
struct Story {
    @Guide(description: "The story title")
    let title: String
    @Guide(description: "The story content")
    let content: String
}

// Using @Session and PromptBuilder
struct StoryGenerator {
    @Session {
        "You are a creative writer"
        "Focus on engaging narratives"
    }
    var session
    
    var generator: some Step {
        Generate<String, Story>(session: $session) { input in
            Prompt {
                "Write a story about: \(input)"
                "Include vivid descriptions"
                if includeDialogue {
                    "Add realistic dialogue"
                }
            }
        }
    }
}
```

### GenerateText

Generate string output using AI models with dynamic builders:

```swift
// Using @Session with shared configuration
struct TextGenerator {
    @Session {
        "You are a creative writer"
        "Use vivid and engaging language"
    }
    var session
    
    func generate(_ topic: String) -> some Step {
        GenerateText(session: $session) { input in
            Prompt {
                "Write about: \(topic)"
                "Input: \(input)"
            }
        }
    }
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

SwiftAgent includes a comprehensive suite of tools for file operations, searching, command execution, and more. See the [Tool Reference](#tool-reference) section below for detailed information about each tool.

### Quick Examples

#### File Operations
```swift
// Reading files
let readTool = ReadTool()
let content = try await readTool.call(ReadInput(path: "config.json", startLine: 1, endLine: 50))

// Writing files
let writeTool = WriteTool()
let result = try await writeTool.call(WriteInput(path: "output.txt", content: "Hello, World!"))

// Editing files
let editTool = EditTool()
let edited = try await editTool.call(EditInput(
    path: "main.swift",
    oldString: "print(\"old\")",
    newString: "print(\"new\")",
    replaceAll: "true"
))
```

#### Search Operations
```swift
// Search with grep
let grepTool = GrepTool()
let matches = try await grepTool.call(GrepInput(
    pattern: "TODO:",
    filePattern: "*.swift",
    basePath: "./src",
    ignoreCase: "false",
    contextBefore: 2,
    contextAfter: 2
))

// Find files with glob
let globTool = GlobTool()
let files = try await globTool.call(GlobInput(
    pattern: "**/*.md",
    basePath: ".",
    fileType: "file"
))
```

#### System Operations
```swift
// Execute commands
let executeTool = ExecuteCommandTool()
let output = try await executeTool.call(ExecuteCommandInput(
    command: "swift build",
    timeout: 30
))

// Git operations
let gitTool = GitTool()
let status = try await gitTool.call(GitInput(
    command: "status",
    args: "--short"
))

// Fetch URLs
let urlTool = URLFetchTool()
let webpage = try await urlTool.call(URLInput(url: "https://api.example.com/data"))
```

## Tool Reference

| Tool Name | Purpose | Main Features | Common Use Cases |
|-----------|---------|---------------|------------------|
| **ReadTool** | Read file contents with line numbers | • Line number formatting (123→content)<br>• Range selection (startLine, endLine)<br>• UTF-8 text file support<br>• Max file size: 1MB | • View source code<br>• Read configuration files<br>• Inspect specific line ranges<br>• Debug file contents |
| **WriteTool** | Write content to files | • Create new files or overwrite existing<br>• Automatic parent directory creation<br>• Atomic write operations<br>• UTF-8 encoding only | • Save generated content<br>• Create configuration files<br>• Export data<br>• Write logs or reports |
| **EditTool** | Find and replace text in files | • Single or all occurrences replacement<br>• Preview changes before applying<br>• Atomic operations<br>• Validates old/new strings | • Fix bugs in code<br>• Update configuration values<br>• Refactor variable names<br>• Correct typos |
| **MultiEditTool** | Apply multiple edits in one transaction | • Batch find/replace operations<br>• Transactional (all or nothing)<br>• Order-preserving execution<br>• JSON-based edit specification | • Complex refactoring<br>• Multiple related changes<br>• Atomic updates<br>• Code migrations |
| **GrepTool** | Search file contents using regex | • Regular expression patterns<br>• Case-insensitive option<br>• Context lines (before/after)<br>• Multi-file search | • Find TODO comments<br>• Locate function usage<br>• Search error messages<br>• Code analysis |
| **GlobTool** | Find files using glob patterns | • Wildcard patterns (*, **, ?)<br>• File type filtering<br>• Recursive directory traversal<br>• Sorted results | • Find files by extension<br>• List directory contents<br>• Discover project structure<br>• Batch file operations |
| **ExecuteCommandTool** | Execute shell commands | • Configurable timeout<br>• stdout/stderr capture<br>• Working directory support<br>• Process control | • Build projects<br>• Run tests<br>• System operations<br>• Script execution |
| **GitTool** | Perform Git operations | • All git commands supported<br>• Argument passing<br>• Repository operations<br>• Output capture | • Version control<br>• Commit changes<br>• Branch management<br>• Check status |
| **URLFetchTool** | Fetch content from URLs | • HTTP/HTTPS support<br>• Content type handling<br>• Error handling<br>• Response parsing | • API calls<br>• Web scraping<br>• Data fetching<br>• External integrations |

### Tool Integration with AI Models

All tools implement the `OpenFoundationModels.Tool` protocol and can be used with AI models:

```swift
let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
    tools: [
        ReadTool(),
        WriteTool(),
        EditTool(),
        GrepTool(),
        ExecuteCommandTool()
    ]
) {
    Instructions("You are a code assistant with file system access.")
}
```

### Tool Input/Output Types

All tools use `@Generable` structs for type-safe input and provide structured output:

```swift
// Example: ReadTool
@Generable
struct ReadInput {
    @Guide(description: "File path to read")
    let path: String
    @Guide(description: "Starting line number (1-based, 0 for beginning)")
    let startLine: Int
    @Guide(description: "Ending line number (0 for end of file)")
    let endLine: Int
}

// Output includes metadata
struct ReadOutput {
    let content: String        // Formatted with line numbers
    let totalLines: Int       // Total lines in file
    let linesRead: Int        // Lines actually read
    let path: String          // Normalized path
    let startLine: Int        // Actual start line
    let endLine: Int          // Actual end line
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
    
    @Session {
        "You are a creative writer"
        "Write compelling stories based on the user's request"
        "Include interesting characters, plot, and theme"
    }
    var session
    
    public init() {}
    
    public var body: some Step<Input, Output> {
        GenerateText(session: $session) { input in
            Prompt {
                "Request: \(input)"
                "Create an engaging narrative"
            }
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
    
    @Session
    var session: LanguageModelSession
    
    init(model: any LanguageModel) {
        self._session = Session(wrappedValue: LanguageModelSession(
            model: model,
            tools: [ReadTool(), GrepTool(), GitTool()]
        ) {
            Instructions {
                "You are a code analysis expert"
                "Analyze the codebase and provide insights"
                "Focus on code quality and best practices"
            }
        })
    }
    
    var body: some Step<Input, Output> {
        Generate<String, AnalysisResult>(session: $session) { request in
            Prompt {
                "Analyze the following: \(request)"
                "Use available tools to examine the code"
                "Provide actionable recommendations"
            }
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
    
    @Session {
        "You are a research expert"
        "Synthesize information into comprehensive reports"
        "Focus on accuracy and clarity"
    }
    var session
    
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
        Generate<[SearchResult], ResearchReport>(session: $session) { results in
            Prompt {
                "Synthesize these search results:"
                for result in results {
                    "- \(result.content)"
                }
                "Create a comprehensive report with key findings"
            }
        }
    }
    
    var guardrails: [any Guardrail] {
        [ContentSafetyGuardrail(), TokenLimitGuardrail(maxTokens: 4000)]
    }
}
```

### Interactive Chat Agent with Memory

```swift
struct ChatAgent: Agent {
    typealias Input = String
    typealias Output = String
    
    @Memory var conversationHistory: [String] = []
    
    @Session {
        "You are a helpful conversational assistant"
        "Maintain context across the conversation"
        "Be friendly and engaging"
    }
    var session
    
    var body: some Step<Input, Output> {
        Transform<String, String> { input in
            // Add to conversation history
            conversationHistory.append("User: \(input)")
            return input
        }
        
        GenerateText(session: $session) { input in
            Prompt {
                "Conversation history:"
                for message in conversationHistory.suffix(10) {
                    message
                }
                ""
                "Current message: \(input)"
                "Respond naturally and helpfully"
            }
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

### Model Provider Packages

SwiftAgent requires a model provider package from the OpenFoundationModels ecosystem. Choose based on your needs:

```swift
// For OpenAI models
.package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")

// For local models via Ollama
.package(url: "https://github.com/1amageek/OpenFoundationModels-Ollama.git", branch: "main")

// For Anthropic Claude models
.package(url: "https://github.com/1amageek/OpenFoundationModels-Anthropic.git", branch: "main")

// Additional providers available - check OpenFoundationModels documentation
```

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
        // Choose your AI provider - example with OpenAI
        .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MyAgent",
            dependencies: [
                .product(name: "SwiftAgent", package: "SwiftAgent"),
                .product(name: "AgentTools", package: "SwiftAgent"),  // Optional: for built-in tools
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
        
        // Add your chosen AI provider package
        // Example: OpenAI
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

Configure your chosen AI provider according to their documentation. For example:

```bash
# For OpenAI
export OPENAI_API_KEY="your-api-key"

# For Anthropic
export ANTHROPIC_API_KEY="your-api-key"

# For local models (Ollama)
# Install and configure Ollama according to their documentation
```

### 3. Create your first agent

```swift
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI  // Your chosen provider

struct MyAgent: Agent {
    typealias Input = String
    typealias Output = String
    
    @Session
    var session = LanguageModelSession(
        model: OpenAIModelFactory.gpt4o(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
    ) {
        Instructions {
            "You are a helpful assistant"
            "Be concise and informative"
        }
    }
    
    var body: some Step<Input, Output> {
        GenerateText(session: $session) { input in
            Prompt {
                "User request: \(input)"
                "Provide a helpful response"
            }
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

### Monitoring & Tracing

SwiftAgent provides two complementary ways to observe step execution:

#### Monitor - Lightweight Debugging

Use `Monitor` for simple debugging and logging during development:

```swift
GenerateText { input in
    "Process: \(input)"
}
.onInput { input in
    print("Starting with: \(input)")
}
.onOutput { output in
    print("Generated: \(output)")
}
.onError { error in
    print("Failed: \(error)")
}
.onComplete { duration in
    print("Took \(duration) seconds")
}
```

#### Distributed Tracing - Production Monitoring

Use `trace()` for production-grade distributed tracing with OpenTelemetry support:

```swift
GenerateText { input in
    "Process: \(input)"
}
.trace("TextGeneration", kind: .client)

// Combine monitoring and tracing
GenerateText { input in
    "Process: \(input)"
}
.onError { error in
    logger.error("Generation failed: \(error)")
}
.trace("TextGeneration")
```

#### Integration with Vapor

SwiftAgent automatically integrates with Vapor's distributed tracing:

```swift
app.post("analyze") { req async throws -> Response in
    // SwiftAgent traces will be nested under Vapor's request trace
    let agent = MyAgent()
    let result = try await agent.run(input)
    return result
}
```

The trace hierarchy will look like:
```
[Trace] Request abc-123
├─ [Span] POST /analyze (Vapor) - 2.5s
│  ├─ [Span] MyAgent - 2.3s
│  │  ├─ [Span] ContentSafetyGuardrail - 0.1s ✓
│  │  ├─ [Span] GenerateText - 2.0s
│  │  └─ [Span] OutputGuardrail - 0.2s ✓
│  └─ [Span] Response serialization - 0.2s
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