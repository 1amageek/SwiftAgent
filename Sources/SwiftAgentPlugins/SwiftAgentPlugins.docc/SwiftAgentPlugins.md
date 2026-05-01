# ``SwiftAgentPlugins``

A manifest-based plugin system for distributing tools, prompts, and lifecycle
hooks alongside SwiftAgent applications.

## Overview

`SwiftAgentPlugins` complements `SwiftAgentSkills` (which is discovery-first
and unmanaged) with a *managed* plugin model. A plugin is described by a
``PluginManifest``, installed through ``PluginManager`` from a
``PluginInstallSource``, recorded as an ``InstalledPluginRecord``, and
exposed at runtime through ``PluginRegistry``.

Plugins can ship:

- **Tools** — wrapped through ``PluginToolAdapter`` so they appear as ordinary
  `any Tool` instances with ``PluginToolPermission`` enforcement.
- **Hooks** — pre-/post-tool callbacks executed by ``PluginHookRunner`` and
  ``PluginHookMiddleware`` so plugins can audit or amend tool calls.
- **Permissions** — declared via ``PluginPermission`` and applied through the
  same `PermissionRule` system used by the rest of SwiftAgent.

### Lifecycle

```text
PluginInstallSource → PluginManager.install
                        ↓
                 InstalledPluginRecord
                        ↓
                  PluginRegistry
                        ↓
   PluginToolAdapter ⇆ ToolPipeline (PluginHookMiddleware)
```

``PluginLifecycle`` records the resolution and load state of a plugin (e.g.
ready, disabled, failed) so registries can report partial outcomes via
``PluginRegistryReport``.

### Hooks

Hooks fire on ``PluginHookEvent`` boundaries (`willCallTool`, `didCallTool`,
etc.) and either annotate the call or short-circuit it via
``PluginHookError``. ``PluginHookMiddleware`` plugs into the same
`ToolMiddleware` pipeline used by permissions and sandboxing in `SwiftAgent`.

### Update Flow

``PluginUpdateOutcome`` and ``PluginInstallOutcome`` describe the result of
manager operations and surface manifest validation issues
(``PluginManifestValidationError``) in a structured form.

## Topics

### Manager

- ``PluginManager``
- ``PluginManagerConfig``

### Manifest and Records

- ``PluginManifest``
- ``InstalledPluginRecord``
- ``PluginInstallSource``
- ``PluginInstallOutcome``
- ``PluginUpdateOutcome``
- ``PluginManifestValidationError``

### Registry

- ``PluginRegistry``
- ``RegisteredPlugin``
- ``PluginSummary``
- ``PluginLoadFailure``
- ``PluginRegistryReport``
- ``PluginLifecycle``

### Tools

- ``PluginTool``
- ``PluginToolAdapter``
- ``PluginToolPermission``

### Hooks

- ``PluginHooks``
- ``PluginHookEvent``
- ``PluginHookRunner``
- ``PluginHookRunResult``
- ``PluginHookMiddleware``
- ``PluginHookError``

### Metadata

- ``PluginMetadata``
- ``PluginPermission``
- ``PluginJSONValue``

### Errors

- ``PluginError``
