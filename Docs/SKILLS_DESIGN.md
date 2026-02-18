# SwiftAgent Skills System Design

## 1. Overview

Agent Skills は、AIエージェントに新しい能力を与えるためのシンプルでオープンなフォーマットです。
SwiftAgent に Skills サポートを追加することで、外部で定義されたスキルを発見・読み込み・実行できるようになります。

### 1.1 Goals

- Agent Skills 仕様に準拠した SKILL.md ファイルの読み込み
- Progressive Disclosure による効率的なコンテキスト管理
- 既存の SwiftAgent アーキテクチャとの自然な統合
- Cursor, Claude Code, VS Code などの Skills 対応ツールとの相互運用性

### 1.2 Non-Goals

- スキル作成ツールの提供（別モジュールで対応可能）
- スキル内スクリプトの自動実行（セキュリティ上、ツール経由で実行）
- リモートスキルリポジトリへの接続

## 2. Agent Skills Format

### 2.1 Directory Structure

```
skill-name/
├── SKILL.md          # Required: メタデータ + 指示
├── scripts/          # Optional: 実行可能コード
├── references/       # Optional: 追加ドキュメント
└── assets/           # Optional: テンプレート、リソース
```

### 2.2 SKILL.md Format

```yaml
---
name: skill-name                    # Required: 1-64文字、小文字英数字とハイフンのみ
description: What this skill does   # Required: 1-1024文字
license: Apache-2.0                 # Optional: ライセンス
compatibility: Requires git, jq     # Optional: 環境要件（最大500文字）
metadata:                           # Optional: カスタムメタデータ
  author: example-org
  version: "1.0"
allowed-tools: Bash(git:*) Read     # Optional: 事前承認済みツール
---

# Skill Instructions (Markdown)

Instructions for the agent...
```

### 2.3 Progressive Disclosure Model

1. **Discovery**: 起動時に `name` と `description` のみ読み込み（~100 tokens/skill）
2. **Activation**: タスクにマッチしたら `SKILL.md` 全体を読み込み（< 5000 tokens 推奨）
3. **Execution**: 必要に応じて `scripts/`, `references/`, `assets/` を参照

## 3. Architecture

### 3.1 Component Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Conversation                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────────────────────┐ │
│  │  SkillRegistry  │  │SkillPermissions │  │      ToolPipeline             │ │
│  │                 │  │                 │  │ ┌─────────────────────────┐   │ │
│  │  - skills       │  │ - rulesBySkill  │◄─┼─│  PermissionMiddleware   │   │ │
│  │  - activeSkills │  │ - ruleRefCount  │  │ │  (dynamicRulesProvider) │   │ │
│  └────────┬────────┘  └────────┬────────┘  │ └─────────────────────────┘   │ │
│           │                    │           └───────────────────────────────┘ │
│           │           ┌────────┴─────────┐                                   │
│           │           │                  │                                   │
│           ▼           ▼                  │                                   │
│     ┌───────────────────┐                │                                   │
│     │    SkillTool      │────────────────┘                                   │
│     │  - registry       │   allowed-tools → SkillPermissions                 │
│     │  - permissions    │                                                    │
│     └───────────────────┘                                                    │
└──────────────────────────────────────────────────────────────────────────────┘
                    │
       ┌────────────┴────────────┐
       │                         │
 ┌─────┴─────┐           ┌───────┴───────┐
 │  Skill    │           │ SkillDiscovery│
 │ (struct)  │           │               │
 └─────┬─────┘           └───────────────┘
       │
 ┌─────┴─────┐
 │SkillLoader│
 └─────┬─────┘
       │
 ┌─────┴─────┐
 │SKILL.md   │
 │(filesystem)│
 └───────────┘
```

### 3.2 Data Flow

```
1. Discovery Phase
   SkillDiscovery.discover()
        │
        ▼
   SkillLoader.loadMetadata(path)  ←─── SKILL.md の frontmatter のみパース
        │
        ▼
   SkillRegistry.register(skill)   ←─── name + description を保持

