# SwiftAgent

Apple FoundationModelsを基盤とした型安全で宣言的なAIエージェントフレームワーク。

> **Note**: デフォルトはApple FoundationModelsを使用。`--traits OpenFoundationModels` で OpenFoundationModels に切り替え可能。

## コア概念

| 概念 | 説明 |
|------|------|
| **Step** | `Input -> Output` の非同期変換単位。`run(_:)` を直接実装するか、`body` を定義して宣言的に合成 |
| **Session** | TaskLocalベースのセッション伝播（`@Session`, `.session()`） |
| **Memory/Relay** | Step間の状態共有（`@Memory` で保持、`$` で `Relay` を取得） |
| **Context** | 汎用TaskLocal伝播（`@Contextable`, `@Context`, `.context()`） |
| **Generate** | LLMによる構造化出力生成 |

## Step 一覧

| 種別 | Steps |
|------|-------|
| プリミティブ | `Transform`, `Generate`, `GenerateText`, `EmptyStep`, `Join`, `Gate` |
| 合成 | `Chain2-8`, `Pipeline`, `Parallel`, `Race`, `Loop`, `Map`, `Reduce` |
| 修飾 | `Monitor`, `TracingStep`, `AnyStep` |

## 基本パターン

```swift
// Session伝播（TaskLocal経由で自動伝播）
struct MyStep: Step {
    @Session var session: LanguageModelSession
    func run(_ input: String) async throws -> String {
        try await session.respond { Prompt(input) }.content
    }
}
try await MyStep().session(session).run("Hello")

// Memory/Relay による状態共有
struct OrchestratorStep: Step {
    @Memory var visitedURLs: Set<URL> = []  // 状態を保持

    func run(_ input: Query) async throws -> Result {
        // $visitedURLs で Relay を取得し、子Stepに渡す
        try await CrawlStep(visited: $visitedURLs).run(input.startURL)
    }
}

struct CrawlStep: Step {
    let visited: Relay<Set<URL>>  // 親からRelayを受け取る

    func run(_ input: URL) async throws -> CrawlResult {
        if visited.contains(input) { return .alreadyVisited }
        visited.insert(input)
        // クロール処理...
    }
}

// Context による汎用TaskLocal伝播（@Contextable マクロで簡潔に定義）
@Contextable
struct AppConfig: Contextable {
    static var defaultValue: AppConfig { AppConfig(maxRetries: 3) }
    let maxRetries: Int
}

struct MyStep: Step {
    @Context var config: AppConfig  // 型から自動でContextKeyを解決
    func run(_ input: String) async throws -> String { /* config.maxRetries を使用 */ }
}
try await MyStep().context(AppConfig(maxRetries: 5)).run("input")

// Step による宣言的な合成（body を定義すると run が自動実装）
struct TextPipeline: Step {
    @Session var session: LanguageModelSession
    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText(session: session) { Prompt($0) }
    }
}

// 構造化出力
@Generable struct Output: Sendable {
    @Guide(description: "説明") let field: String
}
let step = Generate<String, Output>(session: session) { Prompt($0) }

// Tool定義（Arguments は @Generable、Output は不要）
struct MyTool: Tool {
    typealias Arguments = MyInput  // @Generable 必須
    let name = "my_tool"
    let description = "説明"
    func call(arguments: MyInput) async throws -> MyOutput { ... }
}
```

## Memory / Relay

Step間で状態を共有するためのプロパティラッパー。

| 型 | 用途 |
|---|------|
| `@Memory<Value>` | 値を参照型ストレージに保持。`$` で `Relay` を取得 |
| `Relay<Value>` | getter/setter クロージャによる間接アクセス |

