# SwiftAgent I/O and Harness Specification

## 1. Purpose

本仕様は、SwiftAgent の Agent 入出力と Tool Harness を以下の観点で定義する。

- 現在実装されている仕様の明文化
- `stdin/stdout` 依存からの拡張可能な設計方針
- 互換性を維持した段階的移行計画

---

## 2. Scope

本仕様の対象は次のモジュールとサンプル実装。

- Core: `SwiftAgent` (`Step`, `Conversation`, `ToolPipeline`, Security)
- Tools: `AgentTools`
- CLI: `Samples/AgentCLI`

本仕様は LLM モデル実装（OpenAI/Claude SDK の詳細）には踏み込まない。

---

## 3. Current Implementation (As-Is)

### 3.1 Input/Output

- CLI の対話入力は `readLine()` ベース (`WaitForInput`)。
- 出力は `print` による `stdout` ストリーミング。
- インタラクション単位は「文字列入力 -> 文字列出力」が中心。
- `Agent` プロトコルは `Input == String`, `Output == Never`（無限ループ型）を前提とし、出力は `AsyncStream<String>.Continuation` に流す。

### 3.2 Session Runtime

- `Conversation` は `send(_:)`, `input(_:)`, `waitForInput()` を提供。
- 並行送信は内部 `Mutex` で逐次化（FIFO wait queue）。
- `EventBus` に `promptSubmitted` / `responseCompleted` を発行。
- `LanguageModelSession` は TaskLocal (`SessionContext`) で伝搬。

### 3.3 Tool Execution

- 標準ツールは `AgentTools` モジュールが提供 (`ReadTool`, `WriteTool`, `EditTool`, `GrepTool`, `GlobTool`, `ExecuteCommandTool`, `GitTool`, `URLFetchTool` など)。使う側が直接 `[any Tool]` を構築する。
- 実行は `ToolPipeline` によるミドルウェアチェーン。
- `PermissionMiddleware` と `SandboxMiddleware` が主要セキュリティ境界。

### 3.4 Security Model

- 権限は `PermissionConfiguration` で `allow/deny/finalDeny/overrides/defaultAction` を評価。
- 評価順は `finalDeny -> session memory -> overrides -> deny -> allow -> default`。
- `SandboxExecutor` は macOS `sandbox-exec` を使用し、`ExecuteCommandTool` に TaskLocal で注入される。

### 3.5 Current Limitations

- 入出力契約が実質的に CLI (`readLine` + `print`) に強く結合。
- 出力ストリームの意味論が `String` 中心で、構造化イベントが標準化されていない。
- 承認（approval）イベントが I/O プロトコルとして明示されていない。
- CLI 以外（HTTP/SSE/WebSocket/Queue）への展開時に再実装コストが高い。

---

## 4. Target Architecture (To-Be)

### 4.1 Design Principles

- Agent Core をトランスポート非依存にする。
- I/O は「文字列」ではなく「構造化イベント」に統一する。
- Tool 実行境界（権限・sandbox・監査）を Harness に集約する。
- 既存 CLI は最初の Transport Adapter として維持する。

### 4.2 Logical Layers

1. Agent Core  
`Step` / planning / generation。外部 I/O を知らない。

2. Runtime  
`Session`, `Turn`, cancel, timeout, retry, idempotency を管理。

3. Tool Harness  
Tool registry, middleware pipeline, permission, sandbox, audit trail を管理。

4. Transport Adapter  
`Stdio`, `HTTP+SSE`, `WebSocket`, `Queue`, `MCP bridge` を差し替え可能。

### 4.3 Canonical I/O Contract

#### RunRequest

- `session_id: String`
- `turn_id: String`
- `input: InputPayload`
- `context: ContextPayload?`
- `policy: ExecutionPolicy?`
- `metadata: [String: String]?`

#### AgentEvent (stream)

- `run_started`
- `token_delta`
- `tool_call`
- `tool_result`
- `approval_required`
- `approval_resolved`
- `warning`
- `error`
- `run_completed`

