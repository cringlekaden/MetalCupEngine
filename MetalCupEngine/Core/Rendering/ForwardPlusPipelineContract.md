# Forward+ Pipeline Contract

This document defines the minimum contract for the Forward+ render path.

## 1) Snapshot-only render rule

- Render graph execution must consume `RenderFrameSnapshot` + per-frame/per-view render context only.
- Render passes and `SceneRenderer` must not traverse live ECS or scene managers during rendering.
- Snapshot preparation (`SceneRenderer.prepareRenderFrameSnapshot(...)`) happens before graph execution, once per view per frame.

## 2) Depth dependency rule

- `LightCullingPass` always requires a depth input (`forwardPlus.cullingDepth`).
- Depth is produced before culling by either:
  - `DepthPrepassPass` when depth prepass is enabled, or
  - `CullingDepthFallbackPass` when depth prepass is disabled.
- Culling must not run without this depth contract resource.

## 3) Produced Forward+ resources

`LightCullingPass` produces these per-frame transient resources:

- `forwardPlus.lightGrid` (buffer): per-cluster `{offset, count}` entries.
- `forwardPlus.lightIndexList` (buffer): packed light indices.
- `forwardPlus.lightIndexCount` (buffer): index header/counters.
- `forwardPlus.clusterParams` (buffer): ABI/version + tile/cluster params.

## 4) Consumers

- `ScenePass` (fragment path) consumes all Forward+ buffers via `LightingInputs`.
- Heatmap debug mode (`DebugLightHeatmap`) uses the same cluster resolution path as lighting.

## 5) ABI + config

- ABI version is defined by `ForwardPlusConfig.abiVersion` and mirrored in Swift/MSL structs.
- Core culling config lives in `ForwardPlusConfig`:
  - `tileSizeX`, `tileSizeY`, `zSliceCount`, `maxLightsPerCluster`, `configVersion`.
- Scene render batch cache keys include a Forward+ culling config signature to prevent stale reuse when config/toggle changes.
