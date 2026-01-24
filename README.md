# MetalCup ☕️

MetalCup is a **personal 3D rendering engine written in Swift using Apple’s Metal API**, built as a learning and experimentation project on macOS.

The goal of this project is to explore modern real-time rendering techniques on Apple Silicon while keeping the engine simple, readable, and hackable.

> ⚠️ This project is **early-stage and experimental**. APIs, structure, and rendering techniques are expected to change frequently.

---

## Features (Current)

- ✅ **Swift + Metal** (no third-party libraries)
- ✅ **OBJ model loading**
- ✅ **.mdl material support**
- ✅ **Normal mapping**
- ✅ **Phong lighting**
- ✅ **Unlimited point lights**
  - No attenuation (yet)
- ✅ **Simple scene system**
- ✅ **Game object / node hierarchy**
- ✅ Designed for **macOS on Apple Silicon**

---

## Planned / Future Work

- 🔜 **Physically Based Rendering (PBR)**
- 🔜 **Image-Based Lighting (IBL)**
  - Skysphere → cubemap workflow
- 🔜 **Ray-traced shadows**
- 🔜 Potential **full real-time ray tracing**
- 🔜 Light attenuation & more light types
- 🔜 Engine architecture cleanup as features stabilize

---

## Requirements

- macOS **26** (only version tested so far)
- Apple Silicon Mac (developed on an **M4 Mac mini**)
- Xcode (recent version recommended)
- Swift & Metal (no external dependencies)

> The engine *may* work on earlier macOS versions, but this has not been tested.

---

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/cringlekaden/MetalCup.git
