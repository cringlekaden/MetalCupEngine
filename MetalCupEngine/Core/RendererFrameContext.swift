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

public struct LightingInputs {
    public var lightCountBuffer: MTLBuffer
    public var lightDataBuffer: MTLBuffer
    public var lightGridBuffer: MTLBuffer?
    public var lightIndexListBuffer: MTLBuffer?
    public var lightIndexCountBuffer: MTLBuffer?
    public var clusterParamsBuffer: MTLBuffer?
    public var tileLightGridBuffer: MTLBuffer?
    public var tileParamsBuffer: MTLBuffer?
}

public struct RenderViewContext {
    public var viewId: UInt64
    public var viewportSize: SIMD2<Float>
    public var layerFilterMask: LayerMask
    public var depthPrepassEnabled: Bool
    public var debugFlags: UInt32
    public var showEditorOverlays: Bool

    public init(
        viewId: UInt64 = 0,
        viewportSize: SIMD2<Float> = .zero,
        layerFilterMask: LayerMask = .all,
        depthPrepassEnabled: Bool = true,
        debugFlags: UInt32 = 0,
        showEditorOverlays: Bool = false
    ) {
        self.viewId = viewId
        self.viewportSize = viewportSize
        self.layerFilterMask = layerFilterMask
        self.depthPrepassEnabled = depthPrepassEnabled
        self.debugFlags = debugFlags
        self.showEditorOverlays = showEditorOverlays
    }

    public func cacheSignature() -> UInt64 {
        var hasher = Hasher()
        hasher.combine(viewId)
        hasher.combine(viewportSize.x.bitPattern)
        hasher.combine(viewportSize.y.bitPattern)
        hasher.combine(layerFilterMask.rawValue)
        hasher.combine(depthPrepassEnabled)
        hasher.combine(debugFlags)
        hasher.combine(showEditorOverlays)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    public var viewSignature: UInt64 {
        cacheSignature()
    }
}

public enum ForwardPlusCullingDepthSource: UInt32 {
    case none = 0
    case prepass = 1
    case fallback = 2
}

public struct RendererFrameContext {
    fileprivate let storage: RendererFrameContextStorage

    fileprivate init(storage: RendererFrameContextStorage) {
        self.storage = storage
    }

    public func currentFrameIndex() -> Int {
        storage.currentFrameIndex()
    }

    public func frameInFlightIndex() -> Int {
        storage.currentFrameIndex()
    }

    public func currentFrameCounter() -> UInt64 {
        storage.currentFrameCounter()
    }

