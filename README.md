<p align="center">
  <img src="SwiftAgent.png" alt="SwiftAgent" width="100%">
</p>

# SwiftAgent

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%20|%20macOS%2026%20|%20tvOS%2026-blue.svg)](https://developer.apple.com)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://1amageek.github.io/SwiftAgent/documentation/swiftagent/)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/1amageek/SwiftAgent)

A type-safe, declarative framework for building AI agents in Swift, built on Apple FoundationModels.

**[Documentation](https://1amageek.github.io/SwiftAgent/documentation/swiftagent/)**

## Features

- **Declarative Syntax** - Build agents by composing Steps in `body`, just like SwiftUI
- **Type-Safe** - Compile-time checked input/output types
- **Built on FoundationModels** - Native Apple AI integration
- **Structured Output** - Generate typed data with `@Generable`
- **Security Built-in** - Permission, Sandbox, and Guardrail systems
- **Extensible** - MCP integration, distributed agents, skills system

## Installation

**Requirements:** Swift 6.2+ / iOS 26+ / macOS 26+ / Xcode 26+

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main")
]
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SwiftAgent", package: "SwiftAgent"),
        .product(name: "AgentTools", package: "SwiftAgent"),  // Optional
    ]
)
```

### OpenFoundationModels

SwiftAgent supports alternative LLM providers via SPM Traits. Enable the `OpenFoundationModels` trait to use OpenAI, Claude, Ollama, and more:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/SwiftAgent.git", branch: "main", traits: ["OpenFoundationModels"])
]
```

```bash
swift build --traits OpenFoundationModels
swift test --traits OpenFoundationModels
```

```swift
import OpenFoundationModels

let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(apiKey: "...")
) {
    Instructions("You are a helpful assistant")
}
```