#### RunResult

- `session_id: String`
- `turn_id: String`
- `status: completed | failed | cancelled | denied | timed_out`
- `final_output: OutputPayload?`
- `usage: TokenUsage?`
- `tool_trace: [ToolTrace]`
- `error: ErrorPayload?`

### 4.4 Transport Interface

```swift
public protocol AgentTransport: Sendable {
    associatedtype Request: Sendable
    associatedtype Event: Sendable

    func receive() async throws -> Request
    func send(_ event: Event) async throws
    func close() async
}
```

要件:

- Transport は framing/serialization を担当し、Agent Core には渡さない。
- backpressure と cancellation を扱えること。
- half-close（入力終了後に出力継続）に対応できること。

### 4.5 Harness Interface

```swift
public protocol ToolHarness: Sendable {
    func execute(_ call: ToolCall, in context: HarnessContext) async throws -> ToolResult
}
```

要件:

- 全 Tool 呼び出しは Harness 経由を強制。
- `PermissionMiddleware` と `SandboxMiddleware` を Harness の標準構成とする。
- 監査ログ（timestamp, tool, args digest, decision, duration, exit_code）を標準出力可能にする。

---

## 5. Approval and Security Requirements

- `approval_required` イベントは transport 共通で必須。
- 承認応答は `approval_id` で相関づける。
- `defaultAction == .ask` の場合、transport が承認不能なら明示的に `denied` として終了。
- sandbox が利用可能な環境では `ExecuteCommandTool` を原則 sandbox 実行。
- `finalDeny` 違反時は即時失敗し、再試行しない。

---

## 6. Backward Compatibility

- 既存 `Samples/AgentCLI` は `StdioTransport` として温存。
- `WaitForInput` は deprecated 候補とし、新規実装は Transport 経由を推奨。
- 既存 `Step<String, String>` は adapter 層で `InputPayload.text` にマップして継続利用可能にする。

---

## 7. Migration Plan

### Phase 1: Protocol Introduction

- `RunRequest`, `AgentEvent`, `RunResult` を追加。
- `AgentTransport` と `ToolHarness` を導入。
- 既存 CLI を壊さず `StdioTransport` 実装を追加。

### Phase 2: Runtime Consolidation

- `Conversation` のイベントを `AgentEvent` に正規化。
- Tool 実行ログを `tool_trace` に統合。
- 承認フローを `approval_required` / `approval_resolved` で統一。

### Phase 3: Multi-Transport

- `HTTP+SSE` を追加（サーバー/GUI連携用）。
- 必要に応じて `WebSocket` / `Queue` を拡張。

---

## 8. Non-Goals

- 本仕様では UI/UX デザイン（TUI/Web UI）自体は定義しない。
- 本仕様では各 LLM プロバイダ固有パラメータは標準化しない。
- 本仕様では分散エージェント（Symbio）のプロトコルまでは統合しない。

---

## 9. Acceptance Criteria

- CLI が既存同等に動作する（回帰なし）。
- 同一 Agent Core を `StdioTransport` と `HTTP+SSE` の両方で実行可能。
- Tool 実行の全経路が Harness 経由で監査可能。
- 承認が必要なケースで `approval_required` イベントが必ず発行される。
- `finalDeny` は transport を問わず常に優先適用される。

---

## 10. References (Current Code)

- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Agent.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Conversation.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/WaitForInput.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Middleware/ToolPipeline.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Security/PermissionMiddleware.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Security/PermissionConfiguration.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Security/SandboxMiddleware.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/SwiftAgent/Security/SandboxExecutor.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Sources/AgentTools/ExecuteCommandTool.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Samples/AgentCLI/Sources/AgentCLI/AgentCommand.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Samples/AgentCLI/Sources/AgentCLI/Agents/ChatAgent.swift`
- `/Users/1amageek/Desktop/SwiftAgent/Samples/AgentCLI/Sources/AgentCLI/Agents/CodingAgent.swift`
