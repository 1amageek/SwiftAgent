# SwiftAgent

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/1amageek/SwiftAgent)

A type-safe, declarative framework for building AI agents in Swift.

## Features

- **Declarative Syntax** - Build agents with composable `Step` chains
- **Type-Safe** - Compile-time checked input/output types
- **Built on FoundationModels** - Native Apple AI integration
- **Structured Output** - Generate typed data with `@Generable`
- **Security Built-in** - Permission, Sandbox, and Guardrail systems
- **Extensible** - MCP integration, distributed agents, skills system

## Quick Start

### Requirements

- Swift 6.2+
- iOS 26.0+ / macOS 26.0+
- Xcode 26.0+

### Installation

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
        .product(name: "AgentTools", package: "SwiftAgent")  // Optional
    ]
)
```

### Minimal Example

```swift
import SwiftAgent
import FoundationModels

struct Translator: Agent {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        GenerateText(session: session) { input in
            Prompt("Translate to Japanese: \(input)")
        }
    }
}

// Usage
let session = LanguageModelSession(model: SystemLanguageModel.default) {
    Instructions("You are a professional translator")
}

let result = try await Translator()
    .session(session)
    .run("Hello, world!")
```

## Core Concepts

### Step

The fundamental building block. Transforms input to output asynchronously.

```swift
public protocol Step<Input, Output> {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    func run(_ input: Input) async throws -> Output
}
```

Use `Step` when you need custom control flow:

```swift
struct CustomStep: Step {
    func run(_ input: String) async throws -> String {
        if input.isEmpty { return "Empty" }
        return try await someAsyncOperation(input)
    }
}
```

### Agent

A declarative `Step` that defines its behavior through a `body` property. The framework handles execution automatically.

```swift
struct Pipeline: Agent {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText(session: session) { Prompt("Process: \($0)") }
        Transform { "Result: \($0)" }
    }
}
```

### Session

Provides `LanguageModelSession` to Steps via TaskLocal propagation.

```swift
struct MyStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        let response = try await session.respond { Prompt(input) }
        return response.content
    }
}

// Provide session via modifier
try await MyStep()
    .session(session)
    .run("Hello")
```

Sessions automatically propagate through nested Steps:

```swift
struct OuterStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        // InnerStep automatically gets the same session
        let processed = try await InnerStep().run(input)
        let response = try await session.respond { Prompt(processed) }
        return response.content
    }
}
```

### Memory / Relay

Share state between Steps with reference semantics.

```swift
struct Orchestrator: Step {
    @Memory var visitedURLs: Set<URL> = []
    @Memory var resultCount: Int = 0

    func run(_ input: URL) async throws -> Result {
        // Pass Relay to child Steps via $ prefix
        try await CrawlStep(
            visited: $visitedURLs,
            counter: $resultCount
        ).run(input)
        return Result(count: resultCount)
    }
}

struct CrawlStep: Step {
    let visited: Relay<Set<URL>>
    let counter: Relay<Int>

    func run(_ input: URL) async throws -> Void {
        if visited.contains(input) { return }
        visited.insert(input)
        counter.increment()
        // Crawl...
    }
}
```

**Relay Convenience Methods:**

```swift
// Set operations
$urls.insert(url)
$urls.remove(url)
$urls.contains(url)
$urls.formUnion(newURLs)

// Array operations
$items.append("item")
$items.append(contentsOf: more)
$items.removeAll()

// Int operations
$count.increment()    // += 1
$count.decrement()    // -= 1
$count.add(5)         // += 5

// Transformations
let doubled = $count.map({ $0 * 2 }, reverse: { $0 / 2 })
let readOnly = $count.readOnly { $0 * 2 }
```

### Context

Propagate configuration through the Step hierarchy using `@Contextable`.

```swift
// 1. Define a Contextable type with defaultValue
@Contextable
struct CrawlerConfig: Contextable {
    static var defaultValue: CrawlerConfig {
        CrawlerConfig(maxDepth: 3, timeout: 30)
    }
    let maxDepth: Int
    let timeout: Int
}

// 2. Access via @Context (uses defaultValue if not provided)
struct MyStep: Step {
    @Context var config: CrawlerConfig

    func run(_ input: URL) async throws -> Result {
        print("Max depth: \(config.maxDepth)")
        // ...
    }
}

