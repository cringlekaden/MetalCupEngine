/// RendererDelegate.swift
/// Defines the RendererDelegate types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public protocol RendererDelegate: AnyObject {
    func update()
    func renderScene(into encoder: MTLRenderCommandEncoder)
    func renderOverlays(view: MTKView, commandBuffer: MTLCommandBuffer)
}
