# SwiftAgent

Apple FoundationModelsを基盤とした型安全で宣言的なAIエージェントフレームワーク。

> **Note**: デフォルトはApple FoundationModelsを使用。`USE_OTHER_MODELS=1` で OpenFoundationModels に切り替え可能。

## コア概念

| 概念 | 説明 |
|------|------|
| **Step** | `Input -> Output` の非同期変換単位 |
| **Agent** | `body` を定義するだけで `run` が自動実装される宣言的Step |
| **Session** | TaskLocalベースのセッション伝播（`@Session`, `withSession`） |
| **Memory/Relay** | Step間の状態共有（`@Memory` で保持、`$` で `Relay` を取得） |
| **Context** | 汎用TaskLocal伝播（`ContextKey`, `@Context`, `withContext`） |
| **Generate** | LLMによる構造化出力生成 |

## Step 一覧

| 種別 | Steps |
|------|-------|
| プリミティブ | `Transform`, `Generate`, `GenerateText`, `EmptyStep`, `Join` |
| 合成 | `Chain2-8`, `Parallel`, `Race`, `Loop`, `Map`, `Reduce` |
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
try await withSession(session) { try await MyStep().run("Hello") }

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

// Context による汎用TaskLocal伝播
enum TrackerContext: ContextKey {
    @TaskLocal static var current: URLTracker?
    static func withValue<T: Sendable>(_ value: URLTracker, operation: () async throws -> T) async rethrows -> T {
        try await $current.withValue(value, operation: operation)
    }
}

struct MyStep: Step {
    @Context(TrackerContext.self) var tracker: URLTracker
    func run(_ input: URL) async throws -> Bool { !tracker.hasVisited(input) }
}
try await withContext(TrackerContext.self, value: tracker) { try await MyStep().run(url) }

// Agent による宣言的な合成
struct Pipeline: Agent {
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

## Context

任意の型をTaskLocal経由で伝播する汎用システム。

```swift
// 1. ContextKey を定義
enum ConfigContext: ContextKey {
    @TaskLocal static var current: AppConfig?

    static func withValue<T: Sendable>(
        _ value: AppConfig,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $current.withValue(value, operation: operation)
    }
}

// 2. @Context で値にアクセス
struct ConfiguredStep: Step {
    @Context(ConfigContext.self) var config: AppConfig

    func run(_ input: String) async throws -> String {
        // config を使用...
    }
}

// 3. withContext で値を提供
try await withContext(ConfigContext.self, value: appConfig) {
    try await ConfiguredStep().run("input")
}

// @OptionalContext - 値がなくてもエラーにならない
struct OptionalStep: Step {
    @OptionalContext(ConfigContext.self) var config: AppConfig?

    func run(_ input: String) async throws -> String {
        if let config { /* ... */ }
    }
}

// Step拡張
try await myStep.run(input, context: ConfigContext.self, value: config)
```

## @Generable の制限

- Dictionary 型は未サポート
- enum は未サポート（`@Guide(enumeration:)` を使用）
- 全プロパティに `@Guide` が必須

## モジュール

### Skills
エージェント機能を拡張するポータブルなスキルパッケージ。詳細: [docs/SKILLS_DESIGN.md](docs/SKILLS_DESIGN.md)

```swift
let config = AgentConfiguration(
    instructions: Instructions("..."),
    modelProvider: provider,
    skills: .autoDiscover()
)
```

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
    deny: [.bash("rm -rf:*")],               // 拒否ルール
    defaultAction: .ask,                      // デフォルト動作
    handler: CLIPermissionHandler(),          // 対話ハンドラ
    enableSessionMemory: true                 // Always Allow/Block を記憶
)

// ファイルからの読み込み
let config = try PermissionConfiguration.load(from: url)

// マージ（後者優先、重複排除）
let merged = base.merged(with: override)
```

**ルール評価順序:** session memory → allow → deny → defaultAction

**パターン構文（大文字小文字区別）:**

| パターン | マッチ対象 |
|---------|----------|
| `"Read"` | Read ツール |
| `"Bash(git:*)"` | git で始まるコマンド |
| `"Write(/tmp/*)"` | /tmp/ 以下への書き込み |
| `"mcp__*"` | 全MCPツール |

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

### Context による設定伝播

`SandboxMiddleware` は `@Context` システムを使用して設定を `ExecuteCommandTool` に伝播:

```swift
// SandboxMiddleware 内部
return try await withContext(SandboxContext.self, value: configuration) {
    try await next(context)
}

// ExecuteCommandTool 内部
@OptionalContext(SandboxContext.self) private var sandboxConfig: SandboxExecutor.Configuration?
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
                    OpenFoundationModels (USE_OTHER_MODELS=1)
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
USE_OTHER_MODELS=1 swift build
USE_OTHER_MODELS=1 swift test
```

## 参考リンク
- [FoundationModels (Apple)](https://developer.apple.com/documentation/foundationmodels)
- [OpenFoundationModels](https://github.com/1amageek/OpenFoundationModels)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