2. Session Creation
   Conversation.create()
        │
        ├─→ SkillPermissions 作成
        │
        ├─→ ToolPipeline.withDynamicPermissions { skillPermissions.rules }
        │
        ├─→ SkillTool(registry, permissions: skillPermissions)
        │
        ▼
   SkillRegistry.generateAvailableSkillsPrompt()
        │
        ▼
   <available_skills> XML をシステムプロンプトに注入

3. Activation Phase (LLM が Skill Tool を呼び出した時)
   SkillTool.call(name: "pdf-processing")
        │
        ▼
   SkillRegistry.activate(name)
        │
        ▼
   SkillLoader.loadFull(path)      ←─── SKILL.md 全体をパース
        │
        ├─→ allowed-tools がある場合:
        │   PermissionRule.parse(allowedTools)
        │        │
        │        ▼
        │   SkillPermissions.add(rules, from: skillName)
        │
        ▼
   Skill.instructions を返却       ←─── LLM コンテキストに追加

4. Permission Evaluation (ツール実行時)
   PermissionMiddleware.handle(context)
        │
        ├─→ effectiveConfiguration()
        │        │
        │        ▼
        │   dynamicRulesProvider() ─→ SkillPermissions.rules
        │        │
        │        ▼
        │   Allow List にスキルのルールを追加
        │
        ▼
   ルール評価: FinalDeny → Memory → Override → Deny → Allow → Default
```

## 4. Component Design

### 4.1 SkillMetadata

SKILL.md の YAML frontmatter を表現する構造体。

```swift
/// Metadata from SKILL.md frontmatter.
public struct SkillMetadata: Sendable, Codable, Equatable {

    // MARK: - Required Fields

    /// Skill name (1-64 chars, lowercase alphanumeric + hyphens).
    public let name: String

    /// Description of what the skill does (1-1024 chars).
    public let description: String

    // MARK: - Optional Fields

    /// License information.
    public let license: String?

    /// Environment compatibility requirements (max 500 chars).
    public let compatibility: String?

    /// Custom metadata key-value pairs.
    public let metadata: [String: String]?

    /// Space-delimited list of pre-approved tools.
    public let allowedTools: String?
}
```

**Validation Rules:**
- `name`: 1-64文字、`^[a-z0-9]+(-[a-z0-9]+)*$` にマッチ、ディレクトリ名と一致
- `description`: 1-1024文字、空でない
- `compatibility`: 存在する場合 1-500文字
- `allowedTools`: スペース区切りのツール識別子

### 4.2 Skill

スキルの完全な情報を保持する構造体。

```swift
/// A loaded skill with metadata and instructions.
public struct Skill: Identifiable, Sendable {

    /// Unique identifier (same as name).
    public var id: String { metadata.name }

    /// Skill metadata from frontmatter.
    public let metadata: SkillMetadata

    /// Full instructions (Markdown body).
    /// Nil if only metadata has been loaded (discovery phase).
    public let instructions: String?

    /// Absolute path to the skill directory.
    public let directoryPath: String

    /// Path to SKILL.md file.
    public var skillFilePath: String {
        (directoryPath as NSString).appendingPathComponent("SKILL.md")
    }

    // MARK: - Resource Access

    /// Whether the skill has a scripts directory.
    public var hasScripts: Bool

    /// Whether the skill has a references directory.
    public var hasReferences: Bool

    /// Whether the skill has an assets directory.
    public var hasAssets: Bool

    /// Get path to a resource within the skill.
    public func resourcePath(_ relativePath: String) -> String
}
```

**Design Notes:**
- `instructions` が `nil` の場合は Discovery Phase（メタデータのみ）
- `instructions` が存在する場合は Activation 済み
- リソースパスは相対パスで指定し、`resourcePath()` で絶対パスに変換

### 4.3 SkillLoader

SKILL.md ファイルをパースするユーティリティ。

```swift
/// Loads and parses SKILL.md files.
public struct SkillLoader: Sendable {

    /// Load only metadata from a SKILL.md file (discovery phase).
    ///
    /// - Parameter directoryPath: Path to the skill directory.
    /// - Returns: Skill with metadata only (instructions = nil).
    /// - Throws: `SkillError` if loading fails.
    public static func loadMetadata(
        from directoryPath: String
    ) throws -> Skill

