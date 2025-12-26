# SwiftAgentSymbio 仕様書

エージェント間通信と発見のための分散システムモジュール。

## 設計原則

| 原則 | 説明 |
|------|------|
| **平等性** | 全エージェントは同列、親子関係なし |
| **場所透過性** | エージェントは相手の場所を知らない（同一プロセス/LAN/インターネット） |
| **統一インターフェース** | 全て `Community` 経由で通信 |
| **自己申告** | 各エージェントが `perceptions` で受信可能な信号を宣言 |
| **ローカル管轄** | エージェントは自分の管轄内でのみ起動・終了できる |
| **Distributed Actor** | エージェントは Swift Distributed Actor として実装 |

## ローカル vs リモート

| 操作 | ローカル | リモート |
|------|:--------:|:--------:|
| 起動 (spawn) | ✅ | ❌ |
| 終了 (terminate) | ✅ | ❌ |
| 発見 (discover) | ✅ | ✅ |
| 通信 (send/invoke) | ✅ | ✅ |

- **ローカルエージェント**: 自分で起動し、自分で終了できる
- **リモートエージェント**: 発見して通信するのみ（起動・終了は相手の管轄）

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 4: Agent (distributed actor)                              │
│   • ビジネスロジック                                             │
│   • @Resolvable プロトコル準拠                                   │
│   • distributed func receive(...)                               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Community                                              │
│   • SymbioActorSystem のラッパー                                 │
│   • Member の管理                                               │
│   • エージェントの起動 (spawn)                                   │
│   • 高レベル API 提供                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: SymbioActorSystem (DistributedActorSystem)             │
│   • ActorRegistry でローカル Actor を管理                        │
│   • remoteCall / remoteCallVoid でRPC                           │
│   • PeerConnector 統合                                           │
│   • ローカル/リモート透過的なルーティング                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: PeerConnector (swift-discovery)                        │
│   • Perception ↔ CapabilityID 変換                              │
│   • TransportCoordinator 統合                                    │
│   • 複数トランスポート対応                                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0: Transport (swift-discovery)                            │
│   • LocalNetworkTransport (mDNS/TCP)                            │
│   • NearbyTransport (BLE)                                       │
│   • RemoteNetworkTransport (HTTP/WebSocket)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心技術: Swift Distributed Actors

SwiftAgentSymbio は Swift の Distributed Actors を活用し、場所透過的なエージェント通信を実現する。

### @Resolvable マクロ

`@Resolvable` マクロ（SE-0428）により、プロトコルを通じて distributed actor を解決できる：

```swift
@Resolvable
public protocol SignalReceivable: DistributedActor where ActorSystem == SymbioActorSystem {
    /// 信号を受信
    distributed func receive(_ data: Data, perception: String) async throws -> Data?
}
```

生成されるコード:
```swift
// コンパイラが自動生成
public struct $SignalReceivable: DistributedActor {
    public static func resolve(id: Address, using system: SymbioActorSystem) throws -> any SignalReceivable
}
```

### SymbioActorSystem

`DistributedActorSystem` プロトコルを実装し、ローカル/リモートの区別なく Actor を管理：

```swift
public final class SymbioActorSystem: DistributedActorSystem {
    public typealias ActorID = Address
    public typealias SerializationRequirement = Codable

    /// ローカル Actor レジストリ
    private let registry: ActorRegistry

    /// swift-discovery 統合
    private var peerConnector: PeerConnector?

    /// Actor を解決（ローカル優先）
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?

    /// リモート呼び出し（自動的にローカル/リモートを判断）
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
}
```

**ルーティング原則**:
1. `registry.find(id:)` でローカル Actor を検索
2. 見つかれば `executeDistributedTarget()` で直接実行
3. 見つからなければ `PeerConnector` 経由でリモート呼び出し

---

## コアプロトコル

### Perception（知覚）

エージェントが受け取れる信号の種類を宣言する。

```swift
public protocol Perception: Sendable {
    var identifier: String { get }
    associatedtype Signal: Sendable & Codable
}
```

**Perception と Signal は 1:1 の関係**:
- 1つの Perception は 1つの Signal 型に対応
- Signal 型は必ず `Codable` に準拠（シリアライズ可能）

**標準シグナル型：**

| シグナル | 説明 |
|----------|------|
| `VisualSignal` | 画像データ（data, width, height, timestamp） |
| `AuditorySignal` | 音声データ（data, sampleRate, channels, timestamp） |
| `TactileSignal` | 触覚データ（pressure, locationX, locationY, timestamp） |
| `NetworkSignal` | テキストメッセージ（text, sourceIdentifier, timestamp） |