```swift
// 基本的な使い方
@Memory var counter: Int = 0
counter += 1              // 値の変更
let relay = $counter      // Relay を取得
relay.wrappedValue = 10   // Relay 経由で変更

// コレクション拡張
@Memory var urls: Set<URL> = []
$urls.insert(url)         // Relay.insert
$urls.contains(url)       // Relay.contains
$urls.formUnion(newURLs)  // Relay.formUnion

@Memory var items: [String] = []
$items.append("item")     // Relay.append

// Int 拡張
@Memory var count: Int = 0
$count.increment()        // count += 1
$count.decrement()        // count -= 1
$count.add(5)             // count += 5

// Relay 変換
let doubled = $counter.map({ $0 * 2 }, reverse: { $0 / 2 })
let readOnly = $counter.readOnly { $0 * 2 }

// 定数 Relay
let constant = Relay<Int>.constant(42)  // 書き込み無視
```

## Pipeline / Gate

Stepの宣言的な合成とフロー制御を提供する。

| 型 | 用途 |
|---|------|
| `Pipeline` | `@StepBuilder` でStepを順番に実行するコンテナ |
| `Gate` | 入力を変換またはブロックするStep |
| `GateResult` | `.pass(value)` で続行、`.block(reason:)` で中断 |

```swift
// 基本的な Pipeline + Gate
Pipeline {
    // 入口ゲート：検証・変換
    Gate { input in
        guard !input.isEmpty else {
            return .block(reason: "Empty input")
        }
        return .pass(input.lowercased())
    }

    // メイン処理
    MyAgent()

    // 出口ゲート：後処理
    Gate { output in
        .pass(output.trimmingCharacters(in: .whitespaces))
    }
}

// 宣言的Step内での使用（body は既に @StepBuilder なので Pipeline 不要）
struct SecurePipeline: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        Gate { input in .pass(sanitize(input)) }
        GenerateText(session: session) { Prompt($0) }
        Gate { output in .pass(filterSensitive(output)) }
    }
}

// Pipeline が必要なケース：宣言的Stepの外で Step を合成
let step = Pipeline {
    Gate { .pass(validate($0)) }
    MyProcessingStep()
}
try await step.run(input)

// Gate ファクトリメソッド
Gate<String, String>.passthrough()           // 入力をそのまま通す
Gate<String, String>.block(reason: "Blocked") // 常にブロック
```

**GateError:**
- `GateError.blocked(reason:)` - ゲートがブロックした場合にスロー

## Event

型安全なイベント発火システム。`Notification.Name` 風の `EventName` と `@Context` で伝播する `EventBus` を使用。

| 型 | 用途 |
|---|------|
| `EventName` | 型安全なイベント名（`Notification.Name` 風） |
| `EventBus` | イベントの発火とリスナー管理（`@Contextable`） |
| `EventTiming` | `.before` / `.after` - イベント発火タイミング |

```swift
// イベント名の定義（アプリ側）
extension EventName {
    static let sessionStarted = EventName("sessionStarted")
    static let sessionEnded = EventName("sessionEnded")
}

// Step の .emit() モディファイア
MyStep()
    .emit(.sessionStarted, on: .before)  // 実行前に発火
    .emit(.sessionEnded, on: .after)     // 実行後に発火（デフォルト）

// ペイロード付き
MyStep()
    .emit(.completed) { output in output }  // output をペイロードに

// EventBus のセットアップと使用
let eventBus = EventBus()
await eventBus.on(.sessionStarted) { payload in
    print("Started: \(payload.value ?? "")")
}

try await MyAgent()
    .context(eventBus)
    .run(input)
```

## Context

TaskLocal経由の汎用コンテキスト伝播システム。Agent（持つ側）からStep（使う側）へ値を伝播する。

### 基本的な使い方

```swift
// 1. @Contextable で型を定義（Contextable準拠は自動追加）
@Contextable
class Library {
    var books: [Book] = []
    var availableCount: Int { books.filter(\.isAvailable).count }

    static var defaultValue: Library { Library() }  // 必須
}

// 2. 宣言的Step（持つ側）で .context() モディファイアで渡す
struct BookReaderPipeline: Step {
    let library = Library()

    var body: some Step<Query, Response> {
        FetchBooksStep()
        AnalyzeStep()
            .context(library)
    }
}

// 3. Step（使う側）で @Context で受け取る
struct AnalyzeStep: Step {
    @Context var library: Library

    func run(_ input: Query) async throws -> Response {
        let count = library.availableCount
        // ...
    }
}
```

### @Contextable マクロ