    /// Load full skill including instructions (activation phase).
    ///
    /// - Parameter directoryPath: Path to the skill directory.
    /// - Returns: Skill with full instructions.
    /// - Throws: `SkillError` if loading fails.
    public static func loadFull(
        from directoryPath: String
    ) throws -> Skill

    /// Parse YAML frontmatter from SKILL.md content.
    ///
    /// - Parameter content: Raw SKILL.md file content.
    /// - Returns: Tuple of (metadata, body).
    /// - Throws: `SkillError.invalidFormat` if parsing fails.
    internal static func parseFrontmatter(
        _ content: String
    ) throws -> (metadata: SkillMetadata, body: String)

    /// Validate skill metadata.
    ///
    /// - Parameters:
    ///   - metadata: The metadata to validate.
    ///   - directoryName: The skill directory name.
    /// - Throws: `SkillError.validationFailed` if validation fails.
    internal static func validate(
        _ metadata: SkillMetadata,
        directoryName: String
    ) throws
}
```

**Implementation Notes:**
- YAML パースには `Yams` ライブラリを使用（SPM で追加）
- frontmatter は `---` で囲まれた部分
- `loadMetadata` では body 部分を読み込まない（効率化）

### 4.4 SkillRegistry

スキルの登録・管理・活性化を行う Actor。

```swift
/// Registry for managing discovered skills.
public actor SkillRegistry {

    // MARK: - State

    /// All registered skills (metadata only initially).
    private var skills: [String: Skill] = [:]

    /// Currently activated skills (full instructions loaded).
    private var activeSkills: Set<String> = []

    // MARK: - Initialization

    /// Creates an empty registry.
    public init()

    /// Creates a registry and discovers skills from standard paths.
    public init(discoverFromStandardPaths: Bool) async throws

    // MARK: - Registration

    /// Register a skill.
    public func register(_ skill: Skill)

    /// Register multiple skills.
    public func register(_ skills: [Skill])

    /// Unregister a skill by name.
    @discardableResult
    public func unregister(_ name: String) -> Skill?

    // MARK: - Retrieval

    /// Get a skill by name.
    public func get(_ name: String) -> Skill?

    /// Get all registered skill names.
    public var registeredNames: [String]

    /// Get all registered skills.
    public var allSkills: [Skill]

    /// Check if a skill is registered.
    public func contains(_ name: String) -> Bool

    /// Number of registered skills.
    public var count: Int

    // MARK: - Activation

    /// Activate a skill (load full instructions).
    ///
    /// - Parameter name: The skill name.
    /// - Returns: The activated skill with full instructions.
    /// - Throws: `SkillError.skillNotFound` or loading errors.
    public func activate(_ name: String) throws -> Skill

    /// Deactivate a skill (free instructions from memory).
    public func deactivate(_ name: String)

    /// Check if a skill is active.
    public func isActive(_ name: String) -> Bool

    /// Get all active skill names.
    public var activeSkillNames: [String]

    // MARK: - Prompt Generation

    /// Generate <available_skills> XML for system prompt.
    ///
    /// This includes only name and description for each skill.
    public func generateAvailableSkillsPrompt() -> String

    /// Generate full instructions for active skills.
    ///
    /// Used when injecting active skill context into prompts.
    public func generateActiveSkillsPrompt() -> String
}
```

**Example Output:**

```xml
<available_skills>
  <skill>
    <name>pdf-processing</name>
    <description>Extract text and tables from PDF files, fill forms, merge documents.</description>
    <location>/Users/me/.agent/skills/pdf-processing/SKILL.md</location>
  </skill>
  <skill>
    <name>data-analysis</name>
    <description>Analyze datasets, generate charts, and create summary reports.</description>
    <location>/Users/me/.agent/skills/data-analysis/SKILL.md</location>
  </skill>
</available_skills>
```

### 4.5 SkillDiscovery

標準パスからスキルを発見するユーティリティ。

```swift
/// Discovers skills from standard directories.
public struct SkillDiscovery: Sendable {

    /// Standard skill discovery paths.
    public static let standardPaths: [String] = [
        "~/.agent/skills",           // User-level skills
        "./.agent/skills",           // Project-level skills
    ]

    /// Environment variable for additional paths.
    public static let environmentVariable = "AGENT_SKILLS_PATH"

