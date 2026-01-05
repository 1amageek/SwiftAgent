# Security Configuration

SwiftAgentのセキュリティ設定（パーミッション＆サンドボックス）のドキュメント。

## 概要

SwiftAgentは2層のセキュリティを提供します：

1. **PermissionConfiguration** - ツール実行の許可/拒否ルール
2. **SandboxExecutor** - コマンド実行のサンドボックス化（macOS専用）

`PermissionConfiguration`はJSONファイルでの読み込み・書き出しをサポートします。ファイルの保存場所の決定は利用側プロジェクトの責務です。

## 責務の分離

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftAgent (このライブラリ)                                  │
│  ─────────────────────────────────────────                  │
│  • JSONフォーマット定義                                       │
│  • Codable 準拠                                              │
│  • load(from: URL) / load(from: Data)                       │
│  • encode() -> Data                                          │
│  • プリセット (.standard, .development, etc.)                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  利用側プロジェクト                                           │
│  ─────────────────────────────────────────                  │
│  • ファイルの保存場所を決定                                   │
│    - ~/.config/myapp/permissions.json                       │
│    - .myapp/permissions.json                                │
│    - Bundle.main.url(forResource:...)                       │
│  • 複数ファイルのマージ戦略                                   │
│  • ファイル監視・ホットリロード                               │
└─────────────────────────────────────────────────────────────┘
```

---

## JSONフォーマット

### 完全版

```json
{
  "version": 1,
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(git:*)",
      "Bash(swift build:*)",
      "Write(/tmp/*)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(sudo:*)",
      "Bash(chmod 777:*)"
    ],
    "defaultAction": "ask",
    "enableSessionMemory": true
  }
}
```

### 最小版

```json
{
  "permissions": {
    "allow": ["Read"],
    "deny": []
  }
}
```

---

## フィールド仕様

| フィールド | 型 | 必須 | デフォルト | 説明 |
|-----------|-----|:----:|-----------|------|
| `version` | Int | No | 1 | スキーマバージョン（将来の互換性用） |
| `permissions.allow` | [String] | Yes | - | 許可するパターンのリスト |
| `permissions.deny` | [String] | Yes | - | 拒否するパターンのリスト |
| `permissions.defaultAction` | String | No | "ask" | ルールにマッチしない場合のアクション |
| `permissions.enableSessionMemory` | Bool | No | true | 「常に許可」をセッション内で記憶するか |

### defaultAction の値

| 値 | 説明 |
|-----|------|
| `"allow"` | ルールにマッチしない場合は許可 |
| `"deny"` | ルールにマッチしない場合は拒否 |
| `"ask"` | ルールにマッチしない場合はユーザーに確認 |

---

## パターン構文

Claude Code互換のパターン構文をサポートします。

### 基本パターン

| パターン | マッチ対象 |
|---------|----------|
| `"Read"` | Read ツールの全ての呼び出し |
| `"Glob"` | Glob ツールの全ての呼び出し |
| `"*"` | 全てのツール |

### 引数パターン

| パターン | マッチ対象 |
|---------|----------|
| `"Bash(git:*)"` | `git` で始まるコマンド |
| `"Bash(git status)"` | 正確に `git status` コマンド |
| `"Bash(swift build:*)"` | `swift build` で始まるコマンド |
| `"Write(/tmp/*)"` | `/tmp/` 以下へのファイル書き込み |
| `"Read(/etc/*)"` | `/etc/` 以下のファイル読み込み |

### ワイルドカード

| パターン | マッチ対象 |
|---------|----------|
| `"mcp__*"` | 全てのMCPツール |
| `"mcp__github__*"` | github MCPサーバーの全ツール |

### 大文字小文字の区別

パターンマッチングは**大文字小文字を区別**します。

- `"Read"` は `Read` にマッチしますが、`read` にはマッチしません
- `"Bash*"` は `Bash` にマッチしますが、`bash` にはマッチしません

---

## API

### 読み込み

```swift
// URLから読み込み
let config = try PermissionConfiguration.load(from: url)

// Dataから読み込み
let config = try PermissionConfiguration.load(from: jsonData)
```

### 書き出し

```swift
// Dataにエンコード
let data = try config.encode()

// 文字列が必要な場合
let jsonString = String(data: data, encoding: .utf8)!
```

### マージ

```swift
// 2つの設定をマージ（後者が優先）
let merged = baseConfig.merged(with: overrideConfig)

// 複数の設定をマージ（後のものが優先）
let merged = PermissionConfiguration.merge([
    systemConfig,
    userConfig,
    projectConfig
])
```

**注意:** マージ時、重複するルールは自動的に除去されます（順序を保持し、最初の出現を維持）。

---

## 使用例

### 利用側プロジェクトでの実装例

```swift
import SwiftAgent

struct PermissionLoader {

    /// 設定ファイルの優先順位（後が優先）
    static let configPaths: [URL] = [
        // 1. システムデフォルト（バンドル）
        Bundle.main.url(forResource: "permissions", withExtension: "json"),

        // 2. ユーザー設定
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/myagent/permissions.json"),

        // 3. プロジェクト設定
        URL(fileURLWithPath: ".myagent/permissions.json")
    ].compactMap { $0 }