Available providers: [OpenAI](https://github.com/1amageek/OpenFoundationModels-OpenAI) | [Claude](https://github.com/1amageek/OpenFoundationModels-Claude) | [Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama)

## Quick Start

```swift
import SwiftAgent
import FoundationModels

struct Translator: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        GenerateText(session: session) { input in
            Prompt("Translate to Japanese: \(input)")
        }
    }
}

let session = LanguageModelSession(model: SystemLanguageModel.default) {
    Instructions("You are a professional translator")
}

let result = try await Translator()
    .session(session)
    .run("Hello, world!")
```

## Step

The fundamental building block. Define `body` to compose steps declaratively -- the framework auto-synthesizes `run(_:)`, just like SwiftUI synthesizes view rendering from `body`.

```swift
struct TextPipeline: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText(session: session) { Prompt("Summarize: \($0)") }
        Transform { "Summary: \($0)" }
    }
}
```

Steps listed in `body` execute sequentially: each step's output becomes the next step's input, forming a type-safe pipeline.

```swift
// String -> Transform -> String -> GenerateText -> String -> Transform -> String
```

For complex control flow that cannot be expressed declaratively, override `run(_:)` directly:

```swift
struct ConditionalStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        if input.count < 10 {
            return input  // Skip LLM for short input
        }
        return try await GenerateText(session: session) {
            Prompt("Expand: \(input)")
        }.run(input)
    }
}
```

### Built-in Steps

All built-in steps can be used inside `body`:

| Step | Description |
|------|-------------|
| `Transform` | Synchronous data transformation |
| `Generate<I, O>` | Structured output generation |
| `GenerateText` | Text generation |
| `Gate` | Validate / transform or block execution |
| `Loop` | Iterate until condition met |
| `Map` | Process collections in parallel |
| `Reduce` | Aggregate collection elements |
| `Parallel` | Execute concurrently, collect all successes |
| `Race` | Execute concurrently, return first success |
| `Pipeline` | Compose steps sequentially (outside `body`) |

```swift
struct ResearchPipeline: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, Report> {
        // Validate input
        Gate { input in
            guard !input.isEmpty else { return .block(reason: "Empty query") }
            return .pass(input)
        }

        // Generate search queries
        Generate<String, SearchQueries>(session: session) { input in
            Prompt("Generate search queries for: \(input)")
        }

        // Fetch from multiple sources in parallel
        Transform { queries in queries.items }
        Map<[String], [SearchResult]> { query, _ in FetchStep() }

        // Synthesize into report
        Generate<[SearchResult], Report>(session: session) { results in
            Prompt("Create a report from: \(results)")
        }
    }
}
```

### Parallel / Race

```swift
// Parallel - best-effort, collects all successes
struct MultiSearch: Step {
    var body: some Step<Query, [SearchResult]> {
        Parallel {
            SearchGitHub()
            SearchStackOverflow()
            SearchDocumentation()
        }
    }
}

// Race - returns first success (fallback pattern)
struct FetchWithFallback: Step {
    var body: some Step<URL, Data> {
        Race(timeout: .seconds(5)) {
            FetchFromPrimary()
            FetchFromMirror()
            FetchFromCDN()
        }
    }
}
```

### Gate

`Gate` validates or transforms input. Returns `.pass(value)` to continue or `.block(reason:)` to halt.

```swift
struct SafePipeline: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        Gate { .pass(sanitize($0)) }
        GenerateText(session: session) { Prompt($0) }
        Gate { .pass(filterSensitive($0)) }
    }
}
```

### Pipeline

`Pipeline` provides `body`-like composition outside of a Step declaration:

```swift
let step = Pipeline {
    Gate { input in
        guard !input.isEmpty else { return .block(reason: "Empty") }
        return .pass(input.lowercased())
    }
    MyProcessingStep()
}
try await step.run("Hello")
```

### Error Handling

```swift
struct ResilientFetch: Step {
    var body: some Step<URL, Data> {
        Try {
            FetchFromPrimary()
                .timeout(.seconds(10))
                .retry(3, delay: .seconds(1))
        } catch: { _ in
            FetchFromBackup()
        }
    }
}
```

### Step Modifiers

Modifiers wrap a step with additional behavior, similar to SwiftUI view modifiers:

```swift
struct MyWorkflow: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        GenerateText(session: session) { Prompt($0) }
            .timeout(.seconds(30))
            .retry(3, delay: .seconds(1))
            .mapError { MyError.generationFailed($0) }
            .onInput { print("Input: \($0)") }
            .onOutput { print("Output: \($0)") }
            .trace("TextGeneration", kind: .client)
    }
}
```

## Session

Provides `LanguageModelSession` to steps via TaskLocal propagation. Attach once at the top and it automatically flows through all nested steps.

```swift
struct OuterStep: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        InnerStepA()   // inherits session
        InnerStepB()   // inherits session
    }
}

try await OuterStep()
    .session(session)   // provide once
    .run("Hello")
```

### AgentSession

Thread-safe interactive session with FIFO message queuing and steering.

```swift
let session = AgentSession(tools: myTools) {
    Instructions("You are a helpful assistant.")
}

// FIFO queuing
let response = try await session.send("Hello!")

// Steering: add context to the next prompt
session.steer("Use async/await")
session.steer("Add error handling")
let response = try await session.send("Write a function...")

// Session replacement (safe during processing)
session.replaceSession(with: compactedTranscript)

// Persistence
let snapshot = session.snapshot()
let restored = AgentSession.restore(from: snapshot, tools: myTools)
```

| Property | Type | Description |
|----------|------|-------------|
| `transcript` | `Transcript` | Current conversation transcript |
| `isResponding` | `Bool` | Whether currently generating |
| `pendingSteeringCount` | `Int` | Steering messages waiting |

## Memory / Relay

Share mutable state between steps with reference semantics. `@Memory` holds the value; `$` prefix yields a `Relay` for passing to child steps.

```swift
struct Orchestrator: Step {
    @Memory var visitedURLs: Set<URL> = []
    @Memory var resultCount: Int = 0

    var body: some Step<URL, CrawlResult> {
        CrawlStep(visited: $visitedURLs, counter: $resultCount)
    }
}

struct CrawlStep: Step {
    let visited: Relay<Set<URL>>
    let counter: Relay<Int>

    func run(_ input: URL) async throws -> CrawlResult {
        if visited.contains(input) { return .alreadyVisited }
        visited.insert(input)
        counter.increment()
        // ...
    }
}
```

**Relay convenience methods:**

```swift
$urls.insert(url)       // Set
$urls.contains(url)
$items.append("item")   // Array
$count.increment()      // Int: += 1
$count.add(5)           // Int: += 5

let doubled = $count.map({ $0 * 2 }, reverse: { $0 / 2 })
let readOnly = $count.readOnly { $0 * 2 }
```

## Context

Propagate configuration through the step hierarchy via TaskLocal. Attach with `.context()` and read with `@Context`.

```swift
@Contextable
struct CrawlerConfig {
    let maxDepth: Int
    let timeout: Int
    static var defaultValue: CrawlerConfig { CrawlerConfig(maxDepth: 3, timeout: 30) }
}

struct MyCrawler: Step {
    @Context var config: CrawlerConfig
    @Session var session: LanguageModelSession

    var body: some Step<URL, Report> {
        FetchStep()             // can also read @Context var config
        AnalyzeStep()
        Generate<Analysis, Report>(session: session) { analysis in
            Prompt("Summarize with max depth \(config.maxDepth): \(analysis)")
        }
    }
}

try await MyCrawler()
    .context(CrawlerConfig(maxDepth: 10, timeout: 60))
    .session(session)
    .run(url)
```

## Structured Output

Use `@Generable` to generate typed data from LLM responses.

```swift
@Generable
struct CodeReview {
    @Guide(description: "Summary of code quality") let summary: String
    @Guide(description: "Potential bugs or issues") let issues: String
    @Guide(description: "Suggested improvements") let suggestions: String
}

struct CodeAnalyzer: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, CodeReview> {
        Generate(session: session) { code in
            Prompt("Review the following code:\n\(code)")
        }
    }
}

let review = try await CodeAnalyzer().session(session).run(sourceCode)
print(review.summary)
```

> **@Generable limitations:** Dictionary and enum types are not supported. All properties require `@Guide`.

## Streaming

```swift
// Text streaming
var previous = ""
let step = GenerateText<String>(
    session: session,
    prompt: { Prompt("Write about: \($0)") },
    onStream: { snapshot in
        let chunk = String(snapshot.content.dropFirst(previous.count))
        previous = snapshot.content
        print(chunk, terminator: "")
    }
)

// Structured output streaming (properties are Optional in PartiallyGenerated)
let step = Generate<String, BlogPost>(
    session: session,
    prompt: { Prompt("Write a blog post about: \($0)") },
    onStream: { snapshot in
        if let title = snapshot.content.title {
            print("Title: \(title)")
        }
    }
)
```

## Event

Type-safe event emission using `EventName` and `EventBus` propagated via `@Context`.

```swift
extension EventName {
    static let sessionStarted = EventName("sessionStarted")
    static let sessionEnded = EventName("sessionEnded")
}

struct EventedWorkflow: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        GenerateText(session: session) { Prompt($0) }
            .emit(.sessionStarted, on: .before)
            .emit(.sessionEnded, on: .after)
    }
}

let eventBus = EventBus()
await eventBus.on(.sessionStarted) { payload in
    print("Started: \(payload.value ?? "")")
}

try await EventedWorkflow()
    .session(session)
    .context(eventBus)
    .run(input)
```

## AgentTools

Claude Code-style tool naming for file system and web operations.

| Tool | Description |
|------|-------------|
| `Read` | Read file contents with line numbers |
| `Write` | Write content to files |
| `Edit` | Find and replace text |
| `MultiEdit` | Atomic multi-edit transactions |
| `Grep` | Regex content search |
| `Glob` | File pattern search |
| `Bash` | Execute shell commands |
| `Git` | Git operations |
| `WebFetch` | Fetch URL content |
| `WebSearch` | Web search |
| `Notebook` | In-memory key-value scratchpad |
| `Dispatch` | Sub-LLM session delegation |

```swift
let session = LanguageModelSession(
    model: myModel,
    tools: [ReadTool(), WriteTool(), EditTool(), GrepTool(), GlobTool(), ExecuteCommandTool()]
) {
    Instructions("You are a code assistant with file system access")
}
```

### Nested Agents (RLM-inspired)

AgentTools supports nested agent patterns inspired by [Recursive Language Models (RLM)](https://arxiv.org/abs/2512.24601). RLM demonstrates that LLMs can overcome context window limitations by storing data in an external environment and recursively delegating sub-tasks to fresh LLM sessions.

SwiftAgent makes this straightforward with two built-in tools:

- **`Notebook`** — An in-memory scratchpad where agents store and retrieve data outside their context window
- **`Dispatch`** — Spawns child LLM sessions that share the parent's Notebook and can recursively dispatch further sub-agents

Child sessions are depth-limited and operate independently from the parent's conversation history, enabling an agent to decompose complex problems into focused sub-tasks — each handled by a nested agent with its own reasoning scope.

> Zhang, A. L., Krasta, T., & Khattab, O. (2025). *Recursive Language Models.* arXiv:2512.24601.

## Security

Three layers: **Permission** (which tools), **Sandbox** (how commands run), **Guardrail** (per-step policy).

### Permission

```swift
let config = PermissionConfiguration(
    allow: [.tool("Read"), .bash("git:*")],
    deny: [.bash("rm:*")],
    finalDeny: [.bash("sudo:*")],    // Cannot be overridden
    defaultAction: .ask,
    handler: CLIPermissionHandler(),
    enableSessionMemory: true
)
```

**Evaluation order:** Final Deny > Session Memory > Override > Deny > Allow > Default

| Pattern | Matches |
|---------|---------|
| `"Read"` | Read tool |
| `"Bash(git:*)"` | git commands |
| `"Write(/tmp/*)"` | Writes under /tmp/ |
| `"mcp__*"` | All MCP tools |

### Sandbox (macOS)

```swift
let config = SandboxExecutor.Configuration(
    networkPolicy: .local,              // .none, .local, .full
    filePolicy: .workingDirectoryOnly,  // .readOnly, .workingDirectoryOnly, .custom
    allowSubprocesses: true
)
```

### Guardrail

Declarative step-level security applied via `.guardrail { }` modifier. Guardrails inherit from parent to child.

```swift
struct SecureWorkflow: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        GenerateText(session: session) { Prompt($0) }
            .guardrail {
                Allow(.tool("Read"))
                Deny.final(.bash("sudo:*"))  // Absolute, cannot override
                Deny(.bash("rm:*"))          // Can be overridden by child
                Sandbox(.restrictive)
            }

        CleanupStep()
            .guardrail {
                Override(.bash("rm:*.tmp"))   // Relaxes parent Deny for .tmp
            }
    }
}

// Presets
.guardrail(.readOnly)
.guardrail(.standard)
.guardrail(.restrictive)
```

### Security Presets

```swift
let config = AgentConfiguration(...)
    .withSecurity(.standard)      // Interactive ask, local network, working dir
    .withSecurity(.development)   // Permissive, no sandbox
    .withSecurity(.restrictive)   // Minimal, no network, read-only
    .withSecurity(.readOnly)      // Read tools only
```

## Extension Modules

### SwiftAgentMCP

MCP (Model Context Protocol) integration with Claude Code-compatible tool naming.

```swift
import SwiftAgentMCP

let manager = try await MCPClientManager.loadDefault()  // .mcp.json
let tools = try await manager.allTools()  // mcp__server__tool format

// Permission integration
.allowing(.mcp("github"))
.denying(.mcp("filesystem"))
```

See [docs/MCP.md](docs/MCP.md) for configuration and transport options.

### SwiftAgentSymbio

Distributed agent communication using Swift Distributed Actors.

```swift
import SwiftAgentSymbio

let actorSystem = SymbioActorSystem()
let community = Community(actorSystem: actorSystem)

let worker = try await community.spawn {
    WorkerAgent(community: community, actorSystem: actorSystem)
}

try await community.send(WorkSignal(task: "process"), to: worker, perception: "work")

for await change in await community.changes {
    switch change {
    case .joined(let member): print("Joined: \(member.id)")
    case .left(let member): print("Left: \(member.id)")
    default: break
    }
}
```

See [docs/SYMBIOSIS.md](docs/SYMBIOSIS.md) for protocols and SubAgent spawning.

### Skills

Portable skill packages with auto-discovery.

```swift
let config = AgentConfiguration(...)
    .withSkills(.autoDiscover())
```

See [docs/SKILLS.md](docs/SKILLS.md) for SKILL.md format.

## Architecture

```
                    FoundationModels (default)
                    OpenFoundationModels (--traits OpenFoundationModels)
                           |
                       SwiftAgent
                      /    |    \
        SwiftAgentMCP  AgentTools  SwiftAgentSymbio
              |                          |
         MCP (swift-sdk)         swift-actor-runtime
                                         |
                                  swift-discovery
```

## License

MIT

## Author

[@1amageek](https://github.com/1amageek)
