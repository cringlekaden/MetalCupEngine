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
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create MTLDevice")
        }
        let queue = device.makeCommandQueue()
        let defaultLibrary = device.makeDefaultLibrary()
        guard let commandQueue = queue else {
            fatalError("Failed to create MTLCommandQueue")
        }
        let resources = ResourceRegistry()
        if let folder = specification.resourcesFolderName,
           let url = Bundle.main.url(forResource: folder, withExtension: nil) {
            resources.resourcesRootURL = url.standardizedFileURL
        } else if let bundleRoot = Bundle.main.resourceURL {
            resources.resourcesRootURL = bundleRoot.standardizedFileURL
        }
        if let assetsRoot = specification.assetsRootURL {
            resources.shaderRootURLs = [assetsRoot.appendingPathComponent("Shaders", isDirectory: true)]
        }
        resources.defaultLibrary = defaultLibrary
        self.engineContext = EngineContext(
            device: device,
            commandQueue: commandQueue,
            defaultLibrary: defaultLibrary,
            resources: resources
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
        if engineContext.resources.defaultLibrary == nil {
            engineContext.resources.defaultLibrary = engineContext.device.makeDefaultLibrary()
        }
        if engineContext.resources.defaultLibrary == nil {
            engineContext.resources.defaultLibrary = engineContext.defaultLibrary
        }

        BuiltinAssets.registerMeshes(
            assetManager: engineContext.assets,
            device: engineContext.device,
            graphics: engineContext.graphics
        )

        willCreateWindow()
        if engineContext.resources.defaultLibrary == nil {
            engineContext.resources.buildDefaultLibraryIfNeeded(device: engineContext.device)
        }
        guard engineContext.resources.defaultLibrary != nil else {
            fatalError("No default MTLLibrary available. Ensure .metal files are included in the app or engine target.")
        }
        window = EngineWindow()
        window.eventHandler = self
        window.create(with: specification, device: engineContext.device, preferences: engineContext.preferences)
        didCreateWindow()

        // Hook renderer to the MTKView
        renderer = Renderer(window.mtkView, engineContext: engineContext)
        renderer.inputAccumulator = window.inputAccumulator
        renderer.delegate = self
        window.mtkView.delegate = renderer
        engineContext.renderer = renderer

        let appId = ObjectIdentifier(self)
        let rendererId = ObjectIdentifier(renderer)
        engineContext.log.logDebug("Application bootstrap app=\(appId) renderer=\(rendererId)", category: .core)
    }

    // MARK: - EventHandler
    public func dispatch(_ event: Event) {
        layerStack.sendEvent(event)
    }

    // MARK: - RendererDelegate overrides
    open func activeScene() -> EngineScene? {
        nil
    }

    open func buildSceneView(renderer: Renderer) -> SceneView {
        let viewport = (renderer.viewportSize.x > 1 && renderer.viewportSize.y > 1)
            ? renderer.viewportSize
            : renderer.drawableSize
        return SceneView(viewportSize: viewport)
    }

    open func handlePickResult(_ result: PickResult) {}
    
}

extension Application: RendererDelegate {
    public func update(frame: FrameContext) {
        layerStack.updateAll(frame: frame)
    }
    public func renderScene(into encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        layerStack.renderAll(with: encoder, frameContext: frameContext)
    }

    public func renderOverlays(view: MTKView, commandBuffer: MTLCommandBuffer, frameContext: RendererFrameContext) {
        layerStack.renderOverlays(view: view, commandBuffer: commandBuffer, frameContext: frameContext)
    }
}