// 3. Provide via modifier
try await MyStep()
    .context(CrawlerConfig(maxDepth: 10, timeout: 60))
    .run(url)

// Chain multiple contexts
try await MyStep()
    .context(config)
    .context(tracker)
    .session(session)
    .run(input)
```

Context is ideal for:
- Configuration that many Steps need
- Shared trackers or loggers
- Request-scoped data

## Built-in Steps

| Step | Description |
|------|-------------|
| `Transform` | Synchronous data transformation |
| `Generate<I, O>` | Structured output generation |
| `GenerateText` | Text generation |
| `Loop` | Iterate until condition met |
| `Map` | Process collections |
| `Reduce` | Aggregate collection elements |
| `Parallel` | Execute concurrently, collect all results |
| `Race` | Execute concurrently, return first success |

### Transform

```swift
Transform<String, Int> { $0.count }
```

### Loop

```swift
Loop(max: 5) { input in
    RefineStep()
} until: { output in
    output.quality >= 0.9
}
```

### Map

```swift
Map<[URL], [Data]> { url, index in
    FetchStep()
}
```

### Parallel

Execute all steps concurrently and collect successful results (best-effort).

```swift
let parallel = Parallel<Query, SearchResult> {
    SearchGitHub()
    SearchStackOverflow()
    SearchDocumentation()
}
// Returns all successful results, continues if some fail
```

### Race

Execute all steps concurrently and return the first success (fallback pattern).

```swift
let race = Race<URL, Data> {
    FetchFromPrimary()    // Fast but sometimes down
    FetchFromMirror()     // Slower but reliable
    FetchFromCDN()        // Cached if available
}
// Returns first successful result, ignores failures

// With timeout
Race<String, String>(timeout: .seconds(5)) {
    GenerateWithAPI()
    GenerateLocally()
}
```

### Error Handling

```swift
// Timeout
FetchStep()
    .timeout(.seconds(10))

// Retry with delay
FetchStep()
    .retry(3, delay: .seconds(1))

// Try-Catch
Try {
    FetchFromPrimary()
} catch: { error in
    FetchFromBackup()
}

// Error transformation
ParseStep()
    .mapError { MyError.parseFailed($0) }

// Combined
FetchStep()
    .timeout(.seconds(5))
    .retry(3)
    .mapError { MyError.fetchFailed($0) }
```

## Structured Output

Use `@Generable` to generate typed data from LLM responses.

```swift
@Generable
struct Analysis {
    @Guide(description: "Summary of findings")
    let summary: String

    @Guide(description: "List of issues found")
    let issues: String

    @Guide(description: "Recommendations for improvement")
    let recommendations: String
}

struct Analyzer: Agent {
    @Session var session: LanguageModelSession

    var body: some Step<String, Analysis> {
        Generate(session: session) { input in
            Prompt("Analyze the following code:\n\(input)")
        }
    }
}

let analysis = try await Analyzer()
    .session(session)
    .run(codeString)

