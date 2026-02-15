/// Layer.swift
/// Defines the Layer types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

open class Layer {
    public let name: String
    public init(name: String) { self.name = name }
    open func onAttach() {}
    open func onDetach() {}
    open func onUpdate() {}
    open func onFixedUpdate() {}
    open func onRender(encoder: MTLRenderCommandEncoder) {}
    open func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer) {}
    open func onEvent(_ event: Event) {}
}

public final class LayerStack {
    private var layers: [Layer] = []
    public init() {}

    public func pushLayer(_ layer: Layer) {
        layers.append(layer)
        layer.onAttach()
    }

    public func popLayer(_ layer: Layer) {
        if let idx = layers.firstIndex(where: { $0 === layer }) {
            layers[idx].onDetach()
            layers.remove(at: idx)
        }
    }

    public func updateAll() {
        for layer in layers { layer.onUpdate() }
    }

    public func fixedUpdateAll() {
        for layer in layers { layer.onFixedUpdate() }
    }

    public func renderAll(with encoder: MTLRenderCommandEncoder) {
        for layer in layers { layer.onRender(encoder: encoder) }
    }

    public func renderOverlays(view: MTKView, commandBuffer: MTLCommandBuffer) {
        for layer in layers { layer.onOverlayRender(view: view, commandBuffer: commandBuffer) }
    }

    // Dispatch with early-out if handled
    public func sendEvent(_ event: Event) {
        for layer in layers.reversed() {
            layer.onEvent(event)
            if event.handled { break }
        }
    }
}
