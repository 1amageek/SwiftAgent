# Context Propagation

Share configuration and state across nested Steps using TaskLocal-based context.

## Overview

When building complex pipelines with nested Steps, you often need to share configuration or state without explicitly passing parameters through every level. SwiftAgent's ``Context`` system provides TaskLocal-based propagation that automatically flows through the Step hierarchy.

## Ownership and Isolation

| Type | Responsibility |
| --- | --- |
| ``Contextable`` | Defines a value's default, current value, and scoped installation contract |
| ``ContextValueKey`` | Implements the default type-indexed TaskLocal storage |
| ``ContextKey`` | Provides an explicit TaskLocal boundary for runtime infrastructure with custom semantics |
| ``ContextStep`` | Owns one installed value for the duration of the wrapped Step |

The core context API depends only on Swift Concurrency. Compiler plugins and
model-provider dependencies do not participate in context propagation. Each
scope installs an immutable value-map snapshot, child tasks inherit that
snapshot, and TaskLocal restores the parent snapshot on success or failure.

## Defining a Contextable Type

Conform value types directly to ``Contextable``:

```swift
struct CrawlerConfig: Contextable {
    let maxDepth: Int
    let timeout: TimeInterval
    let userAgent: String

    static var defaultValue: CrawlerConfig {
        CrawlerConfig(maxDepth: 3, timeout: 30, userAgent: "SwiftAgent/1.0")
    }
}
```

``Contextable`` supplies a type-indexed ``ContextValueKey`` by default. This
keeps context propagation independent of compiler plugins while preserving
TaskLocal inheritance and nested-scope restoration.

## Accessing Context in Steps

Use the ``Context`` property wrapper to access propagated values:

```swift
struct FetchStep: Step {
    @Context var config: CrawlerConfig

    func run(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = config.timeout
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        // ...
    }
}

struct CrawlStep: Step {
    @Context var config: CrawlerConfig

    func run(_ input: CrawlRequest) async throws -> [URL] {
        guard input.depth < config.maxDepth else { return [] }
        // ...
    }
}
```

## Providing Context

Use the `.context()` modifier to provide context to a Step and all its nested children:

```swift
let config = CrawlerConfig(maxDepth: 5, timeout: 60, userAgent: "MyBot/2.0")

try await CrawlerPipeline()
    .context(config)
    .run(startURL)
```

## Context Propagation Through Nested Steps

Context automatically propagates through the entire Step hierarchy:

```swift
struct CrawlerPipeline: Step {
    var body: some Step<URL, CrawlResult> {
        // All these steps can access @Context var config
        ValidateURLStep()
        FetchStep()
        ParseStep()
        CrawlStep()
    }
}

// Provide context at the top level
try await CrawlerPipeline()
    .context(CrawlerConfig(maxDepth: 10, timeout: 120, userAgent: "DeepCrawler"))
    .run(url)
```

## Multiple Contexts

Chain multiple contexts together:

```swift
struct DatabaseConfig: Contextable {
    let connectionString: String
    static var defaultValue: DatabaseConfig { DatabaseConfig(connectionString: "") }
}

struct LoggingConfig: Contextable {
    let level: LogLevel
    static var defaultValue: LoggingConfig { LoggingConfig(level: .info) }
}

// Provide multiple contexts
try await MyPipeline()
    .context(DatabaseConfig(connectionString: "postgres://..."))
    .context(LoggingConfig(level: .debug))
    .run(input)

// Access in nested Steps
struct DataStep: Step {
    @Context var dbConfig: DatabaseConfig
    @Context var logConfig: LoggingConfig

    func run(_ input: Query) async throws -> Data {
        if logConfig.level == .debug {
            print("Connecting to: \(dbConfig.connectionString)")
        }
        // ...
    }
}
```

## Context with Reference Types

Use an actor for mutable shared state:

```swift
actor WorkspaceContext: Contextable {
    nonisolated let workingDirectory: String
    private var processedFiles: Set<String> = []

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    static var defaultValue: WorkspaceContext {
        WorkspaceContext(workingDirectory: FileManager.default.currentDirectoryPath)
    }

    func processedFileNames() -> [String] {
        processedFiles.sorted()
    }
}

struct CodingAgent: Step {
    @Context var workspace: WorkspaceContext
    @Session var session: LanguageModelSession

    func run(_ task: String) async throws -> String {
        let processedFiles = await workspace.processedFileNames()
        try await session.respond {
            Prompt("""
                Working directory: \(workspace.workingDirectory)
                Already processed: \(processedFiles.joined(separator: ", "))
                Task: \(task)
                """)
        }.content
    }
}

struct CodingPipeline: Step {
    var body: some Step<String, String> {
        // All child steps share the same WorkspaceContext instance
        AnalyzeStep()
        CodingAgent()
        ReviewStep()
    }
}

// Usage
let workspace = WorkspaceContext(workingDirectory: "/path/to/project")
try await CodingPipeline()
    .context(workspace)
    .run("Implement user authentication")
```

## Hierarchical Context Pattern

Build complex hierarchies where each level can access shared context:

```swift
struct MainOrchestrator: Step {
    var body: some Step<ProjectRequest, ProjectResult> {
        // Level 1: Project analysis
        ProjectAnalyzer()

        // Level 2: Multi-agent processing
        Parallel {
            CodeAgent()      // Can access project context
            TestAgent()      // Can access project context
            DocAgent()       // Can access project context
        }

        // Level 3: Integration
        IntegrationStep()
    }
}

// Each agent can have its own nested Steps that also access context
struct CodeAgent: Step {
    @Context var project: ProjectContext

    var body: some Step<AnalysisResult, CodeResult> {
        PlanStep()           // @Context var project works here
        ImplementStep()      // @Context var project works here
        ValidateStep()       // @Context var project works here
    }
}

// Provide context at the entry point
try await MainOrchestrator()
    .context(ProjectContext(name: "MyApp", path: "/projects/myapp"))
    .run(request)
```

## Manual ContextKey Definition

For advanced use cases, define ``ContextKey`` manually:

```swift
enum URLTrackerContext: ContextKey {
    @TaskLocal private static var _current: URLTracker?

    static var defaultValue: URLTracker { URLTracker() }

    static var current: URLTracker { _current ?? defaultValue }

    static func withValue<T: Sendable>(
        _ value: URLTracker,
        operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

// Make URLTracker contextable
extension URLTracker: Contextable {
    static var defaultValue: URLTracker { URLTracker() }

    static var current: URLTracker { URLTrackerContext.current }

    static func withValue<T: Sendable>(
        _ value: URLTracker,
        operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await URLTrackerContext.withValue(value, operation: operation)
    }
}
```

## Topics

### Core Types

- ``Context``
- ``ContextKey``
- ``ContextValueKey``
- ``Contextable``
- ``ContextStep``