`@Contextable`を適用すると、自動的に`Contextable`準拠、`{TypeName}Context: ContextKey`、`typealias ContextKeyType`が生成される。

```swift
@Contextable
struct CrawlerConfig {
    let maxDepth: Int
    let timeout: Int

    static var defaultValue: CrawlerConfig {  // 必須
        CrawlerConfig(maxDepth: 3, timeout: 30)
    }
}

// 生成されるコード:
// enum CrawlerConfigContext: ContextKey { ... }
// extension CrawlerConfig: Contextable { typealias ContextKeyType = CrawlerConfigContext }
```

### 複数Contextの連鎖

```swift
try await step
    .context(library)
    .context(config)
    .run(input)
```

### 既存のContextKeyへの対応

手動定義の`ContextKey`を`Contextable`に対応させる場合：

```swift
// 既存のContextKey
enum SandboxContext: ContextKey {
    @TaskLocal private static var _current: SandboxExecutor.Configuration?
    static var defaultValue: SandboxExecutor.Configuration { .none }
    static var current: SandboxExecutor.Configuration { _current ?? defaultValue }
    static func withValue<T: Sendable>(_ value: SandboxExecutor.Configuration, operation: () async throws -> T) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

// Contextable準拠を追加
extension SandboxExecutor.Configuration: Contextable {
    public static var defaultValue: SandboxExecutor.Configuration { .none }
    public typealias ContextKeyType = SandboxContext
}

// これで @Context var config: SandboxExecutor.Configuration が使える
```

## Conversation

スレッドセーフな対話型会話管理クラス。FIFOメッセージキューとsteering機能を提供。

### 基本的な使い方

```swift
// シンプルな初期化（内部で DefaultSessionDelegate を生成）
let conversation = Conversation(tools: myTools) {
    Instructions("You are a helpful assistant.")
}

let response = try await conversation.send("Hello!")
print(response.content)
```

### カスタムデリゲート

セッション置換時のカスタムロジックが必要な場合:

```swift
struct MyDelegate: LanguageModelSessionDelegate {
    let model: SystemLanguageModel
    let tools: [any Tool]

    func createSession(with transcript: Transcript) -> LanguageModelSession {
        LanguageModelSession(model: model, tools: tools, transcript: transcript) {
            Instructions("You are a helpful assistant.")
        }
    }
}

let initialSession = LanguageModelSession(model: .default, tools: myTools) {
    Instructions("You are a helpful assistant.")
}
let conversation = Conversation(initialSession: initialSession, delegate: MyDelegate(model: .default, tools: myTools))
```

### メッセージキュー

複数の `send()` 呼び出しは FIFO で処理される。キャンセルされたタスクは自動的にキューから除去。

```swift
// 順番に処理される
Task { try await conversation.send("First") }
Task { try await conversation.send("Second") }

// キャンセル対応
let task = Task { try await conversation.send("Will be cancelled") }
task.cancel()  // キューから除去され、スロットを消費しない
```

### Steering

`steer()` は **次の** プロンプトにコンテキストを追加する。処理中に追加した場合は「次の次」に反映。

```swift
// send() の前に追加
conversation.steer("Use async/await")
conversation.steer("Add error handling")

let response = try await conversation.send("Write a function...")
// → steering メッセージと "Write a function..." が結合されて送信
```

### セッション置換

`replaceSession()` はいつでも呼び出し可能。処理中でも安全。

```swift
// コンテキスト圧縮後に置換
let compactedTranscript = ...
conversation.replaceSession(with: compactedTranscript)
// 現在処理中のメッセージ → 古いセッションで継続
// 次のメッセージ → 新しいセッションを使用
```

### プロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `transcript` | `Transcript` | 現在の会話履歴 |
| `isResponding` | `Bool` | 処理中かどうか |
| `pendingSteeringCount` | `Int` | 未消費の steering メッセージ数 |

### 内部実装

```
send(content)
  └─ acquireProcessingSlot()
       ├─ idle → resume(true) → processMessage() → releaseProcessingSlot()
       └─ busy → waitQueue.append(waiter)
                  ├─ 順番が来た → resume(true) → processMessage()
                  └─ キャンセル → remove(waiter) → resume(false) → throw CancellationError
```

