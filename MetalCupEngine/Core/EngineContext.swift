/// EngineContext.swift
/// Defines the EngineContext that owns engine-wide services.
/// Created by refactor.

import MetalKit

public final class EngineContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let defaultLibrary: MTLLibrary?
    public weak var assetDatabase: AssetDatabase?
    public let log: EngineLogger
    public let prefabSystem: PrefabSystem
    public let layerCatalog: LayerCatalog

    public init(device: MTLDevice,
                commandQueue: MTLCommandQueue,
                defaultLibrary: MTLLibrary?,
                log: EngineLogger = EngineLogger(),
                prefabSystem: PrefabSystem = PrefabSystem(),
                layerCatalog: LayerCatalog = LayerCatalog()) {
        self.device = device
        self.commandQueue = commandQueue
        self.defaultLibrary = defaultLibrary
        self.log = log
        self.prefabSystem = prefabSystem
        self.layerCatalog = layerCatalog
        EngineLoggerContext.install(log)
    }
}
