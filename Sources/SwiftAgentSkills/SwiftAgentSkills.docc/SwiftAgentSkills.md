# ``SwiftAgentSkills``

Local-root skill discovery and progressive skill disclosure for SwiftAgent agents.

## Overview

`SwiftAgentSkills` follows the same discovery-first model as `claw-code` /
`claude-code`. Skills are not plugin-managed — they are discovered from local
skill roots and activated on demand by the model through the
``SkillTool``/`activate_skill` flow. Skills can also extend the agent's
permission set via the YAML `allowed-tools` field.

### Skill Structure

Skills can be defined either as:

- A directory containing `SKILL.md`
- A legacy markdown file discovered from `commands/` roots

YAML frontmatter is optional. Plain markdown files are also supported as of 2.0:

```markdown
# Git Workflow

Use this when inspecting or modifying git history and branches.
```

Frontmatter is supported for permission grants and metadata:

```yaml
---
name: git-workflow
description: Git operations workflow
allowed-tools: Bash(git:*) Read Write
---

# Git Workflow Skill

Instructions for using git…
```

### Auto-Discovery and Runtime Preparation

A typical setup uses ``SkillRuntime/prepare(_:cwd:permissions:)`` to assemble a snapshot containing the registry, permissions, and the prompt fragment that lists available skills:

```swift
import SwiftAgentSkills

let runtime = try await SkillRuntime.prepare(.autoDiscover())

let session = LanguageModelSession(
    model: .default,
    tools: runtime.tools  // includes activate_skill (SkillTool)
) {
    Instructions("You are a coding assistant.")
    runtime.instructions  // injects <skill_policy> + skill catalog
}
```

The model first sees only the skill catalog. When it picks a skill, it calls `activate_skill`, the runtime returns the full instructions, and any `allowed-tools` from the chosen skill are added to the dynamic permission set.

### Discovery Roots

``SkillDiscovery`` searches the same categories of roots as `claw-code`:

- Project ancestors: `.claw/skills`, `.omc/skills`, `.agents/skills`,
  `.codex/skills`, `.claude/skills`
- Legacy command roots: `.claw/commands`, `.codex/commands`, `.claude/commands`
- Config-home roots from `CLAW_CONFIG_HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR`
- User roots such as `~/.claw/skills`, `~/.codex/skills`, `~/.claude/skills`

`AGENT_SKILLS_PATH` adds extra search roots.

### Permission Integration

Skills can grant tool permissions via the `allowed-tools` field. ``SkillRuntime`` wires those grants into a `ToolRuntimeConfiguration` (from `SwiftAgent`) through dynamic permissions:

```swift
let configuration = ToolRuntimeConfiguration.standard
let configured = runtime.applying(to: configuration)
let toolRuntime = ToolRuntime(configuration: configured, tools: runtime.tools)
```

Internally this calls `withDynamicPermissions { permissions.rules }`, so each tool invocation re-reads the rules and respects skills activated in the same session.

### Security Model

- `allowed-tools` adds to the **allow** list only.
- It cannot bypass `deny` or `finalDeny` rules.
- Reference counting handles overlapping grants from multiple skills.

### Authoring a Skill

1. Create a `SKILL.md` directory layout, or a legacy markdown command file.
2. Add YAML frontmatter with `name`, `description`, and optionally `allowed-tools`.
3. Write the body in markdown — this becomes the activation instructions.
4. Place the skill in any discoverable root (or set `AGENT_SKILLS_PATH`).

## Topics

### Runtime

- ``SkillRuntime``
- ``SkillsConfiguration``

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

### Errors

- ``SkillError``