- **Continuation Queue**: `CheckedContinuation<Bool, Never>` ベースの FIFO 待機
- **セッション参照キャプチャ**: `processMessage()` 開始時にセッションをキャプチャし、mid-processing 置換に対応

## @Generable の制限

- Dictionary 型は未サポート
- enum は未サポート（`@Guide(enumeration:)` を使用）
- 全プロパティに `@Guide` が必須

## モジュール

### Skills
エージェント機能を拡張するポータブルなスキルパッケージ。詳細: [docs/SKILLS_DESIGN.md](Docs/SKILLS_DESIGN.md)

```swift
// スキル自動発見
let config = CodingConfiguration(
    instructions: Instructions("..."),
    skills: .autoDiscover()
)

// スキル活性化時の allowed-tools
// SKILL.md の allowed-tools フィールドが自動的に Permission に適用される
```

**allowed-tools 連携:**

スキルの SKILL.md で `allowed-tools` を指定すると、スキル活性化時に自動的に Permission の allow リストに追加される：

```yaml
---
name: git-workflow
description: Git操作のワークフロー
allowed-tools: Bash(git:*) Read Write
---
```

```swift
// SkillTool と SkillPermissions の連携
let permissions = SkillPermissions()
let skillTool = SkillTool(registry: registry, permissions: permissions)

// PermissionMiddleware に動的ルールを注入
let pipeline = basePipeline.withDynamicPermissions { permissions.rules }
```

**セキュリティ:**
- `allowed-tools` は `allow` リストに追加されるのみ
- `deny` / `finalDeny` ルールはバイパスできない
- 複数スキルが同じ権限を付与した場合、参照カウントで管理

### SwiftAgentMCP
MCP統合モジュール。Claude Code互換。

```swift
// 複数サーバー管理
let manager = try await MCPClientManager.loadDefault()  // .mcp.json から読み込み
let tools = try await manager.allTools()  // mcp__server__tool 形式

// 単一サーバー
let mcpClient = try await MCPClient.connect(config: MCPServerConfig(
    name: "github",
    transport: .stdio(command: "docker", arguments: ["run", "-i", "ghcr.io/github/github-mcp-server"])
))
let mcpTools = try await mcpClient.tools()

// Permission連携
.allowing(.mcp("github"))  // mcp__github__* を許可
```

**ルール:**
- ツール名形式: `mcp__servername__toolname`
- 設定ファイル: `.mcp.json`（環境変数 `${VAR}` 展開対応）
- トランスポート: `.stdio()`, `.http()`, `.sse()`
- MCP SDK: `HTTPClientTransport(streaming: false)` = HTTP, `streaming: true` = SSE

### SwiftAgentSymbio
エージェント間通信と発見の分散システムモジュール。Swift Distributed Actors を使用。

#### レイヤー構成

```
Layer 4: Agent (Communicable = CommunityAgent + SignalReceivable)
    ↓
Layer 3: Community (メンバー管理、spawn/terminate/send)
    ↓
Layer 2: SymbioActorSystem + PeerConnector (Distributed Actor基盤)
    ↓
Layer 1: swift-discovery (トランスポート抽象化)
    ↓
Layer 0: Transport (mDNS/TCP, BLE, HTTP/WebSocket)
```

#### 操作の可否

| 操作 | ローカル | リモート |
|------|:--------:|:--------:|
| spawn | ✅ | ❌ |
| terminate | ✅ | ❌ |
| send | ✅ | ✅ |
| invoke (capability) | ❌ | ✅ |

#### 設計原則

- **perceptions (accepts)**: エージェントが受信できる信号の種類。ローカル/リモート両対応
- **capabilities (provides)**: リモートサービス広告用。ローカルエージェントは `provides: []`
- **changes**: 単一コンシューマー制限（AsyncStream の仕様）

#### プロトコル

