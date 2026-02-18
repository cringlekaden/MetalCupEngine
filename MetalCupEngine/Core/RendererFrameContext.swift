/// RendererFrameContext.swift
/// Defines per-frame renderer resources for batching and picking.
/// Created by Kaden Cringle.

import MetalKit

public struct RendererBatchStats {
    public var uniqueMeshes: Int = 0
    public var batches: Int = 0
    public var instancedDrawCalls: Int = 0
    public var nonInstancedDrawCalls: Int = 0
}

public struct RendererFrameContext {
    fileprivate let storage: RendererFrameContextStorage

    fileprivate init(storage: RendererFrameContextStorage) {
        self.storage = storage
    }

    public func currentFrameIndex() -> Int {
        storage.currentFrameIndex()
    }

    public func currentFrameCounter() -> UInt64 {
        storage.currentFrameCounter()
    }

    public func updateBatchStats(_ stats: RendererBatchStats) {
        storage.updateBatchStats(stats)
    }

    public func batchStats() -> RendererBatchStats {
        storage.batchStats
    }

    public func updateIBLTextures(
        environment: MTLTexture?,
        irradiance: MTLTexture?,
        prefiltered: MTLTexture?,
        brdfLut: MTLTexture?
    ) {
        storage.updateIBLTextures(
            environment: environment,
            irradiance: irradiance,
            prefiltered: prefiltered,
            brdfLut: brdfLut
        )
    }

    public func iblTextures() -> RendererFrameContextStorage.IBLTextures {
        storage.iblTextures()
    }

    public func uploadInstanceData(_ data: [InstanceData]) -> MTLBuffer? {
        storage.uploadInstanceData(data)
    }

    public func instanceBuffer() -> MTLBuffer? {
        storage.instanceBuffer()
    }

    public func pickReadbackBuffer() -> MTLBuffer? {
        storage.pickReadbackBuffer()
    }

    public func uploadSceneConstants(_ constants: SceneConstants) -> MTLBuffer? {
        storage.uploadSceneConstants(constants)
    }

    public func makeSceneConstantsBuffer(_ constants: SceneConstants, label: String = "SceneConstants.Temp") -> MTLBuffer? {
        storage.makeSceneConstantsBuffer(constants, label: label)
    }

    public func uploadRendererSettings(_ settings: RendererSettings) -> MTLBuffer? {
        storage.uploadRendererSettings(settings)
    }

    public func uploadLightData(_ data: [LightData]) -> (countBuffer: MTLBuffer?, dataBuffer: MTLBuffer?) {
        storage.uploadLightData(data)
    }
}

public final class RendererFrameContextStorage {
    private let maxFramesInFlight = 3
    private var frameIndex = 0
    private var frameCounter: UInt64 = 0

    public struct IBLTextures {
        public let environment: MTLTexture?
        public let irradiance: MTLTexture?
        public let prefiltered: MTLTexture?
        public let brdfLut: MTLTexture?
    }

    private var currentIBLTextures = IBLTextures(environment: nil, irradiance: nil, prefiltered: nil, brdfLut: nil)

    private var instanceBuffers: [MTLBuffer?] = []
    private var instanceBufferCapacities: [Int] = []
    private var pickReadbackBuffers: [MTLBuffer?] = []
    private var sceneConstantsBuffers: [MTLBuffer?] = []
    private var lightCountBuffers: [MTLBuffer?] = []
    private var lightDataBuffers: [MTLBuffer?] = []
    private var lightDataBufferCapacities: [Int] = []

    private(set) var batchStats = RendererBatchStats()

    public init() {}

    public func beginFrame() -> RendererFrameContext {
        frameIndex = (frameIndex + 1) % maxFramesInFlight
        frameCounter &+= 1
        ensureFrameStorage()
        batchStats = RendererBatchStats()
        MCMesh.resetBindingCache()
        return RendererFrameContext(storage: self)
    }

    fileprivate func currentFrameIndex() -> Int {
        frameIndex
    }

    fileprivate func currentFrameCounter() -> UInt64 {
        frameCounter
    }

    fileprivate func updateBatchStats(_ stats: RendererBatchStats) {
        batchStats = stats
    }

    fileprivate func updateIBLTextures(
        environment: MTLTexture?,
        irradiance: MTLTexture?,
        prefiltered: MTLTexture?,
        brdfLut: MTLTexture?
    ) {
        currentIBLTextures = IBLTextures(
            environment: environment,
            irradiance: irradiance,
            prefiltered: prefiltered,
            brdfLut: brdfLut
        )
    }

    fileprivate func iblTextures() -> IBLTextures {
        currentIBLTextures
    }

    fileprivate func uploadInstanceData(_ data: [InstanceData]) -> MTLBuffer? {
        guard !data.isEmpty else { return nil }
        let requiredBytes = InstanceData.stride(data.count)
        ensureInstanceBufferCapacity(requiredBytes)
        guard let buffer = instanceBuffers[frameIndex] else { return nil }
        MC_ASSERT(requiredBytes <= buffer.length, "Instance buffer too small for upload.")
        _ = data.withUnsafeBytes { bytes in
            memcpy(buffer.contents(), bytes.baseAddress, bytes.count)
        }
        return buffer
    }

    fileprivate func instanceBuffer() -> MTLBuffer? {
        instanceBuffers[frameIndex] ?? nil
    }

    fileprivate func pickReadbackBuffer() -> MTLBuffer? {
        ensurePickReadbackBuffer()
        return pickReadbackBuffers[frameIndex] ?? nil
    }

