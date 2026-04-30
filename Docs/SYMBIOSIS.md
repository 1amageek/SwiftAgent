# SwiftAgentSymbio 仕様書

SwiftAgentSymbio は、エージェントが他者と協力するための実行時基盤である。

`Community` は哲学上の概念として扱う。実装上の中心は `SymbioRuntime` であり、ローカルに所有するエージェント、観測された peer、claim、信頼、routing をこのプロセスの主観的な view として保持する。

設計への具体的な落とし込みは [SYMBIO_DESIGN.md](SYMBIO_DESIGN.md) に分離する。

## 設計原則

| 原則 | 説明 |
|---|---|
| 平等性 | エージェント間の関係は command hierarchy ではなく peer membership |
| 主観的 view | runtime は global registry ではなく、このプロセスから見た局所的な社会 view |
| 接続と社会性の分離 | transport は到達性を扱い、runtime は関係・信頼・routing を扱う |
| claim と authority の分離 | remote peer の宣言は claim であり、local policy を通るまで権限ではない |
| ローカル所有 | 起動・終了できるのはローカルに生成した agent だけ |
| 型付き境界 | signal、invocation、descriptor、route は typed boundary として扱う |
| Community の任意性 | Community は常に必要な実体ではなく、協調を助ける affordance として扱う |

## Community の哲学

`Community` は、複数の主体が協力するための共有作業面である。ただし、3 者以上の共同作業であっても常に `Community` が必要とは限らない。高い文脈保持能力を持つ LLM が全体を調停できる場合や、参加者が直接会話だけで十分に同期できる場合は、明示的な Community を作らなくても協調は成立する。

人間における掲示板、GitHub issue、pull request、共有タスクリスト、現場ログのようなものが Community に近い。これらは会話そのものではなく、会話・作業・判断・レビュー・履歴を外部化するための場である。

```text
goal + participants + context pressure + time scale + audit need
  -> direct conversation
  -> mediated coordination
  -> community substrate
```

Community はしたがって、基礎オブジェクトではなく coordination affordance である。必要なときに立ち上がり、不要なときは直接通信や内部 planning を邪魔しない。

| 状況 | Community の必要性 |
|---|---|
| 1 on 1 の直接会話で完結する | 低い |
| 3 者以上でも強い調停者が文脈を保持できる | 低い場合がある |
| 非同期・長期・レビュー・責任分担が必要 | 高い |
| ロボット、LLM、memory、human が非対称な能力を補完する | 高い |
| context window や計算資源の制約が強い | 高い |
| claim、判断、観測、作業履歴に provenance が必要 | 高い |

## Affordance と capability

ロボットや physical AI を含む協調では、`capability` だけでは不十分である。capability は「原理的に実行できる契約」に近い。一方、affordance は「今この状況でできそうなこと」である。

| 概念 | 意味 | 例 |
|---|---|---|
| perception | 相手に届く問い、観測、報告、signal | 「そこからタワーは見える？」 |
| capability | 明示的に呼び出せる action contract | 画像分析、移動命令、ファイル編集 |
| affordance | 状況込みで現在可能に見えること | タワーが見える、棚に近づける、把持できない |
| claim | provenance 付きの主張 | robot A says tower is visible |
| constraint | affordance を制限する条件 | battery low、path blocked、permission missing |

`perception` は conversational input として開いているべきである。相手が答えられるかを事前に知っている必要はない。電話で相手の状況が分からなくても「そこから見える？」と聞けるのと同じである。

ただし conversational input は自然言語に限定しない。自然言語で表現できる intent もあれば、typed payload、sensor frame、actuator command、resource reference としてしか扱えない入力もある。自然言語を理解できないロボット、reflex loop、低レベル controller も Community の参加者になり得る。

```text
intent -> natural language / typed payload / sensor frame / actuator command
       -> direct receiver or mediator
```

`capability` は side effect や安全境界を伴うため、明示的で typed かつ policy-gated であるべきである。

`affordance` はその間をつなぐ。Community または runtime は、問いかけ、観測、応答、失敗、成功を通じて「今この member が何を差し出せそうか」という local view を更新する。

```text
question / observation -> claim -> affordance -> route / task formation
```

## ローカル vs リモート

