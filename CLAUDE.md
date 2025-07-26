# SwiftAgent OpenFoundationModels 統合方針

## 概要
SwiftAgentをOpenFoundationModelsに対応させ、既存のAIライブラリ依存を削除する。

## 現在の状況
- ✅ Package.swiftからAIライブラリ依存を削除済み
- ✅ OpenFoundationModels依存を追加済み
- ✅ SwiftAgent.Tool を OpenFoundationModels.Tool に完全移行済み
- ✅ AgentTools (FileSystemTool, URLFetchTool, GitTool, ExecuteCommandTool) を移行済み
- ✅ Agent プロトコルに guardrails, tracer, maxTurns プロパティを追加済み
- ✅ 宣言的な設計を維持（Agent 実装時に必要なプロパティのみオーバーライド）
- ✅ すべての個別AIライブラリ依存を削除済み（OllamaKit、LLMChatOpenAI、JSONSchema等）
- ✅ Generate, GenerateText, GenerateStructured を SwiftAgent モジュールに統合済み
- ✅ MessageTransform.swift で ChatMessage 型を定義済み
- ✅ プロジェクト全体のビルドが成功

## 実装済みの内容

### 1. コア設計の維持
- **Step/Agent/Model** の基本構造は維持
- **宣言的でSwiftUIライクな構文** を保持
- **型安全性** を最優先

### 2. Tool定義の完全移行
OpenFoundationModels.Tool を直接使用（Option B を採用）：
```swift
public struct ExecuteCommandTool: OpenFoundationModels.Tool {
    public typealias Arguments = ExecuteCommandInput
    
    public static let name = "execute"
    public var name: String { Self.name }
    
    public func call(arguments: ExecuteCommandInput) async throws -> ToolOutput {
        // 実装
    }
}
```

- パラメータは`@Generable`マクロで定義
- 型安全な入出力（ConvertibleFromGeneratedContent準拠）
- ToolOutput型への出力統一

### 3. Agent プロトコルの拡張
```swift
public protocol Agent: Step {
    // 既存のプロパティ
    @StepBuilder var body: Self.Body { get }
    
    // 新規追加（デフォルト実装あり）
    var maxTurns: Int { get }           // デフォルト: 10
    var guardrails: [any Guardrail] { get }  // デフォルト: []
    var tracer: AgentTracer? { get }    // デフォルト: nil
}
```

run() メソッドで自動的に適用される：
- Guardrails による入出力検証
- Tracing による実行監視
- 宣言的な設定（必要なプロパティのみオーバーライド）

## 完了したタスク

### 1. 依存関係の整理
- すべての個別AIライブラリ（OllamaKit、LLMChatOpenAI、JSONSchema等）を削除
- OpenFoundationModelsに完全移行
- swift-distributed-actors依存も削除

### 2. ヘルパー実装の SwiftAgent モジュールへの統合
- Agents モジュールを削除し、すべてのヘルパー実装を SwiftAgent モジュールに移動
- Generate: Generable型の構造化出力を生成
- GenerateText: シンプルな文字列出力を生成
- GenerateStructured: 構造化データ生成のための汎用Step
- MessageTransform: ChatMessage型と変換処理を提供

### 3. AgentTools の修正
- @Generableマクロの制限に対応（enum→String、配列→String）
- FileSystemTool、GitTool、ExecuteCommandTool、URLFetchToolすべて移行完了

### 4. Guardrails の整理
- SwiftAgent.Guardrail: 汎用的なStep検証用
- LanguageModelSession.Guardrails: LLM特有のコンテンツ安全性用
- 両者は補完的な役割を持つため、どちらも維持

## 今後の方針
- OpenFoundationModels が提供する統一インターフェースのみを使用
- 具体的なAIプロバイダー実装（OpenAI、Anthropic等）はユーザー側で選択
- SwiftAgentはプロバイダー中立なフレームワークとして機能

## モデルプロバイダーの使用方法
SwiftAgent で異なるAIモデルプロバイダーを使用するには、LanguageModelSession を作成して Generate/GenerateText に渡します：

```swift
// OpenAI の場合
let session = LanguageModelSession(
    model: OpenAIModelFactory.gpt4o(apiKey: apiKey),
    instructions: Instructions("You are a helpful assistant.")
)

Generate<String, Output>(session: session) { input in
    input
}
```

この設計により、SwiftAgent は特定のプロバイダーに依存せず、ユーザーが自由にモデルを選択できます。

## 注意事項

### @Generableマクロの制限
- 配列プロパティは直接サポートされない（回避策: スペース区切り文字列を使用）
- enumプロパティは直接サポートされない（回避策: @Guideのenumerationを持つString型を使用）
- 複雑なネスト構造では手動でinit実装が必要な場合がある

## 参考リンク
- [OpenFoundationModels DeepWiki](https://deepwiki.com/1amageek/OpenFoundationModels)
- [OpenAI Agents JS](https://deepwiki.com/openai/openai-agents-js) - Guardrails、Tracing の設計参考