# SwiftAgent

OpenFoundationModelsを基盤とした型安全で宣言的なAIエージェントフレームワーク。

## コア概念

| 概念 | 説明 |
|------|------|
| **Step** | `Input -> Output` の非同期変換単位 |
| **Session** | TaskLocalベースのセッション伝播（`@Session`, `withSession`） |
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

// StepBuilder による合成
struct Pipeline: Step {
    @Session var session: LanguageModelSession
    @StepBuilder var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText(session: session) { Prompt($0) }
    }
    func run(_ input: String) async throws -> String { try await body.run(input) }
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
MCP (Model Context Protocol) 統合モジュール。

```swift
let mcpClient = try await MCPClient.connect(config: config)
let mcpTools = try await mcpClient.tools()
let session = LanguageModelSession(model: model, tools: mcpTools) { Instructions("...") }
```

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
public struct ReplicateTool: OpenFoundationModels.Tool {
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

## 依存関係

```
                    OpenFoundationModels
                           ↓
                       SwiftAgent
                      ↙    ↓    ↘
        SwiftAgentMCP   AgentTools   SwiftAgentSymbio
              ↓                            ↓
         MCP (swift-sdk)         swift-actor-runtime
                                          ↓
                                   swift-discovery
```

## 参考リンク
- [OpenFoundationModels DeepWiki](https://deepwiki.com/1amageek/OpenFoundationModels)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
