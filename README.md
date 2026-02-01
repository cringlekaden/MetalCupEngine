# MetalCup

MetalCup is a **modern real-time 3D rendering engine written in Swift using Apple’s Metal API**, targeting macOS on Apple Silicon.

The project focuses on physically based rendering, image-based lighting, and a clean, hackable architecture designed to evolve into a full engine + editor workflow.

MetalCup is developed as a standalone engine library, with the long-term goal of supporting an editor, scene serialization, and advanced rendering features.

> **Status:** Active development. APIs and architecture are still evolving.

---

## Demo

A short showcase of the current renderer is available here:

**YouTube:** https://youtu.be/YOUR_VIDEO_LINK_HERE

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
- Bloom post-processing
- ACES-style tone mapping + gamma correction

### Assets
- USDZ asset loading via ModelIO
- PBR texture support:
  - Base color
  - Normal
  - Metallic / Roughness (combined or separate)
  - Ambient occlusion
  - Emissive
- Fallback scalar material values
- Per-material feature flags

### Engine Structure
- Scene management system
- Game object / node hierarchy
- Render-to-texture pipeline
- Cubemap rendering passes
- Clean separation between rendering stages

---

## Planned Work

### Rendering
- Ray-traced shadows
- Improved specular occlusion
- Reflection probes
- Better post-processing pipeline
- Additional tone-mapping operators

### Engine Architecture
- Engine / Application / Layer stack
- Event system
- Editor application
- ImGui-based tooling
- Entity Component System (ECS)

### World & Content
- Terrain system
- Scene serialization format
- Asset pipeline improvements
- Material editor
- Lighting tools

---

## Requirements

- macOS 26 (only version tested so far)
- Apple Silicon Mac
- Xcode (recent version recommended)
- Swift + Metal

Earlier macOS versions may work but are not currently supported or tested.

---

## Building

1. Clone the repository:
   ```bash
   git clone https://github.com/cringlekaden/MetalCup.git```
2. Open the project in Xcode
3. Build & run on an Apple Silicon Mac
