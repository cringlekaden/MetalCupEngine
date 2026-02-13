# MetalCup Architecture

This document defines the project structure and how the MetalCup engine/editor integrate. Treat this as the source of truth for boundaries, ownership, and data flow.

## Repository Layout

- `MetalCupEngine/`
  - Swift framework that owns rendering, ECS, serialization, and runtime systems.
- `MetalCupEditor/`
  - macOS editor app that embeds the engine framework and provides the ImGui-based editor UI.
  - Project assets and templates live under `MetalCupEditor/MetalCupEditor/Projects/`.
- `MetalCupEditor/MetalCupEditor/ImGui/`
  - Vendor-only ImGui sources and official backends. No editor logic here.

## Engine (MetalCupEngine)

### Responsibilities
- Rendering pipeline (PBR, IBL, post-processing, tone mapping, bloom).
- ECS runtime, scene graph, and entity/component definitions.
- Scene serialization and deserialization.
- Runtime input/event systems.
- Renderer settings definition and default configuration.

### Key Areas
- `MetalCupEngine/Core/`
  - Renderer core, `RendererSettings`, and runtime configuration.
- `MetalCupEngine/Managers/`
  - `SceneManager` and scene lifecycle management.
- `MetalCupEngine/Serialization/`
  - Scene and renderer settings DTOs.
- `MetalCupEngine/Bridge/`
  - C-callable functions for editor UI to manipulate engine state.

### Data Ownership
- The engine owns all runtime state (render settings, ECS components, GPU resources).
- The editor reads and writes engine state through bridge calls or framework APIs.
- Renderer settings are engine-owned and serialization-ready.

## Editor (MetalCupEditor)

### Responsibilities
- Project management (open/save/recent projects).
- Asset discovery and metadata tracking.
- ImGui-based UI panels and tools.
- Persisted editor settings (panel visibility, headers, selection, layout).

### Structure
- `MetalCupEditor/MetalCupEditor/EditorCore/`
  - Core editor services and bridges.
  - `EditorCore/ImGui/` contains the ImGui layer and bridge that drive frame setup and UI composition.
  - `EditorCore/Services/` includes `EditorLogCenter`, `EditorSettingsStore`, `EditorUIState`, `EditorSelection`, and filesystem helpers.
  - `EditorCore/Assets/` includes `AssetRegistry`, `AssetIO`, `AssetOps`, and `AssetTypes`.
  - `EditorCore/Bridge/` contains C-callable bridge functions for ECS and renderer settings.
- `MetalCupEditor/MetalCupEditor/EditorUI/`
  - UI panels and widgets.
  - `EditorUI/Panels/` includes content browser, inspector, scene hierarchy, renderer, viewport, profiling, and logs panels.
  - `EditorUI/Widgets/` provides reusable ImGui widgets and layout helpers.

### Asset System
- `AssetRegistry`: in-memory registry of asset metadata and file watchers.
- `AssetIO`: asset serialization helpers (display name resolution, meta file utilities).
- `AssetOps`: file operations (create/rename/duplicate/delete) with logging and safety checks.
- `AssetTypes`: shared type classification and code mappings.

All asset mutations flow through `AssetOps` and log through `EditorLogCenter`.

### Editor State
- `EditorSettingsStore` persists editor state to Application Support.
- `EditorUIState` wraps settings for panel visibility and UI state.
- `EditorSelection` tracks the selected material and pending material editor requests.

## ImGui Integration

### Boundary Rules
- `MetalCupEditor/MetalCupEditor/ImGui/` is vendor-only: core Dear ImGui sources and official backends.
- Editor panels, widgets, and services live outside the vendor folder.
- If editor code is needed near the boundary, it lives under `EditorCore/ImGui/` as thin glue only.

### Flow
1. `ImGuiLayer` (Swift) is pushed into the engine layer stack.
2. `ImGuiLayer` calls `ImGuiBridge` each frame to start a new frame and build UI.
3. `ImGuiBridge` (ObjC++) configures ImGui, applies editor theme/fonts, and dispatches panel draws.
4. Panels call C-bridged editor/engine APIs (`EditorECSBridge`, `RendererSettingsBridge`, project services).

### Input
- ImGui input is handled by the official `imgui_impl_osx` backend.
- ImGui’s internal `KeyEventResponder` must stay in the responder chain for text input.

## Data Sharing: Engine <-> Editor

- Editor uses C-callable bridges to read and mutate engine state.
- Renderer settings are stored in `Renderer.settings` (engine) and exposed via `RendererSettingsBridge`.
- ECS state is manipulated via `EditorECSBridge` and `SceneManager` APIs.
- Scenes are serialized through engine serializers; editor initiates save/load via project actions.

## Data Sharing: Editor <-> ImGui

- `EditorCore/ImGui/ImGuiBridge.mm` is the only place that wires ImGui to editor panels.
- `EditorUI/Panels/` contains panel render functions and no ImGui lifecycle management.
- Shared ImGui widgets live in `EditorUI/Widgets/UIWidgets` and are reused across panels.

## Logging

- Use `EditorLogCenter` for all editor logs.
- Asset ops, project ops, and scene ops should log through `EditorLogCenter`.

## Extending the Project

### Add a panel
- Add a new `*.mm` in `EditorUI/Panels/` and expose a `ImGui*PanelDraw` function.
- Register and toggle in `ImGuiBridge.mm` (View menu + render pass).

### Add an asset type
- Update `AssetTypes.type(for:)` and any UI filters in panels.
- Ensure `AssetRegistry` recognizes the type and metadata.

### Add a renderer setting
- Add to `RendererSettings` in engine, expose in `RendererSettingsBridge`, then bind in `RendererPanel`.
