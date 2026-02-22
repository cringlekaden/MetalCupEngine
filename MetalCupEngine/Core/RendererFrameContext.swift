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

    public func setIBLReady(_ ready: Bool) {
        storage.setIBLReady(ready)
    }

    public func iblReady() -> Bool {
        storage.iblReadyValue()
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

    public func uploadSceneConstants(_ constants: SceneConstants) -> MTLBuffer {
        storage.uploadSceneConstants(constants)
    }

    public func makeSceneConstantsBuffer(_ constants: SceneConstants, label: String = "SceneConstants.Temp") -> MTLBuffer {
        storage.makeSceneConstantsBuffer(constants, label: label)
    }

    public func uploadRendererSettings(_ settings: RendererSettings) -> MTLBuffer {
        storage.uploadRendererSettings(settings)
    }

    public func uploadLightData(_ data: [LightData]) -> (countBuffer: MTLBuffer, dataBuffer: MTLBuffer) {
        storage.uploadLightData(data)
    }

    public func rendererSettings() -> RendererSettings {
        storage.rendererSettingsValue()
    }

    public func setShadowConstants(_ constants: ShadowConstants) {
        storage.setShadowConstants(constants)
    }

    public func shadowConstantsBuffer() -> MTLBuffer {
        storage.shadowConstantsBuffer()
    }

    public func shadowConstantsValue() -> ShadowConstants {
        storage.shadowConstantsValue()
    }

    public func setShadowMapTexture(_ texture: MTLTexture?) {
        storage.setShadowMapTexture(texture)
    }

    public func shadowMapTexture() -> MTLTexture? {
        storage.shadowMapTexture()
    }

    public func currentRenderPass() -> RenderPassType {
        storage.currentRenderPassValue()
    }

    public func setCurrentRenderPass(_ pass: RenderPassType) {
        storage.setCurrentRenderPass(pass)
    }

    public func useDepthPrepass() -> Bool {
        storage.useDepthPrepassValue()
    }

    public func setUseDepthPrepass(_ enabled: Bool) {
        storage.setUseDepthPrepass(enabled)
    }

    public func layerFilterMask() -> LayerMask {
        storage.layerFilterMaskValue()
    }

    public func setLayerFilterMask(_ mask: LayerMask) {
        storage.setLayerFilterMask(mask)
    }

    public func engineContext() -> EngineContext {
        storage.engineContextValue()
    }

}

public final class RendererFrameContextStorage {
    private let maxFramesInFlight = 3
    private var frameIndex = 0
    private var frameCounter: UInt64 = 0
    private let engineContext: EngineContext
    private let device: MTLDevice
    private var rendererSettings = RendererSettings()
    private var currentRenderPass: RenderPassType = .main
    private var useDepthPrepass: Bool = true
    private var layerFilterMask: LayerMask = .all

    public struct IBLTextures {
        public let environment: MTLTexture?
        public let irradiance: MTLTexture?
        public let prefiltered: MTLTexture?
        public let brdfLut: MTLTexture?
    }

    private var currentIBLTextures = IBLTextures(environment: nil, irradiance: nil, prefiltered: nil, brdfLut: nil)
    private var iblReady: Bool = false

    private var instanceBuffers: [MTLBuffer?] = []
    private var instanceBufferCapacities: [Int] = []
    private var pickReadbackBuffers: [MTLBuffer?] = []
    private var sceneConstantsBuffers: [MTLBuffer?] = []
    private var lightCountBuffers: [MTLBuffer?] = []
    private var lightDataBuffers: [MTLBuffer?] = []
    private var lightDataBufferCapacities: [Int] = []
    private var shadowConstants = ShadowConstants()
    private var shadowConstantsBuffers: [MTLBuffer?] = []
    private var shadowMap: MTLTexture? = nil

    private(set) var batchStats = RendererBatchStats()

    public init(engineContext: EngineContext) {
        self.engineContext = engineContext
        self.device = engineContext.device
    }

