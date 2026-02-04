//
//  Application.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import AppKit
import MetalKit

/// Base engine Application that owns a Window and wires the Renderer to the MTKView.
/// The editor constructs this with an ApplicationSpecification.
public class Application: NSObject, EventHandler {
    public let specification: ApplicationSpecification
    private(set) var window: EngineWindow!
    private(set) var renderer: Renderer!
    public let layerStack = LayerStack()

    public init(specification: ApplicationSpecification) {
        self.specification = specification
        super.init()
        bootstrap()
    }

    /// Override to perform app/editor specific initialization before window creation.
    open func willCreateWindow() {}

    /// Override to perform app/editor specific initialization after window creation and renderer hookup.
    open func didCreateWindow() {}

    private func bootstrap() {
        // Ensure engine singletons are initialized before constructing the view/renderer.
        // Callers can also perform this before creating Application if they need custom order.
        if Engine.Device == nil {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Failed to create MTLDevice")
            }
            Engine.initialize(device: device)
        }

        willCreateWindow()

        window = EngineWindow()
        window.eventHandler = self
        window.create(with: specification, device: Engine.Device)
        
        // Hook renderer to the MTKView
        renderer = Renderer(window.mtkView)
        renderer.delegate = self
        window.mtkView.delegate = renderer

        didCreateWindow()
    }

    // MARK: - EventHandler
    public func dispatch(_ event: Event) {
        layerStack.sendEvent(event)
    }
}

extension Application: RendererDelegate {
    public func update(deltaTime: Float) {
        layerStack.updateAll(deltaTime: deltaTime)
    }
    public func renderScene(into encoder: MTLRenderCommandEncoder) {
        layerStack.renderAll(with: encoder)
    }

    public func renderOverlays(into encoder: MTLRenderCommandEncoder) {
        layerStack.renderOverlays(with: encoder)
    }
}

