# SwiftAgent

## 概要
SwiftAgentはOpenFoundationModelsを基盤とした、型安全で宣言的なAIエージェントフレームワーク。

## アーキテクチャ

### コア概念
- **Step**: 基本的な処理単位。`Input -> Output` の非同期変換を行う
- **LanguageModelSession**: OpenFoundationModelsのLLMセッション
- **Session**: TaskLocalベースのセッション伝播機構

```swift
public protocol Step<Input, Output> {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    func run(_ input: Input) async throws -> Output
}
```

### Step の種類

#### プリミティブ Steps
| Step | 説明 |
|------|------|
| `Transform` | クロージャによる単純な変換 |
| `Generate<In, Out>` | LLMで構造化出力を生成（Out: Generable） |
| `GenerateText<In>` | LLMでテキスト出力を生成 |
| `EmptyStep` | パススルー（入力をそのまま出力） |
| `Join` | `[String] -> String` 結合 |

#### 合成 Steps
| Step | 説明 |
|------|------|
| `Chain2-8` | 直列実行（StepBuilderで自動生成） |
| `Parallel` | 並列実行 |
| `Race` | 競合実行（最初の結果を返す） |
| `Loop` | 繰り返し実行 |
| `Map` | コレクション変換 |
| `Reduce` | コレクション集約 |

#### 修飾 Steps
| Step | 説明 |
|------|------|
| `Monitor` | 入出力/エラー/完了を監視 |
| `TracingStep` | 分散トレーシング |
| `AnyStep` | 型消去ラッパー |

## Session 管理

SwiftUIの`@Environment`に似た仕組みで、`LanguageModelSession`をStep階層に暗黙的に伝播させる。

### コンポーネント

```swift
// 1. TaskLocalでセッションを保持
public enum SessionContext {
    @TaskLocal public static var current: LanguageModelSession?
}

// 2. @Sessionプロパティラッパーでアクセス
@propertyWrapper
public struct Session {
    public var wrappedValue: LanguageModelSession {
        SessionContext.current!
    }
}

// 3. withSessionでコンテキストを設定
public func withSession<T>(_ session: LanguageModelSession, operation: () async throws -> T) async rethrows -> T

// 4. Step拡張でセッション付き実行
extension Step {
    public func run(_ input: Input, session: LanguageModelSession) async throws -> Output
}
```

### 使用例

```swift
// @Sessionでセッションにアクセス
struct TranslateStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        let response = try await session.respond {
            Prompt("Translate to Japanese: \(input)")
        }
        return response.content
    }
}

// 実行時にwithSessionでコンテキスト設定
let session = LanguageModelSession(model: model) {
    Instructions("You are a translator")
}

let result = try await withSession(session) {
    try await TranslateStep().run("Hello")
}

// または簡便なメソッド
let result = try await TranslateStep().run("Hello", session: session)
```

### ネストしたStep

```swift
struct OuterStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        // InnerStepも同じsessionを自動的に使用
        let processed = try await InnerStep().run(input)
        return processed
    }
}

struct InnerStep: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        // 親のコンテキストからsessionを取得
        let response = try await session.respond { Prompt(input) }
        return response.content
    }
}

// 一度のwithSessionで両方のStepがsessionにアクセス可能
try await withSession(session) {
    try await OuterStep().run("Hello")
}
```

## 基本的な使い方

```swift
import SwiftAgent
import OpenFoundationModels

// LanguageModelSession を作成
let session = LanguageModelSession(model: model) {
    Instructions("You are a helpful assistant.")
}

// Step を作成して実行
let step = GenerateText<String>(session: session) { input in
    Prompt("Translate to Japanese: \(input)")
}

let result = try await step.run("Hello, world!")
```

### StepBuilder による合成

```swift
struct TranslationPipeline: Step {
    typealias Input = String
    typealias Output = String

    @Session var session: LanguageModelSession

    @StepBuilder
    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText(session: session) { input in
            Prompt("Translate to Japanese: \(input)")
        }
        Transform { "Translation: \($0)" }
    }

    func run(_ input: String) async throws -> String {
        try await body.run(input)
    }
}

// 使用
let result = try await withSession(session) {
    try await TranslationPipeline().run("Hello")
}
```