```swift
// 通信可能なエージェント（コミュニティ参加 + 信号受信）
public protocol Communicable: DistributedActor
    where ActorSystem == SymbioActorSystem {
    var community: Community { get }
    nonisolated var perceptions: [any Perception] { get }
    distributed func receive(_ data: Data, perception: String) async throws -> Data?
}

// 終了可能なエージェント
public protocol Terminatable: Actor {
    nonisolated func terminate() async
}

// 自己複製可能なエージェント（SubAgent生成用）
public protocol Replicable: Sendable {
    func replicate() async throws -> Member
}
```

#### 内部データフロー

**spawn() フロー:**
```
factory() → actorReady() → ActorRegistry登録 → localAgentRefs保存
    → registerMethod() → memberCache追加 → .joined イベント
```

**terminate() フロー:**
```
Terminatable.terminate() → unregisterMethod() → resignID()
    → ストレージ削除 → .left イベント
```

**send() ローカルフロー:**
```
localAgentIDs確認 → Communicable キャスト → receive() 直接呼び出し
```

**send() リモートフロー:**
```
PeerConnector.invoke() → Transport → リモートピア
```

**リモート受信フロー:**
```
PeerConnector → handleDiscoveryInvocation() → actorID(for:)
    → ActorRegistry.find() → SignalReceivable.receive()
```

#### Community 内部構造

```swift
actor Community {
    // ストレージ
    var memberCache: [String: Member]              // 全メンバー（ローカル+リモート）
    var localAgentIDs: Set<String>                 // ローカルエージェントID
    var localAgentRefs: [String: any DistributedActor]  // エージェント参照（強参照）
    var registeredMethods: [String: [String]]      // エージェントID → メソッド名リスト

    // ID形式: agent.id.hexString (Address の16進文字列表現)
}
```

#### 使用例

```swift
// エージェント定義
distributed actor WorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let community: Community

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        let signal = try JSONDecoder().decode(WorkSignal.self, from: data)
        // 処理...
        return nil
    }

    nonisolated func terminate() async {
        // クリーンアップ...
    }
}

// Community 使用
let actorSystem = SymbioActorSystem()
let community = Community(actorSystem: actorSystem)

// ローカルエージェント起動
let worker = try await community.spawn {
    WorkerAgent(community: community, actorSystem: actorSystem)
}

// 信号送信
try await community.send(WorkSignal(task: "process"), to: worker, perception: "work")

// 検索
let workers = await community.whoCanReceive("work")

// 変更監視（単一コンシューマーのみ）
for await change in await community.changes {
    switch change {
    case .joined(let member): print("Joined: \(member.id)")
    case .left(let member): print("Left: \(member.id)")
    default: break
    }
}

// 終了
try await community.terminate(worker)
```

#### SubAgent Spawning（LLMによる動的エージェント生成）

LLMがタスクの複雑さを判断し、`ReplicateTool`を通じてSubAgentを動的に生成する仕組み。

**フロー:**
```
LLM → ReplicateTool.call() → Replicable.replicate() → Community.spawn()
    → memberCache追加 → .joined イベント → 動的にToolとして利用可能
```

**ReplicateTool:**
```swift
public struct ReplicateTool: Tool {
    public static let name = "replicate_agent"

    private let agent: any Replicable

    public init(agent: any Replicable) {
        self.agent = agent
    }

    public func call(arguments: ReplicateArguments) async throws -> ReplicateOutput {
        let member = try await agent.replicate()
        return ReplicateOutput(success: true, agentID: member.id, accepts: Array(member.accepts), ...)
    }
}

@Generable
public struct ReplicateArguments: Sendable {
    @Guide(description: "Reason for spawning a SubAgent")
    public let reason: String
}
```

**Replicable エージェントの実装:**
```swift
distributed actor WorkerAgent: Communicable, Replicable {
    let community: Community

    func replicate() async throws -> Member {
        try await community.spawn {
            WorkerAgent(community: self.community, actorSystem: self.actorSystem)
        }
    }
}

// LLMセッションでReplicateToolを使用
let session = LanguageModelSession(model: model, tools: [ReplicateTool(agent: workerAgent)]) {
    Instructions {
        "You can spawn helper agents when tasks are complex."
        "Use replicate_agent when you have many TODOs or parallelizable work."
    }
}
```

