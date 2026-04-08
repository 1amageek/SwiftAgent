# ``SwiftAgentSkills``

Local-root skill discovery for enhancing agent capabilities.

## Overview

SwiftAgentSkills follows the same discovery-first model as `claw-code`.
Skills are not plugin-managed. They are discovered from local skill roots,
then activated on demand.

### Skill Structure

Skills can be defined either as:

- A directory containing `SKILL.md`
- A legacy markdown file discovered from `commands/` roots

YAML frontmatter is optional. Plain markdown files are also supported.

```markdown
# Git Workflow

Use this when inspecting or modifying git history and branches.
```

Frontmatter remains supported:

```yaml
---
name: git-workflow
description: Git operations workflow
allowed-tools: Bash(git:*) Read Write
---

# Git Workflow Skill

Instructions for using git...
```

### Auto-Discovery

```swift
let config = CodingConfiguration(
    instructions: Instructions("..."),
    skills: .autoDiscover()
)
```

### Discovery Roots

`SkillDiscovery` searches the same categories of roots as `claw-code`:

- Project ancestors: `.claw/skills`, `.omc/skills`, `.agents/skills`,
  `.codex/skills`, `.claude/skills`
- Legacy command roots: `.claw/commands`, `.codex/commands`, `.claude/commands`
- Config-home roots from `CLAW_CONFIG_HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR`
- User roots such as `~/.claw/skills`, `~/.codex/skills`, `~/.claude/skills`

### Permission Integration

Skills can grant tool permissions via the `allowed-tools` field:

```swift
// Skills automatically add to permission allow list
let permissions = SkillPermissions()
let skillTool = SkillTool(registry: registry, permissions: permissions)

// Dynamic permissions from activated skills
let pipeline = basePipeline.withDynamicPermissions { permissions.rules }
```

### Security Model

- `allowed-tools` adds to the allow list only
- Cannot bypass `deny` or `finalDeny` rules
- Reference counting for multiple skill grants

### Creating Custom Skills

1. Create a `SKILL.md` file or legacy markdown command file
2. Define `allowed-tools` for required permissions
3. Add instructions in markdown
4. Place in a discoverable location

## Topics

### Core Types

- ``Skill``
- ``SkillRegistry``
- ``SkillMetadata``

### Discovery

- ``SkillDiscovery``
- ``SkillLoader``

### Permissions

- ``SkillPermissions``

### Tools

- ``SkillTool``

### Configuration

- ``SkillsConfiguration``

### Errors

- ``SkillError``
