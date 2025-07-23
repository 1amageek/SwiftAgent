# SwiftAgent

SwiftAgent is a powerful Swift framework for building AI agents using a declarative SwiftUI-like syntax. It provides a type-safe, composable way to create complex agent workflows while maintaining Swift's expressiveness.

## Features

- 🎯 **Declarative Syntax**: Build agents using familiar SwiftUI-like syntax
- 🔄 **Composable Steps**: Chain multiple steps together seamlessly
- 🛠️ **Type-Safe Tools**: Define and use tools with compile-time type checking
- 🤖 **LLM Integration**: Built-in support for OpenAI, Anthropic, and Ollama
- 📦 **Modular Design**: Create reusable agent components
- 🔄 **Async/Await Support**: Built for modern Swift concurrency
- 🎭 **Protocol-Based**: Flexible and extensible architecture
- 📊 **State Management**: Memory and Relay for state handling
- 🔍 **Monitoring**: Built-in monitoring and debugging capabilities

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

### Foundation Models Integration

SwiftAgent integrates seamlessly with Apple's Foundation Models through the OpenFoundationModels library:

```swift
// Use Apple's Foundation Models with SwiftAgent
let agent = FoundationModelAgent(
    tools: [ExecuteCommandTool(), FileSystemTool()],
    instructions: "You are a helpful coding assistant"
)

// Generate structured data using Foundation Models
let step = FoundationModelGenerationStep.generate(
    type: Novel.self,
    instructions: "Generate a novel structure"
) { prompt in
    prompt
}
```

### Transform

The `Transform` step provides a simple way to convert data:

```swift
Transform<String, [ChatMessage]> { input -> [ChatMessage] in
    [ChatMessage(role: .user, content: [.text(input)])]
}
```

### Loop

The `Loop` step enables iterative processing with a condition:

```swift
Loop(max: 5) { input in
    ProcessingStep()
} until: { output in
    output.meetsQualityCriteria
}
```

### Map

The `Map` step processes collections by applying a transformation to each element:

```swift
Map<[Chapter], [String]> { chapter, index in
    Transform { chapter in
        // Process each chapter
    }
}
```

### Join

The `Join` step concatenates an array of strings:

```swift
Join(separator: "\n")  // Combines strings with newlines
```

## Example: AI Novelist

Here's a complete example showing how to create an AI novelist agent that generates and refines stories:

```swift
public struct Novelist: Agent {
    public typealias Input = String
    public typealias Output = String
    
    public var body: some Step<Input, Output> {
        Loop(max: 2) { request in
            // Convert request to chat message
            Transform { input -> [ChatMessage] in
                [ChatMessage(role: .user, content: [.text(input)])]
            }
            
            // Generate chapter structure
            OpenAIModel<Novel>(schema: ChaptersJSONSchema) { _ in
                """
                You are a novelist. Please output a detailed 
                chapter structure in JSON based on the following requirements:
                
                - Include compelling characters, effective foreshadowing, 
                  and impactful dialogue
                - Describe character growth and development
                - Maintain consistent themes throughout the story
                """
            }
            
            // Extract chapters
            Transform<Novel, [Chapter]> { novel in
                novel.chapters
            }
            
            // Convert each chapter to narrative
            Map<[Chapter], [String]> { chapter, index in
                Transform<Chapter, [ChatMessage]> { chapter in
                    [ChatMessage(role: .user, content: [.text(
                        createPrompt(for: chapter)
                    )])]
                }
                OpenAIModel { _ in
                    "Write the chapter following the plot outline"
                }
            }
            
            // Combine chapters
            Join()
        } until: {
            // Evaluate novel quality
            Transform<String, [ChatMessage]> { novel in
                [ChatMessage(role: .user, content: [.text(
                    "Please evaluate this novel: \(novel)"
                )])]
            }
            
            OpenAIModel<NovelQualityAssessment>(
                schema: NovelQualityAssessmentSchema
            ) { _ in
                """
                Evaluate the novel's quality based on:
                - Character development
                - Plot progression
                - Thematic consistency
                - Overall quality
                """
            }
            
            Transform<NovelQualityAssessment, Bool> { assessment in
                assessment.hasGoodCharacters &&
                assessment.hasGoodPlot &&
                assessment.hasGoodTheme &&
                assessment.isHighQuality
            }
        }
    }
}
```