    /// Discover all skills from standard paths.
    ///
    /// - Returns: Array of discovered skills (metadata only).
    public static func discoverAll() throws -> [Skill]

    /// Discover skills from a specific directory.
    ///
    /// - Parameter path: Directory to search for skills.
    /// - Returns: Array of discovered skills.
    public static func discover(in path: String) throws -> [Skill]

    /// Get all configured search paths.
    ///
    /// Includes standard paths and paths from environment variable.
    public static func searchPaths() -> [String]

    /// Check if a directory is a valid skill directory.
    ///
    /// - Parameter path: Directory path to check.
    /// - Returns: true if directory contains SKILL.md.
    public static func isSkillDirectory(_ path: String) -> Bool
}
```

**Search Order:**
1. `~/.agent/skills/` - ユーザーレベル
2. `./.agent/skills/` - プロジェクトレベル（カレントディレクトリ基準）
3. `$AGENT_SKILLS_PATH` - 環境変数で指定（コロン区切り）

### 4.6 SkillError

スキル関連のエラー。

```swift
/// Errors that can occur during skill operations.
public enum SkillError: Error, LocalizedError {

    /// Skill directory not found.
    case skillDirectoryNotFound(path: String)

    /// SKILL.md file not found.
    case skillFileNotFound(path: String)

    /// Invalid SKILL.md format.
    case invalidFormat(reason: String)

    /// Validation failed.
    case validationFailed(field: String, reason: String)

    /// Skill not found in registry.
    case skillNotFound(name: String)

    /// Skill already exists.
    case skillAlreadyExists(name: String)

    /// Failed to read file.
    case fileReadError(path: String, underlyingError: Error)

    /// YAML parsing error.
    case yamlParsingError(reason: String)

    public var errorDescription: String? { ... }
}
```

### 4.7 SkillTool

LLM がスキルを活性化するためのツール。

```swift
/// Tool for activating skills.
///
/// This tool allows the LLM to load a skill's full instructions
/// when it determines a skill is relevant to the current task.
/// When activated, the skill's allowed-tools are automatically
/// added to the session's permission allow list.
public struct SkillTool: Tool {

    public typealias Arguments = SkillToolArguments

    public let name = "activate_skill"

    public let description = """
        Activate a skill to load its full instructions.
        Use this when you determine a skill from <available_skills> is relevant
        to the current task.
        """

    private let registry: SkillRegistry
    private let permissions: SkillPermissions?

    public init(registry: SkillRegistry, permissions: SkillPermissions? = nil) {
        self.registry = registry
        self.permissions = permissions
    }

    public func call(arguments: SkillToolArguments) async throws -> SkillToolOutput {
        let skill = try await registry.activate(arguments.skillName)

        // Add skill's allowed-tools to permission allow list
        if let allowedToolsString = skill.metadata.allowedTools,
           let permissions = self.permissions {
            let rules = PermissionRule.parse(allowedToolsString)
            if !rules.isEmpty {
                permissions.add(rules, from: skill.metadata.name)
            }
        }

        return SkillToolOutput(
            skillName: skill.metadata.name,
            instructions: skill.instructions ?? "",
            resourcesAvailable: SkillToolOutput.Resources(
                hasScripts: skill.hasScripts,
                hasReferences: skill.hasReferences,
                hasAssets: skill.hasAssets
            )
        )
    }
}

@Generable
public struct SkillToolArguments: Sendable {
    @Guide(description: "The name of the skill to activate")
    public let skillName: String
}

public struct SkillToolOutput: Sendable, PromptRepresentable {
    public let skillName: String
    public let instructions: String
    public let resourcesAvailable: Resources

    public struct Resources: Sendable {
        public let hasScripts: Bool
        public let hasReferences: Bool
        public let hasAssets: Bool
    }