### 構造化出力

```swift
@Generable
struct BlogPost: Sendable {
    @Guide(description: "The title of the blog post")
    let title: String

    @Guide(description: "The main content")
    let content: String
}

let step = Generate<String, BlogPost>(session: session) { topic in
    Prompt("Write a blog post about: \(topic)")
}

let post = try await step.run("Swift Concurrency")
```

## Tool 定義

OpenFoundationModels.Tool を直接使用：

```swift
@Generable
public struct SearchInput: Sendable {
    @Guide(description: "Search query")
    public let query: String
}

public struct SearchOutput: Sendable, PromptRepresentable {
    public let results: [String]

    public var promptRepresentation: Prompt {
        Prompt(results.joined(separator: "\n"))
    }
}

public struct SearchTool: Tool {
    public typealias Arguments = SearchInput

    public let name = "search"
    public let description = "Search for information"

    public func call(arguments: SearchInput) async throws -> SearchOutput {
        SearchOutput(results: ["Result 1", "Result 2"])
    }
}
```

### @Generable の注意事項

**Arguments（LLMが生成）**: @Generable を使用
```swift
@Generable
struct ToolInput: Sendable {
    @Guide(description: "説明") let param: String
}
```

**Output（コードが生成）**: @Generable を使用しない
```swift
struct ToolOutput: Sendable, PromptRepresentable {
    let result: String
    var promptRepresentation: Prompt { Prompt(result) }
}
```

### @Generable の制限
- Dictionary 型は直接サポートされない
- enum は直接サポートされない（@Guide の enumeration を使用）
- すべてのプロパティに @Guide を付ける必要がある

## SwiftAgentMCP

MCP (Model Context Protocol) をSwiftAgentと統合するオプショナルモジュール。

### 概要

```swift
import SwiftAgentMCP

// 1. MCP サーバー設定
let config = MCPServerConfig(
    name: "filesystem",
    transport: .stdio(
        command: "/usr/local/bin/npx",
        arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
    )
)

// 2. 接続
let mcpClient = try await MCPClient.connect(config: config)
defer { Task { await mcpClient.disconnect() } }

// 3. Tools取得 (OpenFoundationModels.Tool互換)
let mcpTools = try await mcpClient.tools()

// 4. LanguageModelSessionで使用
let session = LanguageModelSession(model: model, tools: mcpTools) {
    Instructions("You are a helpful assistant")
}
```

### 主要コンポーネント

| コンポーネント | 説明 |
|--------------|------|
| `MCPClient` | MCPサーバーへの接続を管理するActor |
| `MCPDynamicTool` | MCP.ToolをOpenFoundationModels.Toolに変換 |
| `MCPServerConfig` | サーバー接続設定 |
| `MCPTransportConfig` | トランスポート設定（stdio/HTTP） |

## ファイル構成

| ファイル | 責務 |
|----------|------|
| `Agent.swift` | Step プロトコル、Chain2-8、StepBuilder |
| `Session.swift` | @Session、withSession、SessionContext |
| `Generate.swift` | Generate、GenerateText |
| `Loop.swift` | 繰り返し制御 |
| `Parallel.swift` | 並列実行 |
| `Race.swift` | 競合実行 |
| `Map.swift` | コレクション変換 |
| `Reduce.swift` | コレクション集約 |
| `Transform.swift` | 単純変換 |
| `Join.swift` | 文字列結合 |
| `AnyStep.swift` | 型消去 |
| `Monitor.swift` | 監視 |
| `Tracing.swift` | 分散トレーシング |
| `StepModifier.swift` | モディファイアパターン |
| `Tool+Step.swift` | Step を Tool として使用 |

## 依存関係

```
OpenFoundationModels
    ↑
SwiftAgent (Step, Generate, Session, Control Flow)
    ↑
AgentTools (FileSystemTool, ExecuteCommandTool, etc.)

MCP (swift-sdk)
    ↑
SwiftAgentMCP (MCPClient, MCPDynamicTool)
    ↑
SwiftAgent
```

## 参考リンク
- [OpenFoundationModels DeepWiki](https://deepwiki.com/1amageek/OpenFoundationModels)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