**LLMの判断基準:**
- タスクに多数のTODOがある場合
- 作業が並列化可能な場合
- 専門的なサブタスク用のヘルパーが必要な場合

#### 主要コンポーネント

| コンポーネント | 責務 |
|---------------|------|
| `Community` | メンバー管理、spawn/terminate、send、変更通知 |
| `SymbioActorSystem` | DistributedActorSystem実装、ActorRegistry統合 |
| `Member` | コミュニティメンバーの情報（id, accepts, provides, isAvailable, metadata） |
| `CommunityChange` | joined, left, updated, becameAvailable, becameUnavailable |
| `Communicable` | 通信可能なエージェント（community, perceptions, receive） |
| `Replicable` | 自己複製可能なエージェント（Sendable継承、柔軟な型サポート） |
| `ReplicateTool` | LLMがSubAgentを生成するためのツール |

#### SymbioActorSystem 内部構造

```swift
final class SymbioActorSystem: DistributedActorSystem {
    let actorRegistry: ActorRuntime.ActorRegistry  // アクター登録（swift-actor-runtime）
    let methodActors: Mutex<[String: Address]>     // メソッド名 → ActorID マッピング
    var peerConnector: PeerConnector?              // リモート通信用

    // DistributedActorSystem 必須メソッド
    func actorReady(_:)    // ActorRegistry に登録
    func resignID(_:)      // ActorRegistry から削除
    func remoteCall(...)   // ローカル実行 or エラー（リモートは Community 経由）
}
```

#### 依存ライブラリ

- `swift-actor-runtime`: ActorRegistry、InvocationEncoder/Decoder、ResultHandler
- `swift-discovery`: PeerConnector、Transport、CapabilityID

## AgentTools

Claude Code スタイルのツール名を採用。

| ツール名 | 説明 |
|---------|------|
| `Read` | ファイル読み込み |
| `Write` | ファイル書き込み |
| `Edit` | ファイル編集（文字列置換） |
| `MultiEdit` | 複数編集のアトミック適用 |
| `Glob` | ファイルパターン検索 |
| `Grep` | 正規表現による内容検索 |
| `Bash` | シェルコマンド実行 |
| `Git` | Git操作 |
| `WebFetch` | URL内容取得 |
| `WebSearch` | Web検索 |

```swift
// ツールプロバイダーの使用
let provider = AgentToolsProvider(workingDirectory: "/path/to/work")
let tools = provider.allTools()

// 特定のツールを取得
if let readTool = provider.tool(named: "Read") {
    // ...
}

// プリセットの使用
let defaultTools = provider.tools(for: ToolConfiguration.ToolPreset.default.toolNames)
```

## Security

ツール実行に対するパーミッションとサンドボックスを提供。詳細: [docs/SECURITY.md](docs/SECURITY.md)

### アーキテクチャ

```
ツールリクエスト
    │
    ▼
PermissionMiddleware (allow/deny/ask)
    │
    ▼
SandboxMiddleware (Bashをサンドボックス化)
    │
    ▼
ツール実行
```

### 使用方法

```swift
// withSecurity でセキュリティを有効化（ミドルウェアをパイプラインに追加）
let config = AgentConfiguration(...)
    .withSecurity(.standard.withHandler(CLIPermissionHandler()))

// プリセット
.withSecurity(.standard)     // 対話的許可、標準サンドボックス
.withSecurity(.development)  // 緩い許可、サンドボックスなし
.withSecurity(.restrictive)  // 最小限の許可、厳格なサンドボックス
.withSecurity(.readOnly)     // 読み取り専用、実行不可

// カスタム設定
let security = SecurityConfiguration(
    permissions: PermissionConfiguration(
        allow: [.tool("Read"), .bash("git:*")],
        deny: [.bash("rm:*")],
        defaultAction: .ask,
        handler: CLIPermissionHandler()
    ),
    sandbox: .standard
)
```

### SecurityConfiguration

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `permissions` | `PermissionConfiguration` | パーミッションルール |
| `sandbox` | `SandboxExecutor.Configuration?` | サンドボックス設定（nil=無効） |