    public var promptRepresentation: Prompt {
        Prompt("""
            # Skill Activated: \(skillName)

            \(instructions)

            ## Available Resources
            - Scripts: \(hasScripts ? "yes" : "no")
            - References: \(hasReferences ? "yes" : "no")
            - Assets: \(hasAssets ? "yes" : "no")
            """)
    }
}
```

### 4.8 SkillPermissions

スキルから付与されたパーミッションを管理するスレッドセーフなコンテナ。

```swift
/// Holds permission rules granted by activated skills.
///
/// This class accumulates permission rules from skills as they are activated
/// during a session. The rules are added to the allow list when evaluating
/// tool permissions.
///
/// ## Usage
///
/// ```swift
/// let permissions = SkillPermissions()
///
/// // When a skill is activated, add its allowed-tools
/// let rules = PermissionRule.parse("Bash(git:*) Read")
/// permissions.add(rules, from: "git-workflow")
///
/// // PermissionMiddleware reads these rules
/// let allowedRules = permissions.rules
/// ```
///
/// ## Reference Counting
///
/// If multiple skills grant the same permission, the permission remains active
/// until all skills that granted it are removed. This prevents one skill's
/// deactivation from revoking permissions still needed by another skill.
public final class SkillPermissions: @unchecked Sendable {

    private let lock = NSLock()
    private var _rulesBySkill: [String: [PermissionRule]] = [:]
    private var _ruleRefCount: [String: Int] = [:]

    public init() {}

    /// The accumulated permission rules from all activated skills.
    ///
    /// Returns unique rules - if multiple skills grant the same pattern,
    /// it appears only once in the result.
    public var rules: [PermissionRule] {
        lock.withLock {
            Array(_ruleRefCount.keys).map { PermissionRule($0) }
        }
    }

    /// Adds permission rules from a specific skill.
    public func add(_ rules: [PermissionRule], from skillName: String) {
        guard !rules.isEmpty else { return }
        lock.withLock {
            _rulesBySkill[skillName, default: []].append(contentsOf: rules)
            for rule in rules {
                _ruleRefCount[rule.pattern, default: 0] += 1
            }
        }
    }

    /// Removes all permission rules granted by a specific skill.
    ///
    /// If another skill also granted the same permission, it remains active.
    public func remove(from skillName: String) {
        lock.withLock {
            guard let skillRules = _rulesBySkill.removeValue(forKey: skillName) else { return }
            for rule in skillRules {
                if let count = _ruleRefCount[rule.pattern] {
                    if count <= 1 {
                        _ruleRefCount.removeValue(forKey: rule.pattern)
                    } else {
                        _ruleRefCount[rule.pattern] = count - 1
                    }
                }
            }
        }
    }

    /// Returns permission rules granted by a specific skill.
    public func rules(from skillName: String) -> [PermissionRule]

    /// The names of skills that have granted permissions.
    public var skillNames: [String]

    /// Clears all permission rules.
    public func clear()
}
```

**Design Notes:**

- **スレッドセーフ**: `NSLock` による排他制御
- **参照カウント**: 複数スキルが同じパーミッションを付与した場合、全スキルが解除されるまで有効
- **スキル単位の追跡**: どのスキルがどのパーミッションを付与したかを記録

## 5. Integration with AgentConfiguration

### 5.1 Configuration Changes

```swift
public struct AgentConfiguration: Sendable {

    // ... existing properties ...

    // MARK: - Skills

    /// Skill registry for this agent.
    /// If nil, skills are disabled.
    public var skillRegistry: SkillRegistry?

    /// Whether to automatically discover skills from standard paths.
    public var autoDiscoverSkills: Bool

    /// Additional skill search paths.
    public var skillSearchPaths: [String]

    // MARK: - Initialization

    public init(
        // ... existing parameters ...
        skillRegistry: SkillRegistry? = nil,
        autoDiscoverSkills: Bool = true,
        skillSearchPaths: [String] = []
    ) { ... }
}
```

### 5.2 Builder Pattern Extension

```swift
extension AgentConfiguration {

    /// Returns a copy with skills enabled.
    public func withSkills(
        registry: SkillRegistry? = nil,
        autoDiscover: Bool = true,
        additionalPaths: [String] = []
    ) -> AgentConfiguration {
        var copy = self
        copy.skillRegistry = registry
        copy.autoDiscoverSkills = autoDiscover
        copy.skillSearchPaths = additionalPaths
        return copy
    }

