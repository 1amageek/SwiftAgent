# State Management

Choose the right state sharing mechanism for your Step pipelines.

## Overview

SwiftAgent provides two mechanisms for sharing state across Steps:

| Mechanism | Propagation | Use Case |
|-----------|-------------|----------|
| ``Memory`` / ``Relay`` | Explicit (parameter passing) | Mutable state shared between parent and child |
| ``Context`` | Implicit (TaskLocal) | Configuration or services accessed deep in hierarchy |

## Memory and Relay

``Memory`` stores mutable state with reference semantics. Use the `$` prefix to get a ``Relay`` for passing to child Steps.

```swift
struct Orchestrator: Step {
    @Memory var visitedURLs: Set<URL> = []
    @Memory var results: [CrawlResult] = []

    func run(_ input: URL) async throws -> [CrawlResult] {
        // Pass Relay to child - child can read and write
        try await CrawlStep(visited: $visitedURLs, results: $results)
            .run(input)
        return results
    }
}

struct CrawlStep: Step {
    let visited: Relay<Set<URL>>
    let results: Relay<[CrawlResult]>

    func run(_ url: URL) async throws -> Void {
        guard !visited.contains(url) else { return }
        visited.insert(url)

        let data = try await fetch(url)
        results.append(CrawlResult(url: url, data: data))
    }
}
```

**Characteristics:**
- Explicit: Parent must pass Relay to child
- Bidirectional: Child can read and write
- Local scope: Only Steps with the Relay can access
- Mutable: Designed for accumulating or modifying state

## Context

``Context`` propagates values through TaskLocal storage. Child Steps access values without explicit parameter passing.

```swift
@Contextable
struct CrawlerConfig {
    let maxDepth: Int
    let timeout: TimeInterval

    static var defaultValue: CrawlerConfig {
        CrawlerConfig(maxDepth: 3, timeout: 30)
    }
}

struct CrawlerPipeline: Step {
    var body: some Step<URL, CrawlResult> {
        ValidateStep()
        FetchStep()
        ParseStep()
    }
}

struct FetchStep: Step {
    @Context var config: CrawlerConfig  // No parameter needed

    func run(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = config.timeout
        // ...
    }
}

// Provide at entry point
try await CrawlerPipeline()
    .context(CrawlerConfig(maxDepth: 10, timeout: 60))
    .run(url)
```

**Characteristics:**
- Implicit: Automatically available in nested Steps
- Read-only pattern: Typically for configuration
- Global scope: Any Step in the hierarchy can access
- Immutable: Value set at entry point, read throughout

## When to Use Each

### Use Memory/Relay when:

- **Accumulating results** during processing
- **Tracking visited items** to avoid duplicates
- **Counting or aggregating** values
- **State changes** as Steps execute

```swift
// Accumulating results
@Memory var findings: [Issue] = []
try await AnalyzeStep(findings: $findings).run(code)

// Tracking progress
@Memory var processedCount: Int = 0
$processedCount.increment()
```

### Use Context when:

- **Configuration** that doesn't change during execution
- **Services** (database connections, API clients)
- **Environment** (working directory, credentials)
- **Deep nesting** where passing parameters is cumbersome

```swift
// Configuration
@Context var config: AppConfig

// Services
@Context var database: DatabaseService

// Environment
@Context var workspace: WorkspaceInfo
```

## Combining Both

Use both mechanisms together for complex pipelines:

```swift
@Contextable
struct ProjectConfig {
    let projectPath: String
    let maxIssues: Int
    static var defaultValue: ProjectConfig { ... }
}

struct AnalysisPipeline: Step {
    @Memory var issues: [Issue] = []  // Mutable accumulator

    var body: some Step<String, AnalysisReport> {
        // Scan and accumulate issues
        ScanStep(issues: $issues)

        // Filter based on config
        FilterStep(issues: $issues)

        // Generate report
        ReportStep(issues: $issues)
    }
}

struct ScanStep: Step {
    let issues: Relay<[Issue]>
    @Context var config: ProjectConfig  // Read-only config

    func run(_ input: String) async throws -> String {
        let scanner = Scanner(path: config.projectPath)
        for issue in scanner.scan() {
            if issues.wrappedValue.count < config.maxIssues {
                issues.append(issue)
            }
        }
        return input
    }
}

// Usage
try await AnalysisPipeline()
    .context(ProjectConfig(projectPath: "/src", maxIssues: 100))
    .run("analyze")
```

## Summary

| Aspect | Memory/Relay | Context |
|--------|--------------|---------|
| Passing | Explicit (parameter) | Implicit (TaskLocal) |
| Direction | Read/Write | Read-only (typically) |
| Scope | Steps with Relay | Entire hierarchy |
| Purpose | Mutable state | Configuration/Services |
| Definition | `@Memory var x = ...` | `@Contextable struct` |
| Access | `$x` for Relay | `@Context var x` |

## Topics

### State Management

- ``Memory``
- ``Relay``

### Context System

- ``Context``
- ``ContextKey``
- ``Contextable``