### SignalReceivable（信号受信可能）

Distributed Actor として信号を受信するためのプロトコル。

```swift
@Resolvable
public protocol SignalReceivable: DistributedActor where ActorSystem == SymbioActorSystem {
    /// 信号を受信
    /// - Parameters:
    ///   - data: シリアライズされた信号データ
    ///   - perception: 知覚の識別子
    /// - Returns: オプショナルなレスポンスデータ
    distributed func receive(_ data: Data, perception: String) async throws -> Data?
}
```

### CommunityAgent

コミュニティに参加するエージェントのプロトコル。

```swift
public protocol CommunityAgent: DistributedActor where ActorSystem == SymbioActorSystem {
    var community: Community { get }
    nonisolated var perceptions: [any Perception] { get }
}
```

### Terminatable

グレースフル終了をサポートするプロトコル。

```swift
public protocol Terminatable: Actor {
    func terminate() async
}
```

---

## Member

コミュニティ内の他のエージェントを表す。

```swift
public struct Member: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let accepts: Set<String>      // 受け取れる信号
    public let provides: Set<String>     // 提供する機能
    public var isAvailable: Bool
    public let metadata: [String: String]
}
```

**metadata["location"] の値：**
- `"local"` - 同一プロセス内（ローカル Actor）
- `"remote"` - ネットワーク経由（リモート Actor）

---

## Community API

### 初期化とライフサイクル

```swift
public actor Community {
    /// Actor System を指定して初期化
    init(actorSystem: SymbioActorSystem)

    /// 設定を指定して初期化
    init(name: String, perceptions: [any Perception] = [], ...)

    func start() async throws
    func stop() async throws
}
```

### メンバー検索

```swift
func whoCanReceive(_ perception: String) -> [Member]
func whoProvides(_ capability: String) -> [Member]
func member(id: String) -> Member?
var members: [Member] { get }
var availableMembers: [Member] { get }
```

### 通信

```swift
/// 信号を送信（Distributed Actor 経由）
func send<S: Sendable & Codable>(
    _ signal: S,
    to member: Member,
    perception: String
) async throws -> Data?

/// 機能を呼び出し
func invoke(
    _ capability: String,
    on member: Member,
    with arguments: Data
) async throws -> Data
```

### エージェント起動・終了

```swift
/// ローカルでエージェントを起動
@discardableResult
func spawn<A: CommunityAgent & SignalReceivable>(
    _ factory: @escaping () async throws -> A
) async throws -> Member

/// エージェントを終了
func terminate(_ member: Member) async throws
```

### 変更監視

```swift
var changes: AsyncStream<CommunityChange> { get }

public enum CommunityChange: Sendable {
    case joined(Member)
    case left(Member)
    case updated(Member)
    case becameAvailable(Member)
    case becameUnavailable(Member)
}
```

---

## 信号送受信フロー

### send() の実装

```swift
public func send<S: Sendable & Codable>(
    _ signal: S,
    to member: Member,
    perception: String
) async throws -> Data? {
    guard member.isAvailable else {
        throw CommunityError.memberUnavailable(member.id)
    }

    // 1. 信号をシリアライズ
    let data = try JSONEncoder().encode(signal)

    // 2. @Resolvable 経由で Actor を解決
    let receiver = try $SignalReceivable.resolve(
        id: Address(hexString: member.id),
        using: actorSystem
    )

    // 3. distributed func を呼び出し（ローカル/リモート透過）
    return try await receiver.receive(data, perception: perception)
}
```

### フロー図

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           信号送受信フロー                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Sender                     Community                     Receiver          │
│    │                           │                             │              │
│    │ send(signal, to: member)  │                             │              │
│    │ ─────────────────────────>│                             │              │
│    │                           │                             │              │
│    │                      $SignalReceivable.resolve()        │              │
│    │                           │                             │              │
│    │                           │ ┌─────────────────────────┐ │              │
│    │                           │ │ SymbioActorSystem       │ │              │
│    │                           │ │ ┌───────────────────┐   │ │              │
│    │                           │ │ │registry.find(id:) │   │ │              │
│    │                           │ │ └─────────┬─────────┘   │ │              │
│    │                           │ │           │             │ │              │
│    │                           │ │     ┌─────┴─────┐       │ │              │
│    │                           │ │ ローカル     リモート    │ │              │
│    │                           │ │     │           │       │ │              │
│    │                           │ │     ▼           ▼       │ │              │
│    │                           │ │  execute    PeerConnector│ │              │
│    │                           │ │  Target     → Transport │ │              │
│    │                           │ └───────────────────────┘ │ │              │
│    │                           │                             │              │
│    │                           │ receiver.receive(data, ...)│              │
│    │                           │ ───────────────────────────>│              │
│    │                           │                             │              │
│    │                           │                             │ 信号を処理   │
│    │                           │                             │              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## エージェント起動フロー