| 操作 | ローカル | リモート |
|---|:---:|:---:|
| spawn | yes | no |
| terminate | yes | no |
| observe | yes | yes |
| send | yes | yes |
| invoke | yes | yes |
| block / forget | local view only | local view only |

remote agent は所有対象ではない。発見、接続、通信、観測、忘却、拒否、低優先度化はできるが、相手そのものを終了したり支配したりしない。

## アーキテクチャ

```text
Layer 4: Agent
  - Communicable
  - distributed func receive(...)

Layer 3: SymbioRuntime
  - local agent lifecycle
  - member view
  - local peer observations
  - route scoring
  - block / forget

Layer 2: SymbioActorSystem + SymbioProtocol
  - local distributed actor registry
  - incoming invocation routing
  - invocation envelope / reply

Layer 1: SymbioTransport
  - remote peer descriptor events
  - remote invocation delivery

Layer 0: PeerConnectivity or custom transport
  - discovery
  - join / disconnect
  - messages / streams / resources
```

## 主要型

| 型 | 責務 |
|---|---|
| `SymbioRuntime` | ローカル agent と participant view の実行時 facade |
| `ParticipantID` | agent、robot、device、aggregate を表す安定 ID |
| `ParticipantDescriptor` | participant が交換する自己記述 |
| `ParticipantView` | affordance、claim、evidence、availability、policy 制約を含む局所 view |
| `Affordance` | participant が状況内で実行可能に見える capability contract |
| `RoutePlan` | routing 判断、delivery、evidence、policy decision を含む計画 |
| `SymbioActorSystem` | ローカル distributed actor registry と invocation routing |
| `SymbioTransport` | transport 実装を差し替える境界 |
| `SymbioInvocationEnvelope` | remote invocation の request envelope |
| `SymbioInvocationReply` | remote invocation の result / failure |

## Agent 実装

```swift
distributed actor WorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        let signal = try JSONDecoder().decode(WorkSignal.self, from: data)
        return nil
    }

    nonisolated func terminate() async {}
}
```

## Runtime 使用例

```swift
let actorSystem = SymbioActorSystem()
let runtime = SymbioRuntime(actorSystem: actorSystem)

let worker = try await runtime.spawn {
    WorkerAgent(runtime: runtime, actorSystem: actorSystem)
}

try await runtime.send(WorkSignal(task: "process"), to: worker.id, perception: "work")
```

## Transport 境界

`SymbioTransport` は networking framework ではなく、Symbio runtime が必要とする最小境界である。

```swift
public protocol SymbioTransport: Sendable {
    var events: AsyncStream<SymbioTransportEvent> { get }

    func start() async throws
    func shutdown() async throws
    func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async
    func removeInvocationHandler() async
    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply
}
```

`PeerConnectivity` はこの境界の有力な実装候補である。`SymbioRuntime` は `PeerConnectivity` 型を直接知らないため、近傍通信、libp2p、in-process transport、test double を同じ runtime semantics で扱える。

## PeerConnectivity adapter

`SwiftAgentSymbioPeerConnectivity` は `PeerConnectivitySession` を `SymbioTransport` として使うための adapter を提供する。

| 型 | 責務 |
|---|---|
| `PeerConnectivitySymbioTransport` | `PeerConnectivityEvent` を `SymbioTransportEvent` に変換し、stream 上で invocation / descriptor を交換する |
| `PeerConnectivitySymbioMetadata` | discovery metadata へ `ParticipantDescriptor` を載せるための key / codec |

adapter は 2 つの stream protocol を使う。

| Protocol | 用途 |
|---|---|
| `/swiftagent/symbio/descriptor/1.0.0` | 接続後に `ParticipantDescriptor` を交換する |
| `/swiftagent/symbio/invoke/1.0.0` | `SymbioInvocationEnvelope` と `SymbioInvocationReply` を交換する |

discovery metadata が得られる backend では metadata から `ParticipantDescriptor` を作る。metadata が不十分な backend では、接続後の descriptor exchange によって descriptor 全体を補完する。

## Community の位置づけ

`Community` は実装型ではなく、エージェントやロボットが社会的に存在するための概念である。

transport event は単なる到達性であり、runtime はそれを observation、claim、relationship、trust、route に変換する。

```text
transport event -> observation -> claim -> relationship -> route -> action
```

この変換が SwiftAgentSymbio の中心である。
