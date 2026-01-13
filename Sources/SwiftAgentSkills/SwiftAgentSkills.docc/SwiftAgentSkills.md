# ``SwiftAgentSkills``

Extensible skill packages for enhancing agent capabilities.

## Overview

SwiftAgentSkills provides a plugin architecture for extending agent functionality
with reusable, discoverable skill packages.

### Skill Structure

Skills are defined using a `SKILL.md` file with YAML frontmatter:

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

1. Create a `SKILL.md` file with frontmatter
2. Define `allowed-tools` for required permissions
3. Add instructions and examples in markdown
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
