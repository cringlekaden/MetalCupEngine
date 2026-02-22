/// EngineContext.swift
/// Defines the EngineContext that owns engine-wide services.
/// Created by refactor.

import MetalKit

public final class EngineContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let defaultLibrary: MTLLibrary?
    public weak var assetDatabase: AssetDatabase?
    public weak var renderer: Renderer?
    public let log: EngineLogger
    public let prefabSystem: PrefabSystem
    public let layerCatalog: LayerCatalog
    public let resources: ResourceRegistry
    public let assets: AssetManager
    public let graphics: Graphics
    public let preferences: Preferences
    public let fallbackTextures: FallbackTextureLibrary
    public let debugDraw: DebugDraw
    public let pickingSystem: PickingSystem
    public var rendererSettings: RendererSettings = RendererSettings()

    public init(device: MTLDevice,
                commandQueue: MTLCommandQueue,
                defaultLibrary: MTLLibrary?,
                log: EngineLogger = EngineLogger(),
                prefabSystem: PrefabSystem = PrefabSystem(),
                layerCatalog: LayerCatalog = LayerCatalog(),
                resources: ResourceRegistry? = nil,
                assets: AssetManager? = nil,
                graphics: Graphics? = nil,
                preferences: Preferences? = nil,
                debugDraw: DebugDraw? = nil,
                pickingSystem: PickingSystem? = nil) {
        self.device = device
        self.commandQueue = commandQueue
        self.defaultLibrary = defaultLibrary
        self.log = log
        self.prefabSystem = prefabSystem
        self.layerCatalog = layerCatalog
        let resolvedResources = resources ?? ResourceRegistry()
        self.resources = resolvedResources
        self.preferences = preferences ?? Preferences()
        let resolvedGraphics = graphics ?? Graphics(resourceRegistry: resolvedResources, device: device, preferences: self.preferences)
        self.graphics = resolvedGraphics
        self.assets = assets ?? AssetManager(device: device, graphics: resolvedGraphics)
        self.fallbackTextures = FallbackTextureLibrary(device: device, preferences: self.preferences)
        self.debugDraw = debugDraw ?? DebugDraw()
        self.pickingSystem = pickingSystem ?? PickingSystem()
        EngineLoggerContext.install(log)
    }
}
