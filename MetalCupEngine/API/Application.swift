/// Application.swift
/// Defines the Application types and helpers for the engine.
/// Created by Kaden Cringle.

import AppKit
import MetalKit

/// Base engine Application that owns a Window and wires the Renderer to the MTKView.
/// The editor constructs this with an ApplicationSpecification.
open class Application: NSObject, EventHandler {
    public let specification: ApplicationSpecification
    public let engineContext: EngineContext
    private(set) var window: EngineWindow!
    private(set) var renderer: Renderer!
    public let layerStack = LayerStack()
    public var mainWindow: EngineWindow { window }
    public var mainRenderer: Renderer { renderer }

    public init(specification: ApplicationSpecification) {
        self.specification = specification
        if Engine.Device == nil {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Failed to create MTLDevice")
            }
            Engine.initialize(device: device)
        }
        let queue = Engine.Device.makeCommandQueue() ?? Engine.CommandQueue
        self.engineContext = EngineContext(
            device: Engine.Device,
            commandQueue: queue!,
            defaultLibrary: Engine.DefaultLibrary
        )
        super.init()
        bootstrap()
    }

    /// Override to perform app/editor specific initialization before window creation.
    open func willCreateWindow() {}

    /// Override to perform app/editor specific initialization after window creation and renderer hookup.
    open func didCreateWindow() {}

    private func bootstrap() {
        // Configure resource registry from spec
        ResourceRegistry.defaultLibrary = Engine.Device.makeDefaultLibrary()
        if ResourceRegistry.defaultLibrary == nil {
            // Fallback to Engine.DefaultLibrary if available
            ResourceRegistry.defaultLibrary = Engine.DefaultLibrary
        }

        BuiltinAssets.registerMeshes()

        willCreateWindow()
        if ResourceRegistry.defaultLibrary == nil {
            ResourceRegistry.buildDefaultLibraryIfNeeded(device: Engine.Device)
        }
        guard ResourceRegistry.defaultLibrary != nil else {
            fatalError("No default MTLLibrary available. Ensure .metal files are included in the app or engine target.")
        }
        window = EngineWindow()
        window.eventHandler = self
        window.create(with: specification, device: Engine.Device)
        didCreateWindow()

        // Hook renderer to the MTKView
        renderer = Renderer(window.mtkView)
        renderer.delegate = self
        window.mtkView.delegate = renderer

        let appId = ObjectIdentifier(self)
        let rendererId = ObjectIdentifier(renderer)
        EngineLog.shared.logDebug("Application bootstrap app=\(appId) renderer=\(rendererId)", category: .core)
    }

    // MARK: - EventHandler
    public func dispatch(_ event: Event) {
        layerStack.sendEvent(event)
    }

    // MARK: - RendererDelegate overrides
    open func activeScene() -> EngineScene? {
        nil
    }

    open func buildSceneView() -> SceneView {
        let viewport = (Renderer.ViewportSize.x > 1 && Renderer.ViewportSize.y > 1)
            ? Renderer.ViewportSize
            : Renderer.DrawableSize
        return SceneView(viewportSize: viewport)
    }

    open func handlePickResult(_ result: PickResult) {}
    
}

extension Application: RendererDelegate {
    public func update() {
        layerStack.updateAll()
    }
    public func renderScene(into encoder: MTLRenderCommandEncoder) {
        layerStack.renderAll(with: encoder)
    }

    public func renderOverlays(view: MTKView, commandBuffer: MTLCommandBuffer) {
        layerStack.renderOverlays(view: view, commandBuffer: commandBuffer)
    }
}
