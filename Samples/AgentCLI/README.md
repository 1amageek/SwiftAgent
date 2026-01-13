# SwiftAgent CLI

A command-line interface demonstrating SwiftAgent with OpenAI and Claude integration.

## Features

- **Multiple Agent Types**: Chat, Coding, and Research agents
- **Multi-Provider Support**: OpenAI (GPT-4.1, o3, o4) and Claude (Sonnet 4.5, Opus 4.5, Haiku 4.5)
- **Tool Integration**: File operations, shell commands, Git, web fetching
- **Structured Output**: Research agent with comprehensive structured results
- **Interactive Mode**: Continuous chat sessions with conversation history
- **Streaming Output**: Real-time response streaming for all agents

## Requirements

- macOS 26+ / iOS 26+
- Swift 6.2+
- OpenAI API key (for Chat and Code commands)
- Anthropic API key (for Research command)

## Setup

### 1. Install Dependencies

```bash
cd Samples/AgentCLI
swift package resolve
```

### 2. Set API Keys

```bash
# For Chat and Code commands
export OPENAI_API_KEY="your_openai_api_key"

# For Research command
export ANTHROPIC_API_KEY="your_anthropic_api_key"
```

### 3. Build the CLI

```bash
swift build -c release
```

## Usage

### Chat Command

Interactive conversational AI:

```bash
# Interactive mode
.build/release/agent chat

# Single message
.build/release/agent chat "What is SwiftUI?"

# With specific model
.build/release/agent chat --model gpt-4.1-mini "Hello"
```

### Code Command

Coding assistant with file and command access:

```bash
# Single task
.build/release/agent code "Create a Swift function to parse JSON"

# Interactive mode
.build/release/agent code

# With working directory
.build/release/agent code --working-dir /path/to/project "Refactor this code"
```

**Available Tools:**
- `Read` / `Write` / `Edit`: File operations
- `Glob` / `Grep`: File search
- `Bash`: Shell command execution
- `Git`: Git operations

### Research Command (Claude-powered)

Comprehensive research with structured output:

```bash
# Basic research
.build/release/agent research "Latest developments in Swift concurrency"

# JSON output
.build/release/agent research --json "AI trends 2025"

# With specific Claude model
.build/release/agent research --model claude-opus-4-5-20251101 "Quantum computing applications"
```

**Output Includes:**
- Executive Summary
- Key Findings with confidence levels
- Sources with reliability assessment
- Methodology
- Limitations
- Follow-up questions

## Command Options

### Global Options (Chat & Code)

| Option | Description |
|--------|-------------|
| `--model, -m` | Model to use (default: gpt-4.1) |
| `--api-key` | OpenAI API key |
| `--working-dir, -w` | Working directory for file operations |
| `--verbose, -v` | Enable verbose logging |

### Research Options

| Option | Description |
|--------|-------------|
| `--model, -m` | Claude model (default: claude-sonnet-4-5-20250929) |
| `--api-key` | Anthropic API key |
| `--working-dir, -w` | Working directory for file operations |
| `--verbose, -v` | Enable verbose logging |
| `--json` | Output raw JSON instead of formatted text |

## Supported Models

### OpenAI Models (Chat & Code)

| Model | Best For |
|-------|----------|
| `gpt-4.1` | General use, balanced performance (default) |
| `gpt-4.1-mini` | Faster, cost-effective |
| `gpt-4.1-nano` | Lightweight tasks |
| `o3` | Complex reasoning |
| `o3-mini` | Reasoning with better speed/cost |
| `o4-mini` | Efficient reasoning |

### Claude Models (Research)

| Model | Best For |
|-------|----------|
| `claude-sonnet-4-5-20250929` | Balanced research (default) |
| `claude-opus-4-5-20251101` | Comprehensive analysis |
| `claude-haiku-4-5-20251001` | Quick research |

## Examples

### Chat Examples

```bash
# Quick question
.build/release/agent chat "Explain async/await in Swift"

# Start interactive session
.build/release/agent chat
```

### Coding Examples

```bash
# Code generation
.build/release/agent code "Write a unit test for a User model"

# Code review
.build/release/agent code "Review the code in src/main.swift and suggest improvements"

# Refactoring
.build/release/agent code --working-dir ./myproject "Refactor the API client to use async/await"
```

### Research Examples

```bash
# Technical research
.build/release/agent research "Compare SwiftUI vs UIKit performance"

# Market analysis
.build/release/agent research "Mobile app development trends in 2025"

# With JSON output for processing
.build/release/agent research --json "Swift Package Manager best practices" > research.json
```

## Architecture

This CLI demonstrates key SwiftAgent patterns:

### ChatAgent
- `@Session` for TaskLocal session propagation
- `GenerateText` with streaming handler
- Simple step composition

### CodingAgent
- `@Memory` for state sharing (completedTasks, modifiedFiles)
- `Pipeline` and `Gate` for flow control
- `AgentTools` integration
- Streaming output

### ResearchAgent
- Claude-powered with structured output
- `@Generable` for type-safe results (ResearchResult, KeyFinding, Source)
- `@Guide` annotations for field descriptions
- Multi-phase pipeline with validation

## Troubleshooting

### API Key Issues

```bash
# Check if keys are set
echo $OPENAI_API_KEY
echo $ANTHROPIC_API_KEY

# Use explicit key
.build/release/agent chat --api-key "sk-..." "Hello"
.build/release/agent research --api-key "sk-ant-..." "Topic"
```

### Build Issues

```bash
# Clean and rebuild
swift package clean
swift package resolve
swift build -c release
```

### Verbose Mode

```bash
.build/release/agent --verbose chat "Test"
.build/release/agent research --verbose "Topic"
```

## Development

See the source code in `Sources/AgentCLI/Agents/` for implementation details:

- `ChatAgent.swift`: Simple conversational agent
- `CodingAgent.swift`: Tool-equipped coding assistant
- `ResearchAgent.swift`: Claude-powered structured research

Key SwiftAgent features demonstrated:
- Step protocol and composition
- Session management with TaskLocal
- Memory/Relay for state sharing
- Pipeline and Gate for flow control
- Generate/GenerateText for LLM interaction
- Tool integration with AgentTools
- Structured output with @Generable