    /// Returns a copy with skills disabled.
    public func withoutSkills() -> AgentConfiguration {
        var copy = self
        copy.skillRegistry = nil
        copy.autoDiscoverSkills = false
        return copy
    }
}
```

## 6. Integration with Conversation

### 6.1 Session Creation Changes

```swift
public actor Conversation {

    // ... existing properties ...

    /// The skill registry.
    private let skillRegistry: SkillRegistry?

    public static func create(
        configuration: AgentConfiguration
    ) async throws -> Conversation {
        // ... existing code ...

        // Initialize skill registry
        let skillRegistry: SkillRegistry?
        if configuration.autoDiscoverSkills || configuration.skillRegistry != nil {
            skillRegistry = configuration.skillRegistry ?? SkillRegistry()

            if configuration.autoDiscoverSkills {
                // Discover from standard paths
                let discoveredSkills = try SkillDiscovery.discoverAll()
                await skillRegistry!.register(discoveredSkills)

                // Discover from additional paths
                for path in configuration.skillSearchPaths {
                    let skills = try SkillDiscovery.discover(in: path)
                    await skillRegistry!.register(skills)
                }
            }
        } else {
            skillRegistry = nil
        }

        // Build instructions with skill info
        var instructionsText = configuration.instructions.description

        // Add available skills prompt
        if let registry = skillRegistry {
            let skillsPrompt = await registry.generateAvailableSkillsPrompt()
            if !skillsPrompt.isEmpty {
                instructionsText += "\n\n" + skillsPrompt
            }
        }

        // ... rest of session creation ...
    }
}
```

### 6.2 Skill-Related Methods

```swift
extension Conversation {

    /// Lists available skills.
    public func listSkills() async -> [Skill] {
        guard let registry = skillRegistry else { return [] }
        return await registry.allSkills
    }

    /// Activates a skill by name.
    public func activateSkill(_ name: String) async throws -> Skill {
        guard let registry = skillRegistry else {
            throw SkillError.skillNotFound(name: name)
        }
        return try await registry.activate(name)
    }

    /// Deactivates a skill.
    public func deactivateSkill(_ name: String) async {
        await skillRegistry?.deactivate(name)
    }

    /// Gets currently active skills.
    public func activeSkills() async -> [String] {
        guard let registry = skillRegistry else { return [] }
        return await registry.activeSkillNames
    }
}
```

## 7. File Structure

```
Sources/SwiftAgentSkills/
├── SkillMetadata.swift      # YAML frontmatter 構造体
├── Skill.swift              # スキル構造体
├── SkillError.swift         # エラー定義
├── SkillLoader.swift        # SKILL.md パーサー
├── SkillRegistry.swift      # スキル管理 Actor
├── SkillDiscovery.swift     # スキル発見
├── SkillTool.swift          # LLM 用ツール
└── SkillPermissions.swift   # パーミッション管理

Sources/SwiftAgent/
├── Security/
│   ├── PermissionMiddleware.swift  # dynamicRulesProvider 対応
│   └── PermissionRule.swift        # parse() メソッド追加
├── Middleware/
│   └── ToolPipeline.swift          # withDynamicPermissions() 追加
└── ...
```

## 8. Dependencies

### 8.1 New Dependencies

```swift
// Package.swift
dependencies: [
    // ... existing dependencies ...
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
]

targets: [
    .target(
        name: "SwiftAgent",
        dependencies: [
            // ... existing dependencies ...
            "Yams",
        ]
    ),
]
```

### 8.2 Dependency Justification

- **Yams**: YAML パースのデファクトスタンダード。SKILL.md の frontmatter をパースするために必要。

## 9. Usage Examples

### 9.1 Basic Usage

```swift
import SwiftAgent

// Create configuration with skills enabled
let config = AgentConfiguration(
    instructions: Instructions("You are a helpful assistant."),
    modelProvider: myModelProvider,
    autoDiscoverSkills: true  // Discovers from ~/.agent/skills/ etc.
)

// Create session
let session = try await Conversation.create(configuration: config)

// List available skills
let skills = await session.listSkills()
for skill in skills {
    print("- \(skill.metadata.name): \(skill.metadata.description)")
}

// The LLM can now see available skills and activate them as needed
let response = try await session.prompt("Help me process this PDF document")
```

### 9.2 Manual Skill Registration

```swift
// Create skill registry manually
let registry = SkillRegistry()

