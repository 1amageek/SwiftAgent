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
    URLFetchTool(),
]
```

### Security Integration

Tools integrate with SwiftAgent's permission and sandbox systems:

```swift
let config = AgentConfiguration(...)
    .withSecurity(.standard)

// Permission rules
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
