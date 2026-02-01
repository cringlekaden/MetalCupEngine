# MetalCup ☕️

MetalCup is a **personal 3D rendering engine written in Swift using Apple’s Metal API**, built from scratch on macOS.

The project focuses on **modern physically based rendering techniques**, clean architecture, and deep understanding of the Metal graphics pipeline on Apple Silicon.

This is a long-term learning and experimentation project with the eventual goal of evolving into a small but capable game / rendering engine with tooling support.

---

## 🎥 Demo / Showcase

👉 **YouTube Demo:**  
https://www.youtube.com/watch?v=Hbr0vGU27Jw

The demo showcases:
- Physically Based Rendering (PBR)
- Image-Based Lighting (IBL)
- HDR environment maps
- Prefiltered specular reflections
- Bloom post-processing
- Emissive materials

> All rendering shown is performed in real time using Metal on macOS.

---

## ✨ Current Features

### Rendering
- ✅ **Physically Based Rendering (metal/roughness workflow)**
- ✅ **Image-Based Lighting (IBL)**
  - HDR equirectangular → cubemap conversion
  - Irradiance map generation
  - Prefiltered specular cubemap (roughness mip chain)
  - BRDF integration LUT
- ✅ **HDR rendering pipeline**
- ✅ **Bloom post-processing**
  - Bright-pass extraction
  - Separable Gaussian blur (ping-pong)
- ✅ **Emissive materials**
- ✅ **Normal mapping**
- ✅ **Ambient occlusion support**
- ✅ **Tone mapping + gamma correction**

### Assets & Materials
- ✅ **USDZ asset loading via ModelIO**
- ✅ **PBR texture support**
  - Base color (albedo)
  - Normal
  - Metallic / Roughness (combined or separate)
  - Ambient Occlusion
  - Emissive
- ✅ **Material flag system** (feature-driven shading paths)

### Engine / Architecture
- ✅ **Swift + Metal (no third-party libraries)**
- ✅ **Render-to-texture pipeline**
- ✅ **Scene system**
- ✅ **Game object / node hierarchy**
- ✅ **Centralized asset libraries**
  - Meshes
  - Textures
  - Shaders
  - Pipeline states

### Platform
- ✅ Designed for **macOS on Apple Silicon**
- ✅ Developed and tested on an **M4 Mac mini**
- ✅ Runs at **60 FPS** in current demos

---

## 🛠 Planned / Future Work

### Rendering
- 🔜 **Editor integration (ImGui)**
- 🔜 **Better bloom tuning & exposure controls**
- 🔜 **Additional post-processing effects**
  - Color grading
  - FXAA / TAA
- 🔜 **Shadow mapping**
- 🔜 **Ray-traced shadows (Metal RT)**
- 🔜 Potential **full real-time ray tracing**

### Engine Architecture
- 🔜 **Application / Layer stack architecture**
- 🔜 **Event system**
- 🔜 **Entity Component System (ECS)**
- 🔜 **Scene serialization**
- 🔜 Custom file formats for:
  - Scenes
  - Materials
  - Entities
  - Prefabs

### Tooling
- 🔜 **Editor application**
- 🔜 Scene viewport & inspector
- 🔜 Material editor
- 🔜 Asset browser

### World Systems
- 🔜 **Terrain system**
- 🔜 Physics integration
- 🔜 Streaming / large-world support (long term)

---

## ⚙️ Requirements

- macOS **26** (only version tested so far)
- Apple Silicon Mac
- Xcode (recent version recommended)
- Swift & Metal
- No external dependencies

> The engine may work on earlier macOS versions, but this has not been tested.

---

## 🚀 Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/cringlekaden/MetalCup.git```
2. Open the project in Xcode
3. Build & run on an Apple Silicon Mac
