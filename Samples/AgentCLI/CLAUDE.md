# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# SwiftAgent Samples - CLI Application Development Guide

## Overview
This directory contains sample applications demonstrating SwiftAgent usage. The main example is AgentCLI, a command-line tool for interacting with AI agents.

## Build & Run Commands

### Building the CLI
```bash
# Build the CLI application
swift build --product AgentCLI

# Build with release configuration
swift build --product AgentCLI -c release

# Run directly
swift run AgentCLI [command] [options]
```

### Common CLI Commands
```bash
# Ask a question to the agent
swift run AgentCLI ask "Your question here"

# Execute with specific model
swift run AgentCLI ask "Question" --model gpt-4o

# Execute with verbose output
swift run AgentCLI ask "Question" --verbose
```

## AgentCLI Architecture

### Main Components
1. **MainAgent**: The core agent that processes user queries with access to tools
2. **Command Structure**: Uses swift-argument-parser for CLI interface
3. **Tool Integration**: Demonstrates FileSystem, Git, Execute, and URLFetch tools

### Agent Implementation Pattern
```swift
struct MainAgent: Agent {
    @StepBuilder
    var body: some Step {
        StringModelStep<String>(session: session) { input in
            UserMessage(input)
        }
    }
    
    var maxTurns: Int { 10 }
}
```

### Session Configuration
The CLI creates a LanguageModelSession with:
- Selected AI model (OpenAI, Anthropic, etc.)
- System instructions
- Available tools
- Optional guardrails

## Development Workflow

### Adding New Features
1. Extend the MainAgent with new steps
2. Add command-line options via ArgumentParser
3. Test with different model providers

### Testing Commands
```bash
# Test file operations
swift run AgentCLI ask "List all Swift files in the current directory"

# Test code generation
swift run AgentCLI ask "Create a simple TODO list manager in Swift"

# Test with specific working directory
swift run AgentCLI ask "Analyze this codebase" --working-dir /path/to/project
```

### Debugging
- Use `--verbose` flag for detailed output
- Check tool execution logs
- Monitor API calls and responses

## Important Implementation Notes

### Tool Access
The MainAgent has access to:
- **FileSystemTool**: Read/write files within working directory
- **ExecuteCommandTool**: Run shell commands
- **GitTool**: Git operations
- **URLFetchTool**: HTTP requests

### Safety Features
- Working directory restrictions for file operations
- Command execution timeout limits
- Input validation via guardrails

### Model Provider Setup
Ensure environment variables are set:
```bash
export OPENAI_API_KEY="your-key"
export ANTHROPIC_API_KEY="your-key"
```

## Common Patterns

### Multi-step Tasks
```swift
StringModelStep<String>(session: session) { input in
    UserMessage(input)
}
Loop(maxIterations: 5) { context in
    // Process iteratively
}
```

### Error Handling
- Tool errors are reported back to the model
- The agent can retry with different approaches
- Graceful degradation when tools fail

## Extending the CLI

### Adding New Commands
1. Create a new ParsableCommand struct
2. Implement the run() method
3. Add to the main command configuration

### Adding New Tools
1. Implement the OpenFoundationModels.Tool protocol
2. Add to the session's tools array
3. Test tool integration

## Testing the CLI
```bash
# Run with test inputs
echo "List files" | swift run AgentCLI ask -

# Test error handling
swift run AgentCLI ask "Delete system files" # Should be blocked by safety checks

# Test tool combinations
swift run AgentCLI ask "Create a git commit with recent changes"
```