// Load a specific skill
let skill = try SkillLoader.loadMetadata(from: "/path/to/my-skill")
await registry.register(skill)

// Create session with the registry
let config = AgentConfiguration(
    instructions: Instructions("You are a helpful assistant."),
    modelProvider: myModelProvider,
    skillRegistry: registry,
    autoDiscoverSkills: false
)
```

### 9.3 Custom Search Paths

```swift
let config = AgentConfiguration(
    instructions: Instructions("You are a helpful assistant."),
    modelProvider: myModelProvider,
    autoDiscoverSkills: true,
    skillSearchPaths: [
        "/opt/company-skills",
        "/home/shared/team-skills"
    ]
)
```

## 10. Security Considerations

### 10.1 Script Execution

- スキル内の `scripts/` は直接実行しない
- LLM が `ExecuteCommandTool` などを通じて実行する
- 既存の `PermissionMiddleware` で制御可能

### 10.2 File Access

- `references/` と `assets/` は `ReadTool` を通じて読み取り
- 既存の権限システムで制御

### 10.3 Allowed Tools Permission Integration

スキルの `allowed-tools` フィールドは、スキル活性化時に自動的にパーミッションシステムと統合されます。

**アーキテクチャ:**

```
スキル活性化
    │
    ▼
SkillTool.call()
    │
    ├─→ SkillPermissions.add(rules, from: skillName)
    │
    ▼
PermissionMiddleware.effectiveConfiguration()
    │
    ├─→ dynamicRulesProvider() ─→ SkillPermissions.rules
    │
    ▼
Allow List に追加（Deny の後に評価）
```

**評価順序（重要）:**

```
1. Final Deny (絶対禁止 - スキルでもバイパス不可)
2. Session Memory
3. Override
4. Deny (通常禁止)
5. Allow (静的ルール + スキルからの動的ルール)  ← スキルはここに追加
6. Default Action
```

**セキュリティ保証:**

- スキルは `deny` や `finalDeny` ルールをバイパスできない
- スキルは `defaultAction: .ask` の場合にユーザー確認をスキップできる
- 複数スキルが同じパーミッションを付与した場合、参照カウントで管理

**例:**

```yaml
# SKILL.md
---
name: git-workflow
allowed-tools: Bash(git:*) Read
---
```

```swift
// スキル活性化時
let skill = try await registry.activate("git-workflow")
// → SkillPermissions に "Bash(git:*)" と "Read" が追加
// → 以降の git コマンドと Read ツールはユーザー確認なしで実行可能
// → ただし Deny("Bash(git push:*)") があれば、それは依然として拒否される
```

**SkillPermissions と PermissionMiddleware の連携:**

```swift
// セッション作成時
let skillPermissions = SkillPermissions()

// ToolPipeline に動的ルールプロバイダーを注入
let pipeline = basePipeline.withDynamicPermissions {
    skillPermissions.rules
}

// SkillTool に SkillPermissions を渡す
let skillTool = SkillTool(registry: registry, permissions: skillPermissions)
```

## 11. Future Enhancements

1. **Skill Versioning**: 複数バージョンのスキルを管理
2. **Remote Skills**: リモートリポジトリからのスキル取得
3. **Skill Dependencies**: スキル間の依存関係管理
4. **Skill Caching**: 頻繁に使用するスキルのキャッシュ
5. **Skill Analytics**: スキル使用状況の追跡

## 12. Testing Strategy

### 12.1 Unit Tests

- `SkillLoader` のパース処理
- `SkillMetadata` のバリデーション
- `SkillRegistry` の登録・活性化・解除

### 12.2 Integration Tests

- `SkillDiscovery` のディレクトリスキャン
- `Conversation` へのスキル統合
- `SkillTool` の実行

### 12.3 Test Fixtures

```
Tests/SwiftAgentTests/Fixtures/Skills/
├── valid-skill/
│   ├── SKILL.md
│   ├── scripts/
│   │   └── example.py
│   └── references/
│       └── REFERENCE.md
├── minimal-skill/
│   └── SKILL.md
├── invalid-name-skill/
│   └── SKILL.md  # name doesn't match directory
└── invalid-format/
    └── SKILL.md  # malformed YAML
```
