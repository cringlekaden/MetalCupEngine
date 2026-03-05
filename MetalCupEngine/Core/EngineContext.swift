/// EngineContext.swift
/// Defines the EngineContext that owns engine-wide services.
/// Created by Kaden Cringle.

import MetalKit
import Foundation

public final class RendererDiagnosticsService {
    private var forwardPlusByViewSignature: [UInt64: RendererForwardPlusDiagnostics] = [:]
    private var latestForwardPlus = RendererForwardPlusDiagnostics(
        stats: ForwardPlusStats(),
        cullingDepthSource: .none
    )
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func commit(viewSignature: UInt64, forwardPlus: RendererForwardPlusDiagnostics) -> RendererForwardPlusDiagnostics {
        lock.lock()
        forwardPlusByViewSignature[viewSignature] = forwardPlus
        latestForwardPlus = forwardPlus
        lock.unlock()
        return forwardPlus
    }

    public func latest() -> RendererForwardPlusDiagnostics {
        lock.lock()
        let value = latestForwardPlus
        lock.unlock()
        return value
    }

    public func forwardPlus(forViewSignature viewSignature: UInt64) -> RendererForwardPlusDiagnostics? {
        lock.lock()
        let value = forwardPlusByViewSignature[viewSignature]
        lock.unlock()
        return value
    }
}

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
    public var scriptRuntime: ScriptRuntime
    public var rendererSettings: RendererSettings = RendererSettings()
    public let rendererDiagnostics = RendererDiagnosticsService()
    public var forwardPlusStats: ForwardPlusStats = ForwardPlusStats()
    public var forwardPlusCullingDepthSource: UInt32 = ForwardPlusCullingDepthSource.none.rawValue
    public private(set) var physicsSettingsVersion: UInt64 = 1
    public var physicsSettings: PhysicsSettings = PhysicsSettings() {
        didSet {
            physicsSettingsVersion &+= 1
        }
    }

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
                pickingSystem: PickingSystem? = nil,
                scriptRuntime: ScriptRuntime? = nil) {
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
        self.assets = assets ?? AssetManager(device: device, graphics: resolvedGraphics, commandQueue: commandQueue)
        self.fallbackTextures = FallbackTextureLibrary(device: device, preferences: self.preferences)
        self.debugDraw = debugDraw ?? DebugDraw()
        self.pickingSystem = pickingSystem ?? PickingSystem()
        self.scriptRuntime = scriptRuntime ?? NullScriptRuntime()
        EngineLoggerContext.install(log)
#if DEBUG
        TransformMath.runTransformSanityOnce()
#endif
    }
}