### PermissionConfiguration

```swift
let config = PermissionConfiguration(
    allow: [.tool("Read"), .bash("git:*")],  // 許可ルール
    deny: [.bash("rm -rf:*")],               // 拒否ルール（Override可能）
    finalDeny: [.bash("sudo:*")],            // 絶対拒否（Override不可）
    overrides: [],                            // 親のDenyを上書き
    defaultAction: .ask,                      // デフォルト動作
    handler: CLIPermissionHandler(),          // 対話ハンドラ
    enableSessionMemory: true                 // Always Allow/Block を記憶
)

// ファイルからの読み込み
let config = try PermissionConfiguration.load(from: url)

// マージ（後者優先、重複排除）
let merged = base.merged(with: override)
```

**ルール評価順序:**

```
1. Final Deny (絶対禁止・Override不可・セッションメモリより優先)
2. Session Memory
3. Override (マッチすれば通常Denyをスキップ)
4. Deny (通常禁止)
5. Allow
6. Default Action
```

**パターン構文（大文字小文字区別）:**

| パターン | マッチ対象 |
|---------|----------|
| `"Read"` | Read ツール |
| `"Bash(git:*)"` | git コマンド（`git` + 区切り文字で始まる） |
| `"Write(/tmp/*)"` | /tmp/ 以下への書き込み |
| `"mcp__*"` | 全MCPツール |

**注意:** `prefix:*` パターンは区切り文字（スペース、ダッシュ、タブ等）を要求します。`git:*` は `git status` にマッチしますが `gitsomething` にはマッチしません。ファイルパスは正規化後にマッチングされます（`/tmp/../etc/` → `/etc/`）。

### SandboxExecutor（macOS専用）

```swift
let config = SandboxExecutor.Configuration(
    networkPolicy: .local,              // none, local, full
    filePolicy: .workingDirectoryOnly,  // readOnly, workingDirectoryOnly, custom
    allowSubprocesses: true
)

// プリセット
SandboxExecutor.Configuration.standard     // ローカルネットワーク、作業ディレクトリ書込
SandboxExecutor.Configuration.restrictive  // ネットワークなし、読み取り専用
```

**FilePolicy:**

| ポリシー | 読み取り | 書き込み |
|---------|:--------:|:--------:|
| `readOnly` | 全て許可 | 全て拒否 |
| `workingDirectoryOnly` | 全て許可 | 作業ディレクトリ+tmp |
| `custom(read:write:)` | 指定パス+システム | 指定パス+tmp |

### Guardrail（宣言的Step単位セキュリティ）

Step単位で宣言的にセキュリティポリシーを適用する`.guardrail { }`修飾子。

```swift
// 基本使用法
FetchUserData()
    .guardrail {
        Allow(.tool("Read"))
        Deny(.bash("rm:*"))
        Sandbox(.restrictive)
    }

// Deny.final - 絶対禁止（子でOverride不可）
Pipeline()
    .guardrail {
        Deny.final(.bash("rm -rf:*"))   // 絶対禁止
        Deny.final(.bash("sudo:*"))     // 絶対禁止
        Deny(.bash("rm:*"))             // 通常禁止（Override可能）
    }

// Override - 親のDenyを解除
CleanupStep()
    .guardrail {
        Override(.bash("rm:*.tmp"))     // ✅ 親のDeny(.bash("rm:*"))を解除
        Override(.bash("rm -rf:*"))     // ❌ 無視（finalなので）
    }

// プリセット
AnalyzeData()
    .guardrail(.readOnly)        // 読み取り専用
ProcessData()
    .guardrail(.standard)        // 標準セキュリティ
HandleSensitive()
    .guardrail(.restrictive)     // 厳格

// 条件付きルール
.guardrail {
    Allow(.tool("Read"))
    if isProduction {
        Deny(.bash("*"))
        Sandbox(.restrictive)
    }
}
```

**ルール型:**