The Novelist agent demonstrates several key features:
- Iterative refinement using `Loop`
- JSON schema validation for structured data
- Collection processing with `Map`
- String concatenation with `Join`
- Quality assessment with custom evaluation criteria

### Supporting Types

The agent uses several supporting types for structure:

```swift
struct Novel: Codable {
    var chapters: [Chapter]
}

struct Chapter: Codable {
    struct Setting: Codable {
        let location: String
        let timePeriod: String
    }
    
    struct Character: Codable {
        let name: String
        let role: String
    }
    
    struct PlotPoint: Codable {
        let scene: Int
        let description: String
    }
    
    let number: Int
    let title: String
    let summary: String
    let setting: Setting
    let characters: [Character]
    let plotPoints: [PlotPoint]
    let theme: String
}
```

Quality assessment is handled by:

```swift
struct NovelQualityAssessment: Codable {
    let hasGoodCharacters: Bool
    let hasGoodPlot: Bool
    let hasGoodTheme: Bool
    let isHighQuality: Bool
}
```

## Foundation Models Integration

SwiftAgent provides first-class support for Apple's Foundation Models through the OpenFoundationModels library, offering:

### Key Features

- **100% API Compatibility**: Full compatibility with Apple's Foundation Models API
- **Cross-Platform Support**: Works on iOS, macOS, and beyond Apple's ecosystem
- **Structured Data Generation**: Built-in support for type-safe data generation
- **Tool Integration**: Seamless integration with SwiftAgent's tool system
- **Conversation Management**: Advanced conversation state management

### Usage Examples

```swift
// Basic Foundation Model usage
let agent = FoundationModelAgent(
    instructions: "You are a helpful assistant specialized in Swift development"
)

let response = try await agent.run("How do I implement a custom SwiftUI view?")
```

```swift
// Structured data generation
struct CodeSuggestion: Codable, FoundationModelGenerable {
    let code: String
    let explanation: String
    let complexity: String
    
    static var generationSchema: GenerationSchema {
        return .object([
            "code": .string,
            "explanation": .string,
            "complexity": .string
        ])
    }
}

let step = FoundationModelGenerationStep.generate(
    type: CodeSuggestion.self,
    instructions: "Generate code suggestions with explanations"
) { prompt in
    "Generate a Swift function for: \(prompt)"
}
```

## Requirements

- Swift 6.0+
- iOS 18.0+ / macOS 15.0+
- OpenAI API key (for OpenAI integration)
- Anthropic API key (for Claude integration)
- Ollama installation (for local model support)
- Foundation Models support (built-in with OpenFoundationModels)

## Installation and Development Setup

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main")
]
```

### Configure API Keys

API keys must be properly configured for language model integration. You have several options:

#### Option 1: Xcode Environment Variables

1. Open your Xcode project
2. Go to Edit Scheme (⌘ + <)
3. Select "Run" from the left sidebar
4. Go to the "Arguments" tab
5. Under "Environment Variables", add:
   - `OPENAI_API_KEY`: Your OpenAI API key
   - `ANTHROPIC_API_KEY`: Your Anthropic API key
   - `OLLAMA_HOST`: Your Ollama host (optional, defaults to "http://localhost:11434")

#### Option 2: Environment File

Create a `.env` file in your project root:

```bash
OPENAI_API_KEY=your_openai_api_key_here
ANTHROPIC_API_KEY=your_anthropic_api_key_here
OLLAMA_HOST=http://localhost:11434
```

#### Option 3: Shell Environment

Add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export OPENAI_API_KEY=your_openai_api_key_here
export ANTHROPIC_API_KEY=your_anthropic_api_key_here
export OLLAMA_HOST=http://localhost:11434
```

### Local Development Setup

1. **Install Xcode 15.0+**
   - Required for Swift 6.0 support
   - Available from the Mac App Store or developer.apple.com

2. **Install Ollama (Optional, for local model support)**
   ```bash
   curl https://ollama.ai/install.sh | sh
   ```

3. **Clone the Repository**
   ```bash
   git clone https://github.com/1amageek/SwiftAgent.git
   cd SwiftAgent
   ```

4. **Install Dependencies**
   ```bash
   swift package resolve
   ```

5. **Open in Xcode**
   ```bash
   xed .
   ```

### Testing

Run the test suite:

```bash
swift test
```

Or run specific test targets:

```bash
swift test --filter SwiftAgentTests.SpecificTestSuite
```

## License

SwiftAgent is available under the MIT license.

## Author

@1amageek