print(analysis.summary)
print(analysis.issues)
```

**@Generable Limitations:**

- Dictionary types are not supported
- Enums are not supported (use `@Guide(enumeration:)` instead)
- All properties require `@Guide`

## Tools (AgentTools)

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

```swift
let session = LanguageModelSession(
    model: myModel,
    tools: [
        ReadTool(),
        WriteTool(),
        EditTool(),
        GrepTool(),
        GlobTool(),
        ExecuteCommandTool()
    ]
) {
    Instructions("You are a code assistant with file system access")
}
```

## Security

SwiftAgent provides three layers of security: **Permission**, **Sandbox**, and **Guardrail**.

### Permission

Controls **which tools** can be executed.

```swift
let config = PermissionConfiguration(
    allow: [.tool("Read"), .bash("git:*")],
    deny: [.bash("rm:*")],
    finalDeny: [.bash("sudo:*")],    // Cannot be overridden
    defaultAction: .ask,
    handler: CLIPermissionHandler(),
    enableSessionMemory: true        // Remember "Always Allow/Block"
)
```

**Rule Evaluation Order:**

```
1. Final Deny → Reject (absolute, cannot override)
2. Session Memory → Use cached decision
3. Override → Skip matching Deny rules
4. Deny → Reject
5. Allow → Permit
6. Default Action → allow/deny/ask
```

**Pattern Syntax:**

| Pattern | Matches |
|---------|---------|
| `"Read"` | Read tool |
| `"Bash(git:*)"` | git commands (git + delimiter) |
| `"Write(/tmp/*)"` | Writes under /tmp/ |
| `"mcp__github__*"` | All GitHub MCP tools |
| `"mcp__*"` | All MCP tools |

Patterns are case-sensitive. `prefix:*` requires a delimiter (space, dash, tab, etc.) after the prefix. File paths are normalized before matching.

### Sandbox (macOS)

Controls **how commands** are executed with file/network restrictions.

```swift
let config = SandboxExecutor.Configuration(
    networkPolicy: .local,              // .none, .local, .full
    filePolicy: .workingDirectoryOnly,  // .readOnly, .workingDirectoryOnly, .custom
    allowSubprocesses: true
)
```

| Network Policy | Access |
|----------------|--------|
| `.none` | No network |
| `.local` | localhost only |
| `.full` | Unrestricted |

| File Policy | Read | Write |
|-------------|:----:|:-----:|
| `.readOnly` | All | None |
| `.workingDirectoryOnly` | All | Working dir + /tmp |
| `.custom(read:write:)` | Specified paths | Specified paths |

### Combining Permission + Sandbox

Use `withSecurity` to apply both as middleware:

```swift
let security = SecurityConfiguration(
    permissions: PermissionConfiguration(
        allow: [.tool("Read"), .bash("git:*")],
        deny: [.bash("rm:*")],
        finalDeny: [.bash("sudo:*")],
        defaultAction: .ask,
        handler: CLIPermissionHandler()
    ),
    sandbox: .standard
)

let config = AgentConfiguration(...)
    .withSecurity(security)
```

**Presets:**

| Preset | Permission | Sandbox |
|--------|------------|---------|
| `.standard` | Interactive (ask) | Local network, working dir |
| `.development` | Permissive | None |
| `.restrictive` | Minimal | No network, read-only |
| `.readOnly` | Read tools only | None |

```swift
.withSecurity(.standard)
.withSecurity(.development)
.withSecurity(.restrictive)
.withSecurity(.readOnly)
```

### Guardrail

Declarative **Step-level** security policies using `.guardrail { }` modifier.

```swift
FetchUserData()
    .guardrail {
        Allow(.tool("Read"))
        Deny(.bash("rm:*"))
        Sandbox(.restrictive)
    }
```

**Rule Types:**

| Rule | Description |
|------|-------------|
| `Allow` | Permit patterns |
| `Deny` | Block patterns (can be overridden by child) |
| `Deny.final` | Block patterns (cannot be overridden) |
| `Override` | Relax parent's Deny rules |
| `AskUser` | Require confirmation |
| `Sandbox` | Apply sandbox config |

**Hierarchical Application:**

Guardrails inherit from parent to child. Use `Override` to selectively relax restrictions.

```swift
struct SecurePipeline: Agent {
    var body: some Step<String, String> {
        ProcessStep()
            .guardrail {
                Deny.final(.bash("sudo:*"))  // Absolute - cannot override
                Deny(.bash("rm:*"))          // Can be overridden
            }

        CleanupStep()
            .guardrail {
                Override(.bash("rm:*.tmp"))  // Allowed for .tmp files
                // Override(.bash("sudo:*")) would be ignored (final)
            }
    }
}
```

**Conditional Rules:**

```swift
.guardrail {
    Allow(.tool("Read"))

    if isProduction {
        Deny(.bash("*"))
        Sandbox(.restrictive)
    } else {
        Sandbox(.permissive)
    }
}
```

**Presets:**

```swift
.guardrail(.readOnly)
.guardrail(.standard)
.guardrail(.restrictive)
.guardrail(.noNetwork)
```

### Execution Flow

```
Tool Request
    │
    ▼
PermissionMiddleware ── deny ──→ PermissionDenied
    │ allow
    ▼
SandboxMiddleware (injects config via @Context)
    │
    ▼
Tool Execution
```

## Extension Modules

### SwiftAgentMCP

MCP (Model Context Protocol) integration. Claude Code compatible tool naming.

```swift
import SwiftAgentMCP

// Load from .mcp.json
let manager = try await MCPClientManager.loadDefault()
let tools = try await manager.allTools()  // mcp__server__tool format

