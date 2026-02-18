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

### Using the Tool Provider

```swift
let provider = AgentToolsProvider(workingDirectory: "/path/to/work")

// Get all tools
let tools = provider.allTools()

// Get specific tools
let readTool = provider.tool(named: "Read")

// Use presets
let defaultTools = provider.tools(for: ToolConfiguration.ToolPreset.default.toolNames)
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

### Tool Provider

- ``AgentToolsProvider``
- ``ToolConfiguration``

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
