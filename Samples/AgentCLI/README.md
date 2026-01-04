# SwiftAgent CLI - OpenAI Sample

A command-line interface demonstrating SwiftAgent with OpenAI integration.

## Features

- **Multiple Agent Types**: Choose from different specialized agents
- **OpenAI Integration**: Support for GPT-4o, o1-preview, o1-mini, and GPT-3.5-turbo
- **Tool Integration**: Research agent with web browsing and file system access
- **Structured Output**: Analysis agent with structured data generation
- **Interactive Mode**: Chat-style conversations with AI agents

## Setup

### 1. Install Dependencies

```bash
cd Samples/AgentCLI
swift package resolve
```

### 2. Set OpenAI API Key

Create a `.env` file (copy from `.env.example`):

```bash
cp .env.example .env
```

Edit `.env` and add your OpenAI API key:

```
OPENAI_API_KEY=your_api_key_here
```

Or set it as an environment variable:

```bash
export OPENAI_API_KEY="your_api_key_here"
```

### 3. Build the CLI

```bash
swift build -c release
```

## Usage

### Interactive Mode

Start an interactive chat session:

```bash
.build/release/agent
```

With specific model:

```bash
.build/release/agent --model gpt-4o
```

### Ask Mode

Ask a single question:

```bash
.build/release/agent ask "What is quantum computing?"
```

With different agent types:

```bash
# Basic chat agent (default)
.build/release/agent ask --agent-type basic "Hello, how are you?"

# Research agent with tools
.build/release/agent ask --agent-type research "Research the latest developments in AI"

# Analysis agent with structured output
.build/release/agent ask --agent-type analysis "Analyze the impact of remote work"

# Reasoning agent (optimized for complex problems)
.build/release/agent ask --agent-type reasoning --model o1-preview "Solve this complex math problem: ..."
```

### Command Options

- `--model`: Choose AI model (`gpt-4o`, `o1-preview`, `o1-mini`, `gpt-3.5-turbo`)
- `--api-key`: Specify OpenAI API key (overrides environment variable)
- `--agent-type`: Choose agent type (`basic`, `research`, `analysis`, `reasoning`)
- `--verbose`: Enable verbose logging
- `--quiet`: Show only final answer (ask mode only)

## Agent Types

### Basic Chat Agent
Simple conversational AI for general questions and chat.

```bash
.build/release/agent ask --agent-type basic "Tell me about SwiftUI"
```

### Research Agent
Equipped with tools for web browsing, file operations, and command execution.

```bash
.build/release/agent ask --agent-type research "Research SwiftUI best practices and save findings to a file"
```

**Available Tools:**
- `WebFetch`: Fetch content from web URLs
- `Read`/`Write`: Read/write files
- `Bash`: Run command-line tools

### Analysis Agent
Provides structured analysis with key insights, recommendations, and confidence levels.

```bash
.build/release/agent ask --agent-type analysis "Analyze the pros and cons of microservices architecture"
```

**Output Format:**
- Summary
- Key Insights (3-5 points)
- Recommendations
- Confidence Level

### Reasoning Agent
Optimized for complex problem-solving using OpenAI's o1 models.

```bash
.build/release/agent ask --agent-type reasoning --model o1-preview "Design an algorithm to solve the traveling salesman problem"
```

**Best Models:**
- `o1-preview`: Most capable reasoning model
- `o1-mini`: Faster reasoning model

## Configuration

### Environment Variables

- `OPENAI_API_KEY`: Your OpenAI API key (required)

### Configuration Management

View current configuration:

```bash
.build/release/agent config show
```

Set configuration values:

```bash
.build/release/agent config set instructions "You are a helpful assistant"
.build/release/agent config set loglevel debug
```

Reset to defaults:

```bash
.build/release/agent config reset
```

Export/import configuration:

```bash
.build/release/agent config export config.json
.build/release/agent config import config.json
```

## Examples

### Basic Usage

```bash
# Quick question
.build/release/agent ask "What is SwiftUI?"

# Interactive session
.build/release/agent
```

### Research Tasks

```bash
# Research with web access
.build/release/agent ask --agent-type research "Research the latest Swift 6 features and summarize them"

# Save research to file
.build/release/agent ask --agent-type research "Research AI trends and save summary to ai_trends.md"
```

### Analysis Tasks

```bash
# Structured business analysis
.build/release/agent ask --agent-type analysis "Analyze the market opportunity for a new iOS app"

# Technical analysis
.build/release/agent ask --agent-type analysis "Analyze the performance implications of SwiftUI vs UIKit"
```

### Complex Reasoning

```bash
# Mathematical problems
.build/release/agent ask --agent-type reasoning --model o1-preview "Prove that the sum of angles in a triangle is 180 degrees"

# Algorithm design
.build/release/agent ask --agent-type reasoning "Design an efficient algorithm for finding the shortest path in a weighted graph"
```

## Model Comparison

| Model | Best For | Speed | Cost | Reasoning |
|-------|----------|-------|------|-----------|
| `gpt-4o` | General use, balanced performance | Fast | Medium | Good |
| `gpt-3.5-turbo` | Simple tasks, cost-effective | Very Fast | Low | Basic |
| `o1-preview` | Complex reasoning, mathematics | Slow | High | Excellent |
| `o1-mini` | Reasoning tasks, better speed/cost | Medium | Medium | Very Good |

## Troubleshooting

### API Key Issues

```bash
# Check if API key is set
echo $OPENAI_API_KEY

# Test with explicit API key
.build/release/agent ask --api-key "your_key" "Hello"
```

### Build Issues

```bash
# Clean and rebuild
swift package clean
swift build
```

### Verbose Mode

Enable verbose logging to debug issues:

```bash
.build/release/agent --verbose ask "Test question"
```

## Development

This sample demonstrates:

- SwiftAgent framework integration
- OpenFoundationModels-OpenAI usage
- Multiple agent architectures
- Tool integration patterns
- Structured output generation
- Command-line interface design

See the source code for implementation details and extend with your own agent types.