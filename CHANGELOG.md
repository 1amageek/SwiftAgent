# Changelog

All notable changes to SwiftAgent are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-05-01

SwiftAgent 2.0 is a major release that reshapes the pipeline type system,
splits the runtime into focused modules, and ships several new high-level
subsystems (Symbio affordance runtime, agent workflow runtime, progressive
tool/skill disclosure, MCP server hosting).

### Breaking Changes

- **Pipeline `String` → `Prompt` migration.** All pipeline entry points and
  built-in steps (`Generate`, `GenerateText`, `Conversation`, …) now flow
  `Prompt` values rather than raw `String`s, enabling multimodal payloads.
  Call sites that previously passed `String` must wrap the input in
  `Prompt(...)` (or rely on the literal-conversion conformance where
  available).
- **`Conversation` API redesign.** `Conversation` now wraps an
  externally-owned `LanguageModelSession` and a typed step pipeline:
  `init<S: Step & Sendable>(id:languageModelSession:step:) where S.Input == Prompt, S.Output == String`.
  The previous `Conversation(tools:)`, `replaceSession(...)`, and
  `Conversation.restore(from:tools:)` entry points have been removed.
  Persistence is now expressed through `SessionSnapshot` /
  `SessionStore` (`FileSessionStore`, `InMemorySessionStore`).
- **Runtime modules refactored.** MCP, skills, and plugins were split out and
  reorganized into dedicated runtime pipelines. Several internal types were
  renamed or removed; consult the per-module documentation catalogs for the
  current surface.
- **MCP SDK switched from internal fork to upstream.** SwiftAgentMCP now
  depends on `modelcontextprotocol/swift-sdk` 0.12.0 instead of the
  previously vendored fork. Existing MCP client/transport configuration
  continues to work, but downstream code that imported fork-specific symbols
  must migrate to the upstream API.
- **`LanguageModelSessionDelegate` removed.** The session-replacement hook
  is gone; the new `Conversation` model passes a session in directly and
  uses `SessionStore` for persistence.

### Added

- **`MCPServer` protocol and `@ToolsBuilder`** in `SwiftAgentMCP` for
  hosting agent tools as standalone MCP servers, with a default
  stdio-based `main()` entry point.
- **`ToolSearchTool` progressive disclosure gateway** that exposes a small
  set of gateway tools to the model and lets it search/load the rest on
  demand — designed for agents with very large tool catalogs.
- **`AgentWorkflowExecutor` / `AgentWorkflowPlan` runtime** for
  multi-step, policy-aware workflow execution with status reporting
  (`AgentWorkflowStep`, `AgentWorkflowResult`, `AgentWorkflowPolicy`,
  `AgentWorkflowStatus`).
- **`ToolRuntime` / `ToolRuntimeConfiguration`**, a middleware-driven tool
  dispatcher that unifies permission, sandbox, hook, and dynamic-permission
  handling across tools.
- **SwiftAgentSymbio affordance runtime.** New types covering the
  affordance / capability split: `Affordance`, `RoutePlan`,
  `PolicyDecision`/`PolicyDecisionState`, `ParticipantDescriptor`,
  `ParticipantView`, plus `Communicable` / `Terminatable` / `Replicable`
  protocols and the `SymbioRuntime` lifecycle (`runtime.start()`).
- **`SwiftAgentSymbioPeerConnectivity` adapter.**
  `PeerConnectivitySymbioTransport` bridges a `PeerConnectivitySession`
  to the `SymbioTransport` boundary, with versioned default protocol IDs
  (`/swiftagent/symbio/invoke/1.0.0`,
  `/swiftagent/symbio/descriptor/1.0.0`).
- **`SkillRuntime` progressive skill disclosure.**
  `SkillRuntime.prepare(.autoDiscover())` returns a snapshot exposing
  `runtime.tools` (including `activate_skill`/`SkillTool`),
  `runtime.instructions` (skill catalog prompt), and
  `runtime.applying(to:)` for wiring grants into a
  `ToolRuntimeConfiguration` via dynamic permissions.
- **Plain-markdown skill format.** `SKILL.md` directories and legacy
  command files no longer require YAML frontmatter; bare markdown is
  treated as activation instructions.
- **Reasoning delta streaming** for incremental visibility into model
  reasoning during generation.
- **DocC catalogs** for `SwiftAgentPlugins` and
  `SwiftAgentSymbioPeerConnectivity`. Existing catalogs
  (`SwiftAgent`, `SwiftAgentMCP`, `SwiftAgentSymbio`, `SwiftAgentSkills`,
  `AgentTools`) were rewritten against the 2.0 API surface, including the
  `Prompt`-based pipelines and the new `Conversation` model.
- **CI workflow** running `swift test` against macOS 26 in both the
  default (Apple FoundationModels) and `--traits OpenFoundationModels`
  configurations.

### Changed

- **`SwiftAgent` core** evolved alongside the pipeline migration:
  steps now operate on `Prompt`/typed payloads, and the declarative
  `body`-based composition is the recommended authoring pattern.
- **Security model** centralized around `SecurityConfiguration`,
  `PermissionConfiguration`, and `SandboxExecutor.Configuration`. Per-step
  policy is applied via the `.guardrail { ... }` modifier with
  `Allow` / `Deny` / `Deny.final` / `Override` / `AskUser` / `Sandbox`
  rules; presets `.standard`, `.development`, `.restrictive`, `.readOnly`
  are exposed directly on `SecurityConfiguration`.
- **MCP tool naming** is now the colon-separated form
  `mcp:servername:toolname`, aligned with upstream MCP conventions.

### Dependencies

- `OpenFoundationModels` 1.18.0 (trait-gated alternative to Apple
  FoundationModels)
- `swift-actor-runtime` 0.2.0
- `swift-skills` 0.2.1
- `swift-peer-connectivity` 0.1.1
- `modelcontextprotocol/swift-sdk` 0.12.0

### Platform Requirements

- Swift 6.2 toolchain
- iOS 26.0+ / macOS 26.0+