### ローカル起動 (`spawn`)

```
spawn { WorkerAgent(community, actorSystem) }
         │
         ▼
┌─────────────────────────────────────────┐
│ 1. factory() で distributed actor 生成   │
│ 2. actorSystem.actorReady() が自動呼出  │
│    → ActorRegistry に登録               │
│ 3. perceptions → accepts 変換           │
│ 4. Member 作成 & memberCache 登録       │
│ 5. .joined(member) イベント発行          │
└─────────────────────────────────────────┘
         │
         ▼
    return Member
```

**ポイント**:
- `distributed actor` の初期化時に `actorReady()` が自動的に呼ばれる
- これにより `ActorRegistry` に自動登録される
- 手動のハンドラ登録は不要

### spawn() 実装

```swift
@discardableResult
public func spawn<A: CommunityAgent & SignalReceivable>(
    _ factory: @escaping () async throws -> A
) async throws -> Member {
    // 1. エージェント生成（distributed actor）
    let agent = try await factory()

    // 2. Actor ID を取得（actorReady で自動登録済み）
    let agentID = agent.id.hexString

    // 3. perceptions → accepts 変換
    let accepts = Set(agent.perceptions.map { $0.identifier })

    // 4. Member 作成
    let member = Member(
        id: agentID,
        name: nil,
        accepts: accepts,
        provides: [],
        isAvailable: true,
        metadata: ["location": "local"]
    )

    // 5. キャッシュに追加
    memberCache[agentID] = member
    localAgentIDs.insert(agentID)

    // 6. イベント発行
    changeContinuation?.yield(.joined(member))

    return member
}
```

---

## エージェント終了フロー

```
terminate(member)
         │
         ▼
┌─────────────────────────────────────────┐
│ metadata["location"] を確認             │
└─────────────────────────────────────────┘
         │
    ┌────┴────────────────────┐
    │                         │
    ▼ "local"                 ▼ "remote"
┌──────────────────┐    ┌──────────────────┐
│ 1. Terminatable  │    │ エラー           │
│    .terminate()  │    │ (終了不可)       │
│ 2. resignID()で  │    └──────────────────┘
│    Registry解除  │
└────────┬─────────┘
         │
         ▼
┌───────────────────────┐
│ memberCache から削除  │
│ .left(member) 発行    │
└───────────────────────┘
```

---

## 使用例

### Distributed Actor として実装

```swift
distributed actor WorkerAgent: CommunityAgent, SignalReceivable, Terminatable {

    typealias ActorSystem = SymbioActorSystem

    let community: Community
    private var isRunning = true

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    // SignalReceivable - 信号を受信
    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        switch perception {
        case "work":
            let signal = try JSONDecoder().decode(WorkSignal.self, from: data)
            let result = await process(signal)
            return try JSONEncoder().encode(ResultSignal(data: result))
        default:
            return nil
        }
    }

    private func process(_ work: WorkSignal) async -> String {
        // 処理ロジック
        return "processed: \(work.task)"
    }

    func terminate() async {
        isRunning = false
    }
}
```

### オーケストレーター

```swift
distributed actor OrchestratorAgent: CommunityAgent {

    typealias ActorSystem = SymbioActorSystem

    let community: Community
    private var workers: [Member] = []

    nonisolated var perceptions: [any Perception] { [] }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    // ワーカーを起動
    func scaleUp(count: Int) async throws {
        for _ in 0..<count {
            let worker = try await community.spawn {
                WorkerAgent(community: self.community, actorSystem: self.actorSystem)
            }
            workers.append(worker)
        }
    }

    // タスクを分散
    func distribute(tasks: [WorkSignal]) async throws {
        for (index, task) in tasks.enumerated() {
            let worker = workers[index % workers.count]
            _ = try await community.send(task, to: worker, perception: "work")
        }
    }

    // 全ワーカーを終了
    func shutdown() async throws {
        for worker in workers {
            try await community.terminate(worker)
        }
        workers.removeAll()
    }
}
```

### 完全な実行例

