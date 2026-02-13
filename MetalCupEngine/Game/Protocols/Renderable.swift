/// Renderable.swift
/// Defines the Renderable types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

protocol Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder)
}
