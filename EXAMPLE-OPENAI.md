# SwiftAgent with OpenAI Example

## Setup

1. Add OpenFoundationModels-OpenAI dependency to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main"),
    .package(url: "https://github.com/1amageek/OpenFoundationModels-OpenAI.git", branch: "main")
]
```

2. Import required modules:

```swift
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI
```

## Example: Creating a Step with OpenAI

```swift
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

struct MyOpenAIStep: Step {
    let apiKey: String

    public var body: some Step<String, String> {
        StringModelStep<String>(
            session: LanguageModelSession(
                model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
                instructions: Instructions("You are a helpful assistant.")
            )
        ) { input in
            input
        }
    }
}

// Usage
let step = MyOpenAIStep(apiKey: "your-api-key")
let response = try await step.run("What is quantum computing?")
print(response)
```

## Example: Using Tools with OpenAI

```swift
struct ResearchStep: Step {
    let apiKey: String

    public var body: some Step<String, String> {
        StringModelStep<String>(
            session: LanguageModelSession(
                model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
                tools: [
                    URLFetchTool(),
                    FileSystemTool()
                ],
                instructions: Instructions("You are a research assistant.")
            )
        ) { input in
            input
        }
    }
}
```

## Example: Structured Output with OpenAI

```swift
@Generable
struct Analysis {
    @Guide(description: "Summary of the topic")
    let summary: String
    @Guide(description: "Key points", .count(3...5))
    let keyPoints: String
    @Guide(description: "Confidence level", .range(0.0...1.0))
    let confidence: Double
}

struct AnalysisStep: Step {
    let apiKey: String

    public var body: some Step<String, Analysis> {
        ModelStep<String, Analysis>(
            session: LanguageModelSession(
                model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
                instructions: Instructions("Analyze the given topic thoroughly.")
            )
        ) { input in
            input
        }
    }
}
```

## Example: Reasoning Model (o1)

```swift
struct ReasoningStep: Step {
    let apiKey: String

    public var body: some Step<String, String> {
        StringModelStep<String>(
            session: LanguageModelSession(
                model: OpenAIModelFactory.o1(apiKey: apiKey),
                instructions: Instructions("Think step by step to solve complex problems.")
            )
        ) { input in
            input
        }
    }
}
```

## Configuration Options

```swift
// With custom generation options
let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.openai.com/v1")
    ),
    guardrails: .default,
    instructions: Instructions("You are a creative writer.")
)

// Generate with options
let response = try await session.respond(
    generating: String.self,
    options: GenerationOptions(
        temperature: 0.7,
        maxTokens: 1000,
        topP: 0.9
    )
) {
    Prompt("Write a short story")
}
```