```swift
// ActorSystem と Community を作成
let actorSystem = SymbioActorSystem()
let community = Community(actorSystem: actorSystem)
try await community.start()

// オーケストレーターを起動
let orchestratorMember = try await community.spawn {
    OrchestratorAgent(community: community, actorSystem: actorSystem)
}

// OrchestratorAgent を解決して操作
let orchestrator = try actorSystem.resolve(
    id: Address(hexString: orchestratorMember.id),
    as: OrchestratorAgent.self
)!

// ワーカーを3つ起動
try await orchestrator.scaleUp(count: 3)

// タスクを分散
let tasks = [
    WorkSignal(task: "task1"),
    WorkSignal(task: "task2"),
    WorkSignal(task: "task3")
]
try await orchestrator.distribute(tasks: tasks)

// 終了
try await orchestrator.shutdown()
try await community.stop()
```

---

## エラー

```swift
public enum CommunityError: Error {
    case memberUnavailable(String)
    case memberDoesNotProvide(String, String)
    case noAcceptedPerceptions(String)
    case invalidCapability(String)
    case invocationFailed(String)
    case cannotTerminateRemote(String)
    case memberNotFound(String)
}

public enum SymbioError: Error {
    case notStarted
    case alreadyStarted
    case noTransportAvailable
    case serializationFailed(String)
    case deserializationFailed(String)
    case invocationFailed(String)
    case actorNotFound(String)
}
```

---

## ファイル構成

| ファイル | 責務 |
|----------|------|
| `SymbioActorSystem.swift` | DistributedActorSystem 実装、ActorRegistry 管理 |
| `Community.swift` | Community actor、Member、CommunityChange |
| `Communicable.swift` | CommunityAgent、SignalReceivable、Terminatable |
| `PeerConnector.swift` | swift-discovery 統合 |
| `Address.swift` | Actor ID (ActorID = Address) |
| `InvocationEncoder.swift` | RPC エンコーダー |
| `InvocationDecoder.swift` | RPC デコーダー |
| `ResultHandler.swift` | RPC 結果ハンドラ |

---

## swift-discovery 依存

| Transport | スコープ | 技術 |
|-----------|---------|------|
| `LocalNetworkTransport` | 同一ネットワーク | mDNS + TCP |
| `NearbyTransport` | 近接 | BLE |
| `RemoteNetworkTransport` | インターネット | HTTP + WebSocket |

---

## swift-actor-runtime 依存

| コンポーネント | 説明 |
|----------------|------|
| `ActorRegistry` | ローカル Actor インスタンスの管理 |
| `InvocationEnvelope` | RPC リクエストのエンベロープ |
| `ResponseEnvelope` | RPC レスポンスのエンベロープ |

---

## 設計のポイント

### なぜ SignalRouter が不要になったか

従来の設計では、信号ルーティングのために `SignalRouter` を使用していた：

```swift
// 旧設計（SignalRouter ベース）
actor SignalRouter {
    func register<P: Perception>(_ perception: P, handler: ...)
    func route(perception: String, signalData: Data, from: Member)
}
```

**問題点**:
- 型消去による複雑さ（`[any Perception]` → ハンドラ登録）
- 手動のハンドラ登録・解除が必要
- ローカル/リモートで異なるルーティングパス

**新設計（Distributed Actor ベース）**:

```swift
// 新設計（@Resolvable ベース）
@Resolvable
protocol SignalReceivable: DistributedActor {
    distributed func receive(_ data: Data, perception: String) async throws -> Data?
}
```

**解決**:
- `distributed actor` の標準機能でルーティング
- `SymbioActorSystem.remoteCall()` が自動的にローカル/リモートを判断
- ハンドラ登録不要（Actor 生成時に `actorReady()` で自動登録）
- 型安全（`$SignalReceivable.resolve()` でコンパイル時チェック）

### Community の役割

`Community` は `SymbioActorSystem` の高レベルラッパーとして機能：

```
┌─────────────────────────────────────────────────┐
│                  Community                      │
│  ┌───────────────────────────────────────────┐  │
│  │ • Member 管理 (memberCache)              │  │
│  │ • whoCanReceive() / whoProvides()        │  │
│  │ • spawn() / terminate()                  │  │
│  │ • changes (AsyncStream)                  │  │
│  └───────────────────────────────────────────┘  │
│                      ↓                          │
│  ┌───────────────────────────────────────────┐  │
│  │           SymbioActorSystem               │  │
│  │ • ActorRegistry                          │  │
│  │ • PeerConnector                          │  │
│  │ • remoteCall / remoteCallVoid            │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```