    fileprivate func uploadSceneConstants(_ constants: SceneConstants) -> MTLBuffer? {
        ensureFrameStorage()
        let requiredBytes = SceneConstants.stride
        if sceneConstantsBuffers[frameIndex] == nil {
            sceneConstantsBuffers[frameIndex] = Engine.Device.makeBuffer(length: requiredBytes, options: [.storageModeShared])
            sceneConstantsBuffers[frameIndex]?.label = "SceneConstants.Frame\(frameIndex)"
        }
        guard let buffer = sceneConstantsBuffers[frameIndex] else { return nil }
        MC_ASSERT(requiredBytes <= buffer.length, "SceneConstants buffer too small for upload.")
        var value = constants
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func makeSceneConstantsBuffer(_ constants: SceneConstants, label: String = "SceneConstants.Temp") -> MTLBuffer? {
        let requiredBytes = SceneConstants.stride
        guard let buffer = Engine.Device.makeBuffer(length: requiredBytes, options: [.storageModeShared]) else { return nil }
        buffer.label = label
        var value = constants
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func uploadRendererSettings(_ settings: RendererSettings) -> MTLBuffer? {
        let requiredBytes = RendererSettings.stride
        guard let buffer = Engine.Device.makeBuffer(length: requiredBytes, options: [.storageModeShared]) else { return nil }
        buffer.label = "RendererSettings.Frame\(frameIndex)"
        var value = settings
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func uploadLightData(_ data: [LightData]) -> (countBuffer: MTLBuffer?, dataBuffer: MTLBuffer?) {
        ensureFrameStorage()
        let countBytes = Int32.size
        if lightCountBuffers[frameIndex] == nil {
            lightCountBuffers[frameIndex] = Engine.Device.makeBuffer(length: countBytes, options: [.storageModeShared])
            lightCountBuffers[frameIndex]?.label = "LightCount.Frame\(frameIndex)"
        }
        let requiredDataBytes = max(1, data.count) * LightData.stride
        ensureLightDataBufferCapacity(requiredDataBytes)
        guard let countBuffer = lightCountBuffers[frameIndex] else { return (nil, nil) }
        var lightCount = Int32(data.count)
        memcpy(countBuffer.contents(), &lightCount, countBytes)
        guard let dataBuffer = lightDataBuffers[frameIndex] else { return (countBuffer, nil) }
        MC_ASSERT(requiredDataBytes <= dataBuffer.length, "Light data buffer too small for upload.")
        if data.isEmpty {
            var fallback = LightData()
            memcpy(dataBuffer.contents(), &fallback, LightData.stride)
        } else {
            _ = data.withUnsafeBytes { bytes in
                memcpy(dataBuffer.contents(), bytes.baseAddress, bytes.count)
            }
        }
        return (countBuffer, dataBuffer)
    }

    private func ensureFrameStorage() {
        if instanceBuffers.count < maxFramesInFlight {
            instanceBuffers = Array(repeating: nil, count: maxFramesInFlight)
            instanceBufferCapacities = Array(repeating: 0, count: maxFramesInFlight)
        }
        if pickReadbackBuffers.count < maxFramesInFlight {
            pickReadbackBuffers = Array(repeating: nil, count: maxFramesInFlight)
        }
        if sceneConstantsBuffers.count < maxFramesInFlight {
            sceneConstantsBuffers = Array(repeating: nil, count: maxFramesInFlight)
        }
        if lightCountBuffers.count < maxFramesInFlight {
            lightCountBuffers = Array(repeating: nil, count: maxFramesInFlight)
        }
        if lightDataBuffers.count < maxFramesInFlight {
            lightDataBuffers = Array(repeating: nil, count: maxFramesInFlight)
            lightDataBufferCapacities = Array(repeating: 0, count: maxFramesInFlight)
        }
    }

    private func ensureInstanceBufferCapacity(_ requiredBytes: Int) {
        ensureFrameStorage()
        let currentCapacity = instanceBufferCapacities[frameIndex]
        if let _ = instanceBuffers[frameIndex], currentCapacity >= requiredBytes {
            return
        }
        let newCapacity = max(requiredBytes, max(currentCapacity, 1) * 2)
        instanceBuffers[frameIndex] = Engine.Device.makeBuffer(length: newCapacity, options: [.storageModeShared])
        instanceBuffers[frameIndex]?.label = "InstanceBuffer.Frame\(frameIndex)"
        instanceBufferCapacities[frameIndex] = newCapacity
    }

    private func ensurePickReadbackBuffer() {
        ensureFrameStorage()
        if pickReadbackBuffers[frameIndex] != nil { return }
        pickReadbackBuffers[frameIndex] = Engine.Device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: [.storageModeShared])
        pickReadbackBuffers[frameIndex]?.label = "PickReadback.Frame\(frameIndex)"
    }

    private func ensureLightDataBufferCapacity(_ requiredBytes: Int) {
        ensureFrameStorage()
        let currentCapacity = lightDataBufferCapacities[frameIndex]
        if let _ = lightDataBuffers[frameIndex], currentCapacity >= requiredBytes {
            return
        }
        let newCapacity = max(requiredBytes, max(currentCapacity, 1) * 2)
        lightDataBuffers[frameIndex] = Engine.Device.makeBuffer(length: newCapacity, options: [.storageModeShared])
        lightDataBuffers[frameIndex]?.label = "LightData.Frame\(frameIndex)"
        lightDataBufferCapacities[frameIndex] = newCapacity
    }
}