| 型 | 説明 |
|---|------|
| `Allow` | 許可ルール |
| `Deny` | 拒否ルール（Override可能） |
| `Deny.final` | 絶対拒否（Override不可） |
| `Override` | 親のDenyを解除 |
| `AskUser` | 対話的確認 |
| `Sandbox` | サンドボックス設定 |

**階層的適用:**

```swift
// 宣言的Step内での階層的ガードレール
struct SecureWorkflow: Step {
    var body: some Step<String, String> {
        // 親のガードレール付きStep
        ProcessStep()
            .guardrail {
                Deny(.bash("rm:*"))  // 通常禁止
            }

        // 子で一部解除
        CleanupStep()
            .guardrail {
                Override(.bash("rm:*.tmp"))  // .tmpのみ許可
            }
    }
}

// ネストしたガードレール
OuterStep()
    .guardrail { Deny(.bash("rm:*")) }
    .map { input in
        InnerStep()
            .guardrail { Override(.bash("rm:*.tmp")) }
            .run(input)
    }
```

### Context による設定伝播

`SandboxMiddleware` は `@Context` システムを使用して設定を `ExecuteCommandTool` に伝播:

```swift
// SandboxMiddleware 内部（ContextStep経由で伝播）
return try await ContextStep(step: next, key: SandboxContext.self, value: configuration).run(context)

// ExecuteCommandTool 内部
@Context var sandboxConfig: SandboxExecutor.Configuration
// sandboxConfig.isDisabled でサンドボックスの有効/無効を判定
```

## Race / Parallel 設計

### Race: 成功優先戦略

複数のステップを並列実行し、**最初の成功**を返す。フォールバック・冗長性パターンに最適。

```swift
// 複数APIへのフォールバック
let race = Race<URL, Data> {
    FetchFromPrimaryServer()    // メインサーバー（時々ダウン）
    FetchFromMirrorServer()     // ミラー（遅いが安定）
    FetchFromCDN()              // CDN（キャッシュがあれば高速）
}
// → 最初に成功した結果を返す。全て失敗した場合のみエラー

// タイムアウト付き
let race = Race<String, String>(timeout: .seconds(30)) {
    GenerateWithOpenAI()
    GenerateWithLocal()
}
```

**動作:**
- 最初の**成功**結果を返す
- 失敗したステップは無視して他を待つ
- **全て**失敗した場合のみエラーをスロー
- 成功が見つかったら残りをキャンセル
- タイムアウトは即座に失敗

### Parallel: ベストエフォート戦略

複数のステップを並列実行し、**成功した結果を全て収集**。データ集約パターンに最適。

```swift
// 複数ソースからのデータ集約
let parallel = Parallel<Query, SearchResult> {
    SearchGitHub()              // 一時的にダウンすることがある
    SearchStackOverflow()
    SearchDocumentation()
}
// → 成功した結果を全て返す。GitHubが失敗しても他の結果は返る

// 画像処理
let parallel = Parallel<URL, ResizedImage> {
    ResizeImage(size: .thumbnail)
    ResizeImage(size: .medium)
    ResizeImage(size: .large)
}
// → 1つが壊れた画像で失敗しても、他は処理される
```

**動作:**
- 全ステップを並列実行
- 成功した結果を**全て**収集
- 一部が失敗しても成功分を返す
- **全て**失敗した場合のみ `ParallelError.allStepsFailed` をスロー
- 結果は完了順（宣言順ではない）

## 依存関係

```
                    FoundationModels (default)
                    OpenFoundationModels (--traits OpenFoundationModels)
                           ↓
                       SwiftAgent
                      ↙    ↓    ↘
        SwiftAgentMCP   AgentTools   SwiftAgentSymbio
              ↓                            ↓
         MCP (swift-sdk)         swift-actor-runtime
                                          ↓
                                   swift-discovery
```

## ビルド

```bash
# デフォルト (Apple FoundationModels)
swift build

# OpenFoundationModels を使用（開発/テスト用）
swift build --traits OpenFoundationModels
swift test --traits OpenFoundationModels
```

## 参考リンク
- [FoundationModels (Apple)](https://developer.apple.com/documentation/foundationmodels)
- [OpenFoundationModels](https://github.com/1amageek/OpenFoundationModels)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
