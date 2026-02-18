# Security

Control tool execution with permissions and sandboxing.

## Overview

SwiftAgent provides a layered security system:

```
Tool Request
    │
    ▼
PermissionMiddleware (allow/deny/ask)
    │
    ▼
SandboxMiddleware (sandbox Bash commands)
    │
    ▼
Tool Execution
```

## Quick Start

Apply security using the `.withSecurity()` modifier:

```swift
let config = AgentConfiguration(...)
    .withSecurity(.standard.withHandler(CLIPermissionHandler()))
```

### Presets

| Preset | Permissions | Sandbox |
|--------|-------------|---------|
| `.standard` | Interactive prompts | Local network, working dir write |
| `.development` | Permissive | None |
| `.restrictive` | Minimal (read-only) | No network, read-only |
| `.readOnly` | Read tools only | None |

## Permission Configuration

``PermissionConfiguration`` defines rules for tool execution:

```swift
let config = PermissionConfiguration(
    allow: [
        .tool("Read"),
        .bash("git:*"),
    ],
    deny: [
        .bash("rm -rf:*"),
    ],
    finalDeny: [
        .bash("sudo:*"),  // Cannot be overridden
    ],
    defaultAction: .ask,
    handler: CLIPermissionHandler(),
    enableSessionMemory: true
)
```

### Rule Evaluation Order

```
1. Final Deny     ← Absolute prohibition (cannot bypass)
2. Session Memory ← Remembered "always allow" / "block"
3. Override       ← If matched, skip regular Deny
4. Deny           ← Regular prohibition
5. Allow          ← Permission granted
6. Default Action ← ask / allow / deny
```

### Pattern Syntax

| Pattern | Matches |
|---------|---------|
| `"Read"` | Read tool exactly |
| `"Bash(git:*)"` | git commands (git, git status, git-flow) |
| `"Bash(git status)"` | Exact command |
| `"Write(/tmp/*)"` | Write to /tmp paths |
| `"mcp__*"` | All MCP tools |
| `"mcp__github__*"` | GitHub MCP server tools |

The `prefix:*` pattern requires a separator character (space, dash, tab, etc.) after the prefix. `git:*` matches `git status` but not `gitsomething`.

### Factory Methods

```swift
.tool("Read")           // Tool name
.bash("git:*")          // Bash(git:*)
.write("/tmp/*")        // Write(/tmp/*)
.edit("/src/*")         // Edit(/src/*)
.read("/secrets/*")     // Read(/secrets/*)
.mcp("github")          // mcp__github__*
```

### Loading from File

```swift
// Load from JSON file
let config = try PermissionConfiguration.load(from: configURL)

// Merge configurations
let merged = base.merged(with: override)
```

JSON format:

```json
{
  "version": 1,
  "permissions": {
    "allow": ["Read", "Bash(git:*)"],
    "deny": ["Bash(rm -rf:*)"],
    "finalDeny": ["Bash(sudo:*)"],
    "defaultAction": "ask",
    "enableSessionMemory": true
  }
}
```

## Sandbox Configuration

``SandboxExecutor`` runs commands in a restricted macOS sandbox:

```swift
let sandbox = SandboxExecutor.Configuration(
    networkPolicy: .local,           // none, local, full
    filePolicy: .workingDirectoryOnly,
    allowSubprocesses: true
)
```

### Network Policy

| Policy | Access |
|--------|--------|
| `.none` | No network |
| `.local` | Localhost, LAN only |
| `.full` | Unrestricted |

### File Policy

| Policy | Read | Write |
|--------|------|-------|
| `.readOnly` | All | None |
| `.workingDirectoryOnly` | All | Working dir + tmp |
| `.custom(read:write:)` | Specified paths | Specified paths |

### Presets

```swift
.standard     // Local network, working dir write
.restrictive  // No network, read-only
.permissive   // Full network, working dir write
.none         // Effectively disabled
```

## Guardrail (Declarative Security)

Apply security policies to individual Steps using `.guardrail { }`:

```swift
FetchUserData()
    .guardrail {
        Allow(.tool("Read"))
        Deny(.bash("rm:*"))
        Sandbox(.restrictive)
    }
```

### Rule Types

| Rule | Description |
|------|-------------|
| `Allow(_:)` | Permit operation |
| `Deny(_:)` | Prohibit (can be overridden) |
| `Deny.final(_:)` | Prohibit absolutely |
| `Override(_:)` | Exempt from parent Deny |
| `AskUser()` | Require confirmation |
| `Sandbox(_:)` | Apply sandbox config |

### Network Shortcuts

```swift
.guardrail {
    Deny.network        // No network access
    Allow.localNetwork  // Localhost/LAN only
    Allow.fullNetwork   // Unrestricted
}
```

### Hierarchical Guardrails

Parent guardrails cascade to children. Children can relax rules with `Override`, except for `Deny.final`:

```swift
struct SecureWorkflow: Step {
    var body: some Step<String, String> {
        // Parent denies rm commands
        ProcessStep()
            .guardrail {
                Deny(.bash("rm:*"))
                Deny.final(.bash("rm -rf:*"))  // Absolute
            }

        // Child can override regular Deny
        CleanupStep()
            .guardrail {
                Override(.bash("rm:*.tmp"))    // OK
                Override(.bash("rm -rf:*"))    // Ignored (final)
            }
    }
}
```

### Presets

```swift
.guardrail(.readOnly)      // Read-only access
.guardrail(.standard)      // Standard security
.guardrail(.restrictive)   // Minimal permissions
```

### Conditional Rules

```swift
.guardrail {
    Allow(.tool("Read"))
    if isProduction {
        Deny(.bash("*"))
        Sandbox(.restrictive)
    }
}
```

## Custom Permission Handler

Implement ``PermissionHandler`` for custom approval UI:

```swift
struct MyPermissionHandler: PermissionHandler {
    func requestPermission(
        for request: PermissionRequest
    ) async -> PermissionResponse {
        // Show UI, get user decision
        return .allow  // or .deny, .alwaysAllow, .block
    }
}
```

Response types:

| Response | Effect |
|----------|--------|
| `.allow` | Allow this request |
| `.deny` | Deny this request |
| `.alwaysAllow` | Allow and remember |
| `.block` | Deny and remember |

## Security Configuration

Combine permissions and sandbox into ``SecurityConfiguration``:

```swift
let security = SecurityConfiguration(
    permissions: PermissionConfiguration(
        allow: [.tool("Read"), .bash("git:*")],
        deny: [.bash("rm:*")],
        defaultAction: .ask,
        handler: CLIPermissionHandler()
    ),
    sandbox: .standard
)

let config = AgentConfiguration(...)
    .withSecurity(security)
```

### Builder Methods

```swift
SecurityConfiguration.standard
    .withHandler(MyHandler())
    .withSandbox(.restrictive)
    .allowing(.bash("npm:*"))
    .denying(.bash("curl:*"))
    .withoutSandbox()
```

## Topics

### Configuration

- ``SecurityConfiguration``
- ``PermissionConfiguration``
- ``PermissionRule``
- ``PermissionDecision``

### Sandbox

- ``SandboxExecutor``

### Middleware

- ``PermissionMiddleware``
- ``SandboxMiddleware``

### Guardrail

- ``GuardrailRule``
- ``Allow``
- ``Deny``
- ``Override``
- ``AskUser``
- ``Sandbox``

### Handler

- ``PermissionHandler``
- ``PermissionRequest``
- ``PermissionResponse``