// Use with session
let session = LanguageModelSession(model: myModel, tools: tools) {
    Instructions("You are a helpful assistant")
}

// Server management
await manager.disable(serverName: "slack")
await manager.enable(serverName: "slack")
```

Permission integration:

```swift
.allowing(.mcp("github"))      // Allow mcp__github__*
.denying(.mcp("filesystem"))   // Deny mcp__filesystem__*
```

See [docs/MCP.md](docs/MCP.md) for configuration file format and transport options.

### SwiftAgentSymbio

Distributed agent communication using Swift Distributed Actors.

```swift
import SwiftAgentSymbio

let actorSystem = SymbioActorSystem()
let community = Community(actorSystem: actorSystem)

// Spawn agent
let worker = try await community.spawn {
    WorkerAgent(community: community, actorSystem: actorSystem)
}

// Find and send
let workers = await community.whoCanReceive("work")
try await community.send(WorkSignal(task: "process"), to: worker, perception: "work")

// Monitor changes
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

Portable skill packages with auto-discovery from `~/.agent/skills/` and `./.agent/skills/`.

```swift
let config = AgentConfiguration(...)
    .withSkills(.autoDiscover())

// Or with custom paths
    .withSkills(.autoDiscover(additionalPaths: ["/custom/path"]))
```

See [docs/SKILLS.md](docs/SKILLS.md) for SKILL.md format and progressive disclosure.

## Streaming

Process output as it's generated:

```swift
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
let result = try await step.run("Swift Concurrency")
```

Structured output streaming:

```swift
let step = Generate<String, BlogPost>(
    session: session,
    prompt: { Prompt("Write a blog post about: \($0)") },
    onStream: { snapshot in
        // Properties are Optional in PartiallyGenerated
        if let title = snapshot.content.title {
            print("Title: \(title)")
        }
    }
)
```

## Monitoring

```swift
MyStep()
    .onInput { print("Input: \($0)") }
    .onOutput { print("Output: \($0)") }
    .onError { print("Error: \($0)") }

// Distributed tracing
MyStep()
    .trace("TextGeneration", kind: .client)
```

## Examples

### Code Analysis Agent

```swift
@Generable
struct CodeReview {
    @Guide(description: "Summary of code quality")
    let summary: String
    @Guide(description: "Potential bugs or issues")
    let issues: String
    @Guide(description: "Suggested improvements")
    let suggestions: String
}

struct CodeAnalyzer: Agent {
    @Session var session: LanguageModelSession

    var body: some Step<String, CodeReview> {
        Generate(session: session) { code in
            Prompt {
                "Review the following code:"
                code
                "Focus on bugs, performance, and best practices."
            }
        }
    }
}

// Usage with tools and security
let session = LanguageModelSession(
    model: SystemLanguageModel.default,
    tools: [ReadTool(), GrepTool()]
) {
    Instructions("You are a code review expert")
}

let review = try await CodeAnalyzer()
    .session(session)
    .guardrail(.readOnly)
    .run(sourceCode)
```

### Multi-Step Pipeline with Error Handling

```swift
struct ResearchPipeline: Agent {
    @Session var session: LanguageModelSession

    var body: some Step<String, Report> {
        // Fetch with fallback
        Try {
            FetchFromAPI()
                .timeout(.seconds(10))
        } catch: { _ in
            FetchFromCache()
        }

        // Process in parallel
        Parallel<Data, Analysis> {
            AnalyzeContent()
            ExtractMetadata()
            ClassifyTopic()
        }

        // Generate final report
        Generate(session: session) { analyses in
            Prompt("Create a report from: \(analyses)")
        }
    }
}
```

## OpenFoundationModels

For development with other LLM providers, build with:

```bash
USE_OTHER_MODELS=1 swift build
USE_OTHER_MODELS=1 swift test
```

```swift
import OpenFoundationModels

let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(apiKey: "...")
) {
    Instructions("You are a helpful assistant")
}
```

Available providers:
- [OpenFoundationModels-OpenAI](https://github.com/1amageek/OpenFoundationModels-OpenAI)
- [OpenFoundationModels-Anthropic](https://github.com/1amageek/OpenFoundationModels-Anthropic)
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama)

## License

MIT

## Author

[@1amageek](https://github.com/1amageek)
