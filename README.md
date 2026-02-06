# MetalCup

MetalCup is a **modern real-time 3D rendering engine written in Swift using Apple’s Metal API**, targeting macOS on Apple Silicon.

The project focuses on physically based rendering, image-based lighting, and a clean, hackable architecture designed to evolve into a full engine + editor workflow.

MetalCup is developed as a **standalone engine framework**, intended to be embedded into other applications (such as the MetalCup Editor).

> **Status:** Active development. APIs, architecture, and systems are still evolving.

---

## Demo

A short showcase of the renderer is available here:

**YouTube:** https://youtu.be/Hbr0vGU27Jw

The demo highlights:
- Physically based materials
- Image-based lighting
- Specular reflections
- Emissive materials with bloom
- HDR rendering and tone mapping

---

## Current Features

### Rendering
- Metal-based renderer (no third-party libraries)
- HDR rendering pipeline
- Physically Based Rendering (metal/roughness workflow)
- Image-Based Lighting (IBL)
  - Environment cubemap generation
  - Irradiance map
  - Prefiltered specular cubemap
  - BRDF LUT
- Normal mapping
- Emissive materials
- Configurable bloom post-processing
- Configurable tone mapping, gamma correction, and exposure

> An environment / skybox is **optional**. In the future we will offer a dynamic/generated sky in place of environment asset.
> IBL is applied when an environment exists, but future lighting will also support purely analytic lights.

### Assets
- USDZ asset loading via ModelIO
- Automated asset importing
- Asset directory scanning
- Per-asset meta file generation
- Asset handles used internally by the engine
- PBR texture support:
  - Base color
  - Normal
  - Metallic / Roughness (combined or separate)
  - Ambient occlusion
  - Emissive
- Fallback scalar material values
- Per-material feature flags

### Engine Structure
- Built as a reusable **engine framework**
- Scene management system (changes soon)
- Game object / node hierarchy (changes soon)
- Render-to-texture pipeline
- Cubemap rendering passes
- Clean separation between rendering stages
- Runtime decoupled from editor/UI concerns

---

## Planned Work

### Rendering
- Directional light support
- Point lights with attenuation (in progress, working)
- Spot lights
- IBL as an additive lighting component
- Ray-traced shadows
- Improved specular occlusion
- Reflection probes
- Improved post-processing pipeline
- Additional tone-mapping operators

### Engine Architecture
- Entity Component System (ECS)
- Engine / Application / Layer stack (in progress)
- Event system (in progress)
- Serialization support
- Improved runtime/editor boundaries

### World & Content
- Scene serialization format
- Asset pipeline improvements
- Material system extensions
- Lighting tools and utilities

---

## Requirements

- macOS 26 (only version tested so far)
- Apple Silicon Mac
- Xcode (recent version recommended)
- Swift + Metal

Earlier macOS versions may work but are not currently supported or tested.

---

## Building

1. Clone the repository: ```git clone https://github.com/cringlekaden/MetalCupEngine.git```
2. Open the project in Xcode
3. Build the engine framework target

The framework is intended to be consumed by another application (such as the MetalCup Editor).

---

## License

MIT License. Use the code however you like. No warranties.