    public func beginFrame() -> RendererFrameContext {
        frameIndex = (frameIndex + 1) % maxFramesInFlight
        frameCounter &+= 1
        ensureFrameStorage()
        batchStats = RendererBatchStats()
        iblReady = false
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

    fileprivate func setIBLReady(_ ready: Bool) {
        iblReady = ready
    }

    fileprivate func iblReadyValue() -> Bool {
        iblReady
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

    fileprivate func uploadSceneConstants(_ constants: SceneConstants) -> MTLBuffer {
        ensureFrameStorage()
        let requiredBytes = SceneConstants.stride
        if sceneConstantsBuffers[frameIndex] == nil {
            sceneConstantsBuffers[frameIndex] = device.makeBuffer(length: requiredBytes, options: [.storageModeShared])
            sceneConstantsBuffers[frameIndex]?.label = "SceneConstants.Frame\(frameIndex)"
        }
        guard let buffer = sceneConstantsBuffers[frameIndex] else {
            fatalError("SceneConstants buffer creation failed.")
        }
        MC_ASSERT(requiredBytes <= buffer.length, "SceneConstants buffer too small for upload.")
        var value = constants
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func makeSceneConstantsBuffer(_ constants: SceneConstants, label: String = "SceneConstants.Temp") -> MTLBuffer {
        let requiredBytes = SceneConstants.stride
        guard let buffer = device.makeBuffer(length: requiredBytes, options: [.storageModeShared]) else {
            fatalError("SceneConstants temp buffer creation failed.")
        }
        buffer.label = label
        var value = constants
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func uploadRendererSettings(_ settings: RendererSettings) -> MTLBuffer {
        #if DEBUG
        MC_ASSERT(RendererSettings.stride == RendererSettings.expectedMetalStride,
                  "RendererSettings stride mismatch (expected \(RendererSettings.expectedMetalStride), got \(RendererSettings.stride)).")
        #endif
        let requiredBytes = RendererSettings.stride
        guard let buffer = device.makeBuffer(length: requiredBytes, options: [.storageModeShared]) else {
            fatalError("RendererSettings buffer creation failed.")
        }
        buffer.label = "RendererSettings.Frame\(frameIndex)"
        var value = settings
        memcpy(buffer.contents(), &value, requiredBytes)
        return buffer
    }

    fileprivate func uploadLightData(_ data: [LightData]) -> (countBuffer: MTLBuffer, dataBuffer: MTLBuffer) {
        ensureFrameStorage()
        let countBytes = Int32.size
        if lightCountBuffers[frameIndex] == nil {
            lightCountBuffers[frameIndex] = device.makeBuffer(length: countBytes, options: [.storageModeShared])
            lightCountBuffers[frameIndex]?.label = "LightCount.Frame\(frameIndex)"
        }
        let requiredDataBytes = max(1, data.count) * LightData.stride
        ensureLightDataBufferCapacity(requiredDataBytes)
        guard let countBuffer = lightCountBuffers[frameIndex] else {
            fatalError("LightCount buffer creation failed.")
        }
        var lightCount = Int32(data.count)
        memcpy(countBuffer.contents(), &lightCount, countBytes)
        guard let dataBuffer = lightDataBuffers[frameIndex] else {
            fatalError("LightData buffer creation failed.")
        }
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

    func updateRendererState(settings: RendererSettings, currentRenderPass: RenderPassType, useDepthPrepass: Bool, layerFilterMask: LayerMask) {
        rendererSettings = settings
        self.currentRenderPass = currentRenderPass
        self.useDepthPrepass = useDepthPrepass
        self.layerFilterMask = layerFilterMask
    }

    fileprivate func rendererSettingsValue() -> RendererSettings {
        rendererSettings
    }

    fileprivate func setShadowConstants(_ constants: ShadowConstants) {
        shadowConstants = constants
        if shadowConstantsBuffers.count > frameIndex {
            shadowConstantsBuffers[frameIndex] = nil
        }
    }

    fileprivate func shadowConstantsBuffer() -> MTLBuffer {
        ensureFrameStorage()
        if let buffer = shadowConstantsBuffers[frameIndex] {
            return buffer
        }
#if DEBUG
        MC_ASSERT(ShadowConstants.stride == 368, "ShadowConstants stride mismatch. Keep Swift and Metal layouts in sync.")
#endif
        let requiredBytes = ShadowConstants.stride
        guard let buffer = device.makeBuffer(length: requiredBytes, options: [.storageModeShared]) else {
            fatalError("ShadowConstants buffer creation failed.")
        }
        buffer.label = "ShadowConstants.Frame\(frameIndex)"
        var value = shadowConstants
        memcpy(buffer.contents(), &value, requiredBytes)
        shadowConstantsBuffers[frameIndex] = buffer
        return buffer
    }

    fileprivate func shadowConstantsValue() -> ShadowConstants {
        shadowConstants
    }

    fileprivate func setShadowMapTexture(_ texture: MTLTexture?) {
        shadowMap = texture
    }

    fileprivate func shadowMapTexture() -> MTLTexture? {
        shadowMap
    }

    fileprivate func currentRenderPassValue() -> RenderPassType {
        currentRenderPass
    }

    fileprivate func setCurrentRenderPass(_ pass: RenderPassType) {
        currentRenderPass = pass
    }

    fileprivate func useDepthPrepassValue() -> Bool {
        useDepthPrepass
    }

    fileprivate func setUseDepthPrepass(_ enabled: Bool) {
        useDepthPrepass = enabled
    }

    fileprivate func layerFilterMaskValue() -> LayerMask {
        layerFilterMask
    }

    fileprivate func setLayerFilterMask(_ mask: LayerMask) {
        layerFilterMask = mask
    }

    fileprivate func engineContextValue() -> EngineContext {
        engineContext
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
        if shadowConstantsBuffers.count < maxFramesInFlight {
            shadowConstantsBuffers = Array(repeating: nil, count: maxFramesInFlight)
        }
    }

    private func ensureInstanceBufferCapacity(_ requiredBytes: Int) {
        ensureFrameStorage()
        let currentCapacity = instanceBufferCapacities[frameIndex]
        if let _ = instanceBuffers[frameIndex], currentCapacity >= requiredBytes {
            return
        }
        let newCapacity = max(requiredBytes, max(currentCapacity, 1) * 2)
        instanceBuffers[frameIndex] = device.makeBuffer(length: newCapacity, options: [.storageModeShared])
        instanceBuffers[frameIndex]?.label = "InstanceBuffer.Frame\(frameIndex)"
        instanceBufferCapacities[frameIndex] = newCapacity
    }

    private func ensurePickReadbackBuffer() {
        ensureFrameStorage()
        if pickReadbackBuffers[frameIndex] != nil { return }
        pickReadbackBuffers[frameIndex] = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: [.storageModeShared])
        pickReadbackBuffers[frameIndex]?.label = "PickReadback.Frame\(frameIndex)"
    }

    private func ensureLightDataBufferCapacity(_ requiredBytes: Int) {
        ensureFrameStorage()
        let currentCapacity = lightDataBufferCapacities[frameIndex]
        if let _ = lightDataBuffers[frameIndex], currentCapacity >= requiredBytes {
            return
        }
        let newCapacity = max(requiredBytes, max(currentCapacity, 1) * 2)
        lightDataBuffers[frameIndex] = device.makeBuffer(length: newCapacity, options: [.storageModeShared])
        lightDataBuffers[frameIndex]?.label = "LightData.Frame\(frameIndex)"
        lightDataBufferCapacities[frameIndex] = newCapacity
    }
}
