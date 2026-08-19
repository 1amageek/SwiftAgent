# ``AgentTools``

A collection of tools for file operations, search, and command execution.

## Overview

AgentTools provides a set of tools that follow the SwiftAgent naming conventions. These tools enable agents to interact with the file system, execute commands, and perform web operations.

### Available Tools

| Tool | Description |
|------|-------------|
| `Read` | Read file contents |
| `Write` | Write content to files |
| `Edit` | Edit files with string replacement |
| `MultiEdit` | Apply multiple edits atomically |
| `Glob` | Find files matching patterns |
| `Grep` | Search file contents with regex |
| `Bash` | Execute shell commands |
| `Git` | Git operations |
| `WebFetch` | Fetch URL contents |
| `WebSearch` | Web search |

### Using Tools

```swift
// Create tools directly
let tools: [any Tool] = [
    ReadTool(workingDirectory: "/path/to/work"),
    WriteTool(workingDirectory: "/path/to/work"),
    EditTool(workingDirectory: "/path/to/work"),
    MultiEditTool(workingDirectory: "/path/to/work"),
    GlobTool(workingDirectory: "/path/to/work"),
    GrepTool(workingDirectory: "/path/to/work"),
    ExecuteCommandTool(workingDirectory: "/path/to/work"),
    GitTool(),
    URLFetchTool(trustedOrigins: [
        try WebOrigin(scheme: "https", host: "docs.example.com")
    ]),
]
```

`WebFetch` has no unrestricted initializer. The application must inject a
``WebDocumentFetching`` implementation or enumerate exact trusted origins.
Redirects are disabled in the HTTP client and re-authorized by the document
fetcher one hop at a time. A trusted-origin policy is an administrative trust
boundary, accepts HTTPS or loopback HTTP only, and is not DNS pinning;
arbitrary untrusted destinations require a custom endpoint-binding
``WebHTTPClient``.

The default HTTP adapter validates caller headers, drains URLSession
invalidation before cancellation returns, and enforces the body limit while
bytes arrive. Cross-origin redirects discard all caller headers. The bounded
cache is used only for header-free successful requests, rejects `Vary`,
cookie-bearing and private/no-store responses, reauthorizes cached redirect
destinations, and reapplies each caller's body limit.

### Security Integration

Tools integrate with SwiftAgent's permission and sandbox systems through `.guardrail { }` on a Step or by composing a `SecurityConfiguration`:

```swift
// Per-step guardrail
MyAgent()
    .guardrail {
        Allow(.tool("Read"))
        Allow(.tool("Grep"))
        Deny(.bash("rm:*"))
        Sandbox(.standard)
    }

// Or as a SecurityConfiguration
let security = SecurityConfiguration.standard
    .allowing(.tool("Read"))
    .denying(.bash("rm:*"))
```

## Topics

### File Operations

- ``ReadTool``
- ``WriteTool``
- ``EditTool``
- ``MultiEditTool``

### Search

- ``GlobTool``
- ``GrepTool``

### Command Execution

- ``ExecuteCommandTool``
- ``GitTool``

### Web Operations

- ``URLFetchTool``
- ``WebSearchTool``
- ``WebDocumentFetching``
- ``WebURLPolicy``
- ``WebHTTPClient``
