//
//  Layer.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import MetalKit

open class Layer {
    public let name: String
    public init(name: String) { self.name = name }
    open func onAttach() {}
    open func onDetach() {}
    open func onUpdate(deltaTime: Float) {}
    open func onRender(encoder: MTLRenderCommandEncoder) {}
    open func onOverlayRender(encoder: MTLRenderCommandEncoder) {}
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

    public func updateAll(deltaTime: Float) {
        for layer in layers { layer.onUpdate(deltaTime: deltaTime) }
    }

    public func renderAll(with encoder: MTLRenderCommandEncoder) {
        for layer in layers { layer.onRender(encoder: encoder) }
    }

    public func renderOverlays(with encoder: MTLRenderCommandEncoder) {
        for layer in layers { layer.onOverlayRender(encoder: encoder) }
    }

    // Dispatch with early-out if handled
    public func sendEvent(_ event: Event) {
        for layer in layers.reversed() { // top-most first like Hazel
            layer.onEvent(event)
            if event.handled { break }
        }
    }
}