    /// 設定を読み込んでマージ
    static func load() throws -> PermissionConfiguration {
        var config = PermissionConfiguration.standard  // フォールバック

        for path in configPaths {
            guard FileManager.default.fileExists(atPath: path.path) else {
                continue
            }

            do {
                let fileConfig = try PermissionConfiguration.load(from: path)
                config = config.merged(with: fileConfig)
            } catch {
                print("Warning: Failed to load \(path): \(error)")
            }
        }

        return config
    }
}

// 使用
let config = try PermissionLoader.load()
    .withHandler(CLIPermissionHandler())  // handler はランタイムで設定

let agent = AgentConfiguration(...)
    .withSecurity(SecurityConfiguration(permissions: config))
```

### 設定ファイルの書き出し

```swift
// 現在の設定を保存
let config = PermissionConfiguration.standard
let data = try config.encode()

let savePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/myagent/permissions.json")

try FileManager.default.createDirectory(
    at: savePath.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try data.write(to: savePath)
```

---

## 制約事項

### シリアライズ不可な項目

以下のプロパティはJSONに含まれません：

| プロパティ | 理由 | 対処法 |
|-----------|------|--------|
| `handler` | プロトコル型のためシリアライズ不可 | ランタイムで `.withHandler()` を使用 |

### ルール評価順序

1. セッションメモリ（「常に許可」「ブロック」）
2. `allow` ルール（先頭から順にマッチを確認）
3. `deny` ルール（先頭から順にマッチを確認）
4. `defaultAction`

```
Tool呼び出し
    │
    ├─ セッションで「常に許可」済み？ ──→ 許可
    │
    ├─ セッションでブロック済み？ ─────→ 拒否
    │
    ├─ allow ルールにマッチ？ ─────────→ 許可
    │
    ├─ deny ルールにマッチ？ ──────────→ 拒否
    │
    └─ defaultAction を適用
           ├─ allow → 許可
           ├─ deny  → 拒否
           └─ ask   → ユーザーに確認
```

---

## スキーマバージョン

| version | 変更内容 |
|---------|---------|
| 1 | 初期バージョン |

将来のバージョンで破壊的変更がある場合、`version` フィールドを使用して互換性を管理します。

---

## Sandbox（macOS専用）

コマンド実行をサンドボックス内で制限します。`SandboxMiddleware` が `@Context` を通じて `ExecuteCommandTool` に設定を伝播します。

### SandboxExecutor.Configuration

```swift
let config = SandboxExecutor.Configuration(
    networkPolicy: .local,              // ネットワークポリシー
    filePolicy: .workingDirectoryOnly,  // ファイルアクセスポリシー
    allowSubprocesses: true             // サブプロセス許可
)
```

### NetworkPolicy

| ポリシー | 説明 |
|---------|------|
| `.none` | ネットワークアクセス完全拒否 |
| `.local` | localhost のみ許可 |
| `.full` | 全ネットワークアクセス許可 |

### FilePolicy

| ポリシー | 読み取り | 書き込み |
|---------|:--------:|:--------:|
| `.readOnly` | 全て許可 | 全て拒否 |
| `.workingDirectoryOnly` | 全て許可 | 作業ディレクトリ + /tmp |
| `.custom(read:write:)` | 指定パス + システムパス | 指定パス + /tmp |

### プリセット

```swift
// 標準：ローカルネットワーク、作業ディレクトリへの書き込み
SandboxExecutor.Configuration.standard

// 制限：ネットワークなし、読み取り専用
SandboxExecutor.Configuration.restrictive
```

### タイムアウト

- 最小: 0より大きい値
- 最大: 86400秒（24時間）
- デフォルト: 120秒

---

## withSecurity

`AgentConfiguration.withSecurity()` は単なる値の設定ではなく、ミドルウェアをパイプラインに追加する処理を実行します。

```swift
// 内部動作
public func withSecurity(_ security: SecurityConfiguration) -> AgentConfiguration {
    var copy = self

    // パイプラインがなければ作成
    if copy.toolPipeline == nil {
        copy.toolPipeline = ToolPipeline()
    }

    // ミドルウェアを正しい順序で追加
    copy.toolPipeline?.use(PermissionMiddleware(...))  // 先に権限チェック
    copy.toolPipeline?.use(SandboxMiddleware(...))     // 次にサンドボックス

    return copy
}
```

### プリセット

| プリセット | Permission | Sandbox |
|-----------|------------|---------|
| `.standard` | 対話的許可 | 標準サンドボックス |
| `.development` | 緩い許可 | なし |
| `.restrictive` | 最小限許可 | 制限的サンドボックス |
| `.readOnly` | 読み取り専用 | なし |

---

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) - SwiftAgent全体のドキュメント
- [SecurityConfiguration](../Sources/SwiftAgent/Security/) - セキュリティ設定のソースコード
