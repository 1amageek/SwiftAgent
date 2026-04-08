# SwiftAgent Plugins

SwiftAgent runtime plugins follow the same manifest contract as `claw-code`.

## What plugins can do

- Contribute validated tool definitions
- Register `PreToolUse`, `PostToolUse`, and `PostToolUseFailure` hooks
- Run `Init` and `Shutdown` lifecycle commands

## What plugins do not do

- They do not manage skills
- They do not import MCP servers from `plugin.json`
- They do not load plugin-managed agent catalogs

Those constraints intentionally match `claw-code`.

## Supported manifest locations

- `plugin.json`
- `.claude-plugin/plugin.json`

## Supported manifest fields

- `name`
- `version`
- `description`
- `permissions`
- `defaultEnabled`
- `hooks`
- `lifecycle`
- `tools`
- `commands`

## Unsupported Claude Code contract fields

- `skills`
- `mcpServers`
- `agents`
- string-array `commands` catalogs

## Runtime usage

```swift
let manager = PluginManager(
    configuration: PluginManagerConfig(
        externalRoots: ["/path/to/plugin"]
    )
)

let report = try manager.loadRegistryReport()
let registry = try report.intoRegistry()

let tools = try registry.aggregatedSwiftAgentTools()
```