    public func maxFramesInFlight() -> Int {
        storage.maxFramesInFlightValue()
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

    public func uploadRendererSettings(_ settings: RendererSettings) -> (buffer: MTLBuffer, offset: Int) {
        storage.uploadRendererSettings(settings)
    }

    public func uploadLightData(_ data: [LightData]) -> (countBuffer: MTLBuffer, dataBuffer: MTLBuffer) {
        storage.uploadLightData(data)
    }

    public func rendererSettings() -> RendererSettings {
        storage.rendererSettingsValue()
    }

    public func rendererStateRevision() -> UInt64 {
        storage.rendererStateRevisionValue()
    }

    func setRenderResourceRegistry(_ registry: RenderResourceRegistry) {
        storage.setRenderResourceRegistry(registry)
    }

    func renderResourceRegistry() -> RenderResourceRegistry? {
        storage.renderResourceRegistryValue()
    }

    public func setRenderFrameSnapshot(_ snapshot: RenderFrameSnapshot?) {
        storage.setRenderFrameSnapshot(snapshot)
    }

    public func renderFrameSnapshot() -> RenderFrameSnapshot? {
        storage.renderFrameSnapshotValue()
    }

    public func setLightingInputs(_ inputs: LightingInputs) {
        storage.setLightingInputs(inputs)
    }

    public func lightingInputs() -> LightingInputs? {
        storage.lightingInputsValue()
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

    public func viewContext() -> RenderViewContext {
        storage.viewContextValue()
    }

    public func viewSignature() -> UInt64 {
        storage.viewContextValue().viewSignature
    }

    public func setForwardPlusAllowed(_ allowed: Bool) {
        storage.setForwardPlusAllowed(allowed)
    }

    public func isForwardPlusAllowed() -> Bool {
        storage.forwardPlusAllowedValue()
    }

    public func markForwardPlusCullingDepthProduced(source: ForwardPlusCullingDepthSource) {
        storage.markForwardPlusCullingDepthProduced(source: source)
    }

    public func forwardPlusCullingDepthSource() -> ForwardPlusCullingDepthSource {
        storage.forwardPlusCullingDepthSourceValue()
    }

    public func forwardPlusCullingDepthProducerCount() -> Int {
        storage.forwardPlusCullingDepthProducerCountValue()
    }

    public func setViewContext(_ context: RenderViewContext) {
        storage.setViewContext(context)
    }

    public func useDepthPrepass() -> Bool {
        storage.viewContextValue().depthPrepassEnabled
    }

    public func setUseDepthPrepass(_ enabled: Bool) {
        var context = storage.viewContextValue()
        context.depthPrepassEnabled = enabled
        storage.setViewContext(context)
    }

    public func layerFilterMask() -> LayerMask {
        storage.viewContextValue().layerFilterMask
    }

    public func setLayerFilterMask(_ mask: LayerMask) {
        var context = storage.viewContextValue()
        context.layerFilterMask = mask
        storage.setViewContext(context)
    }

    public func engineContext() -> EngineContext {
        storage.engineContextValue()
    }

    public func assetStateRevision() -> UInt64 {
        storage.assetStateRevisionValue()
    }

}

public final class RendererFrameContextStorage {
    private let maxFramesInFlight = 3
    private var frameIndex = 0
    private var frameCounter: UInt64 = 0
    private let engineContext: EngineContext
    private let device: MTLDevice
    private var rendererSettings = RendererSettings()
    private var rendererStateRevision: UInt64 = 0
    private var rendererSettingsSignature: UInt64 = 0
    private var renderViewSignature: UInt64 = 0
    private var assetStateRevision: UInt64 = 0
    private var renderResourceRegistry: RenderResourceRegistry?
    private var renderFrameSnapshot: RenderFrameSnapshot?
    private var lightingInputs: LightingInputs?
    private var currentRenderPass: RenderPassType = .main
    private var viewContext = RenderViewContext()
    private var forwardPlusAllowed = true
    private var forwardPlusCullingDepthSource: ForwardPlusCullingDepthSource = .none
    private var forwardPlusCullingDepthProducerMask: UInt32 = 0

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
    private var sceneConstantsUploaded: [Bool] = []
    private var rendererSettingsBuffers: [MTLBuffer?] = []
    private var rendererSettingsBufferCapacities: [Int] = []
    private var rendererSettingsWriteOffsets: [Int] = []
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
        currentRenderPass = .main
        iblReady = false
        sceneConstantsUploaded[frameIndex] = false
        rendererSettingsWriteOffsets[frameIndex] = 0
        renderResourceRegistry = nil
        renderFrameSnapshot = nil
        lightingInputs = nil
        forwardPlusAllowed = true
        forwardPlusCullingDepthSource = .none
        forwardPlusCullingDepthProducerMask = 0
        return RendererFrameContext(storage: self)
    }

    fileprivate func currentFrameIndex() -> Int {
        frameIndex
    }

    fileprivate func currentFrameCounter() -> UInt64 {
        frameCounter
    }

    fileprivate func maxFramesInFlightValue() -> Int {
        maxFramesInFlight
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
        MC_ASSERT(InstanceData.stride == InstanceData.expectedMetalStride,
                  "InstanceData stride mismatch. Keep Swift and Metal layouts in sync.")
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
        if !sceneConstantsUploaded[frameIndex] {
            var value = constants
            memcpy(buffer.contents(), &value, requiredBytes)
            sceneConstantsUploaded[frameIndex] = true
        }
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

    fileprivate func uploadRendererSettings(_ settings: RendererSettings) -> (buffer: MTLBuffer, offset: Int) {
        #if DEBUG
        MC_ASSERT(RendererSettings.stride == RendererSettings.expectedMetalStride,
                  "RendererSettings stride mismatch (expected \(RendererSettings.expectedMetalStride), got \(RendererSettings.stride)).")
        #endif
        ensureFrameStorage()
        let requiredBytes = RendererSettings.stride
        let alignedBytes = alignBufferSize(requiredBytes)
        let writeOffset = rendererSettingsWriteOffsets[frameIndex]
        let requiredCapacity = writeOffset + alignedBytes
        let currentCapacity = rendererSettingsBufferCapacities[frameIndex]
        if rendererSettingsBuffers[frameIndex] == nil || currentCapacity < requiredCapacity {
            let newCapacity = max(requiredCapacity, max(currentCapacity, 1) * 2)
            rendererSettingsBuffers[frameIndex] = device.makeBuffer(length: newCapacity, options: [.storageModeShared])
            rendererSettingsBuffers[frameIndex]?.label = "RendererSettings.Frame\(frameIndex)"
            rendererSettingsBufferCapacities[frameIndex] = newCapacity
        }
        guard let buffer = rendererSettingsBuffers[frameIndex] else {
            fatalError("RendererSettings buffer creation failed.")
        }
        var value = settings
        memcpy(buffer.contents().advanced(by: writeOffset), &value, requiredBytes)
        rendererSettingsWriteOffsets[frameIndex] = writeOffset + alignedBytes
        return (buffer, writeOffset)
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

    func updateRendererState(settings: RendererSettings, viewContext: RenderViewContext) {
        let nextSettingsSignature = hashRendererSettings(settings)
        let nextViewSignature = viewContext.viewSignature
        let changed = nextSettingsSignature != rendererSettingsSignature || nextViewSignature != renderViewSignature
        rendererSettings = settings
        self.viewContext = viewContext
        rendererSettingsSignature = nextSettingsSignature
        renderViewSignature = nextViewSignature
        if changed {
            rendererStateRevision &+= 1
        }
    }

    fileprivate func rendererSettingsValue() -> RendererSettings {
        rendererSettings
    }

    fileprivate func rendererStateRevisionValue() -> UInt64 {
        rendererStateRevision
    }

    fileprivate func setRenderResourceRegistry(_ registry: RenderResourceRegistry) {
        renderResourceRegistry = registry
    }

    fileprivate func renderResourceRegistryValue() -> RenderResourceRegistry? {
        renderResourceRegistry
    }

    fileprivate func setRenderFrameSnapshot(_ snapshot: RenderFrameSnapshot?) {
        renderFrameSnapshot = snapshot
    }

    fileprivate func renderFrameSnapshotValue() -> RenderFrameSnapshot? {
        renderFrameSnapshot
    }

    func setAssetStateRevision(_ revision: UInt64) {
        assetStateRevision = revision
    }

    fileprivate func assetStateRevisionValue() -> UInt64 {
        assetStateRevision
    }

    fileprivate func setLightingInputs(_ inputs: LightingInputs) {
        lightingInputs = inputs
    }

    fileprivate func lightingInputsValue() -> LightingInputs? {
        lightingInputs
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
        MC_ASSERT(ShadowConstants.stride == 432, "ShadowConstants stride mismatch. Keep Swift and Metal layouts in sync.")
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

    fileprivate func viewContextValue() -> RenderViewContext {
        viewContext
    }

    fileprivate func setViewContext(_ context: RenderViewContext) {
        viewContext = context
    }

    fileprivate func engineContextValue() -> EngineContext {
        engineContext
    }

    fileprivate func setForwardPlusAllowed(_ allowed: Bool) {
        forwardPlusAllowed = allowed
    }

    fileprivate func forwardPlusAllowedValue() -> Bool {
        forwardPlusAllowed
    }

    fileprivate func markForwardPlusCullingDepthProduced(source: ForwardPlusCullingDepthSource) {
        switch source {
        case .none:
            return
        case .prepass:
            forwardPlusCullingDepthProducerMask |= 1 << 0
        case .fallback:
            forwardPlusCullingDepthProducerMask |= 1 << 1
        }
        forwardPlusCullingDepthSource = source
    }

    fileprivate func forwardPlusCullingDepthSourceValue() -> ForwardPlusCullingDepthSource {
        forwardPlusCullingDepthSource
    }

    fileprivate func forwardPlusCullingDepthProducerCountValue() -> Int {
        Int(forwardPlusCullingDepthProducerMask.nonzeroBitCount)
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
            sceneConstantsUploaded = Array(repeating: false, count: maxFramesInFlight)
        }
        if rendererSettingsBuffers.count < maxFramesInFlight {
            rendererSettingsBuffers = Array(repeating: nil, count: maxFramesInFlight)
            rendererSettingsBufferCapacities = Array(repeating: 0, count: maxFramesInFlight)
            rendererSettingsWriteOffsets = Array(repeating: 0, count: maxFramesInFlight)
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

    private func alignBufferSize(_ size: Int) -> Int {
        let alignment = 256
        return ((size + alignment - 1) / alignment) * alignment
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

    private func hashRendererSettings(_ settings: RendererSettings) -> UInt64 {
        var copy = settings
        return withUnsafeBytes(of: &copy) { bytes in
            var hash: UInt64 = 1469598103934665603
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            return hash
        }
    }
}
