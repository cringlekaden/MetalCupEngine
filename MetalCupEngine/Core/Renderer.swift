/// Renderer.swift
/// Renderer entry point and frame orchestration.
/// Created by Kaden Cringle

import MetalKit
import Foundation
import simd
import QuartzCore
import Foundation

public enum RenderPassType {
    case main
    case picking
    case depthPrepass
    case shadow
}

public final class Renderer: NSObject {
    public let engineContext: EngineContext
    public var delegate: RendererDelegate?
    public var inputAccumulator: InputAccumulator?
    public var settings: RendererSettings {
        get { engineContext.rendererSettings }
        set { engineContext.rendererSettings = newValue }
    }
    public let profiler = RendererProfiler()
    public var currentRenderPass: RenderPassType = .main
    public var useDepthPrepass: Bool = true
    public var layerFilterMask: LayerMask = .all

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private var _lastPerfFlags: UInt32 = 0
    private let _renderResources: RenderResources
    private let _renderGraph = RenderGraph()
    private let _frameContextStorage: RendererFrameContextStorage
    private let _skyRebuildFrameContextStorage: RendererFrameContextStorage
    let shadowRenderer: ShadowRenderer
    private var _lastFrameTimestamp: TimeInterval?
    private var _frameCount: UInt64 = 0
    private var _totalTime: Float = 0.0
    private var _unscaledTotalTime: Float = 0.0
    private var _timeScale: Float = 1.0
    private var _fixedDeltaTime: Float = 1.0 / 60.0
    private let _maxFrameDelta: Float = 0.25
    // MARK: - Views for capturing cubemap faces (canonical orientation, no axis flips)
    // +X right, -X left, +Y up, -Y down, +Z forward, -Z backward (Y-up, right-handed).
    private let _views: [float4x4] = [
        float4x4(lookAt: .zero, center: [ 1, 0, 0], up: [0, 1, 0]),
        float4x4(lookAt: .zero, center: [-1, 0, 0], up: [0, 1, 0]),
        float4x4(lookAt: .zero, center: [ 0, 1, 0], up: [0, 0, 1]),
        float4x4(lookAt: .zero, center: [ 0,-1, 0], up: [0, 0,-1]),
        float4x4(lookAt: .zero, center: [ 0, 0,-1], up: [0, 1, 0]),
        float4x4(lookAt: .zero, center: [ 0, 0, 1], up: [0, 1, 0])
    ]
    private var _viewProjections: [float4x4]!
    private let _environmentSize = 2048
    private let _irradianceSize = 64
    private let _prefilteredSize = 1024
    private let _environmentSizeFast = 512
    private let _irradianceSizeFast = 32
    private let _prefilteredSizeFast = 256
    private let _brdfLutSize = 512
    private let _skyRebuildQueue = DispatchQueue(label: "MetalCup.Renderer.SkyRebuild", qos: .userInitiated)
    private let _skyRebuildCooldown: Double = 2.0
    private let _skyInteractiveSettleDelay: Double = 4.0
    private var _skyRebuildInFlight = false
    private var _lastSkyRequestedSnapshot: SkyLightComponent?
    private var _lastSkyLiveSnapshot: SkyLightComponent?
    private var _lastSkyLiveUpdateTime: Double = 0.0
    private var _lastSkyRebuildStartTime: Double = 0.0
    private var _lastSkyInteractionTime: Double = 0.0
    private var _pendingSkySnapshot: SkyLightComponent?

    private struct IBLTextureHandles {
        let environment: AssetHandle
        let irradiance: AssetHandle
        let prefiltered: AssetHandle
        let brdf: AssetHandle
    }


    private var _iblHandleSets: [IBLTextureHandles] = []
    private var _iblFastHandles: IBLTextureHandles?
    private var _activeIBLHandleIndex = 0
    private var _brdfPipelineStateByFormat: [MTLPixelFormat: MTLRenderPipelineState] = [:]

    // MARK: - Static sizes

    public private(set) var screenSize = SIMD2<Float>(0, 0)
    public private(set) var drawableSize = SIMD2<Float>(0, 0)
    public private(set) var viewportSize = SIMD2<Float>(0, 0)
    public var aspectRatio: Float {
        let size = (viewportSize.x > 0 && viewportSize.y > 0) ? viewportSize : screenSize
        return size.y.isZero ? 1 : size.x / size.y
    }

    // MARK: - Init

    init(_ mtkView: MTKView, engineContext: EngineContext) {
        self.engineContext = engineContext
        self._renderResources = RenderResources(
            preferences: engineContext.preferences,
            settingsProvider: { engineContext.rendererSettings },
            settingsUpdater: { updated in engineContext.rendererSettings = updated },
            assetManager: engineContext.assets,
            device: engineContext.device
        )
        self._frameContextStorage = RendererFrameContextStorage(engineContext: engineContext)
        self._skyRebuildFrameContextStorage = RendererFrameContextStorage(engineContext: engineContext)
        self.shadowRenderer = ShadowRenderer(engineContext: engineContext)
        super.init()
        self._lastPerfFlags = settings.perfFlags
        _viewProjections = _views.map { _projection * $0 }
        updateScreenSize(view: mtkView) // builds render targets + base pass desc
        let iblAllocationStart = CACurrentMediaTime()
        BuiltinAssets.registerIBLTextures(
            assetManager: engineContext.assets,
            preferences: engineContext.preferences,
            device: engineContext.device,
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            brdfLutSize: _brdfLutSize
        )
        _ = ensureBRDFLUTTexture()
        prewarmIBLPipelinesWithTiming()
        BuiltinAssets.registerFallbackIBLTextures(assetManager: engineContext.assets, preferences: engineContext.preferences, device: engineContext.device)
        let builtinHandles = IBLTextureHandles(
            environment: BuiltinAssets.environmentCubemap,
            irradiance: BuiltinAssets.irradianceCubemap,
            prefiltered: BuiltinAssets.prefilteredCubemap,
            brdf: BuiltinAssets.brdfLut
        )
        let alternateHandles = IBLTextureHandles(
            environment: AssetHandle(),
            irradiance: AssetHandle(),
            prefiltered: AssetHandle(),
            brdf: BuiltinAssets.brdfLut
        )
        _iblHandleSets = [builtinHandles, alternateHandles]
        _activeIBLHandleIndex = 0
        ensureIBLTextureSet(handles: alternateHandles)
        let fastHandles = IBLTextureHandles(
            environment: AssetHandle(),
            irradiance: AssetHandle(),
            prefiltered: AssetHandle(),
            brdf: BuiltinAssets.brdfLut
        )
        _iblFastHandles = fastHandles
        ensureIBLTextureSet(
            handles: fastHandles,
            environmentSize: _environmentSizeFast,
            irradianceSize: _irradianceSizeFast,
            prefilteredSize: _prefilteredSizeFast,
            labelSuffix: "Fast"
        )
        _lastSkyInteractionTime = CACurrentMediaTime()
        let iblAllocationEnd = CACurrentMediaTime()
        EngineLoggerContext.log(
            "IBL resource allocation/prewarm dt=\(String(format: "%.3f", iblAllocationEnd - iblAllocationStart))s",
            level: .debug,
            category: .renderer
        )
        let frameContext = _frameContextStorage.beginFrame()
        _frameContextStorage.updateRendererState(
            settings: settings,
            currentRenderPass: currentRenderPass,
            useDepthPrepass: useDepthPrepass,
            layerFilterMask: layerFilterMask
        )
        renderBRDFLUT(frameContext: frameContext)
    }

    // MARK: - IBL generation config

    private struct IBLGenerationConfig {
        var qualityPreset: IBLQualityPreset
        var irradianceSamples: UInt32
        var prefilterSamplesMin: UInt32
        var prefilterSamplesMax: UInt32
        var fireflyClamp: Float
        var fireflyClampEnabled: Bool
        var samplingStrategy: String
    }

    private enum IBLBuildMode: String {
        case interactive
        case final
    }

    // MARK: - Render pass descriptor helpers
    private func makeRenderPassDescriptor(
        colorTarget: AssetHandle,
        depthTarget: AssetHandle? = nil,
        slice: Int? = nil,
        level: Int = 0,
        depthLoadAction: MTLLoadAction = .clear
    ) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = engineContext.assets.texture(handle: colorTarget)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        pass.colorAttachments[0].level = level
        if let slice {
            pass.colorAttachments[0].slice = slice
        }
        if let depthTarget {
            pass.depthAttachment.texture = engineContext.assets.texture(handle: depthTarget)
            pass.depthAttachment.loadAction = depthLoadAction
            pass.depthAttachment.storeAction = .store
        }
        return pass
    }

    private func makeRenderPassDescriptor(
        colorTexture: MTLTexture,
        depthTexture: MTLTexture? = nil,
        slice: Int? = nil,
        level: Int = 0,
        depthLoadAction: MTLLoadAction = .clear
    ) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        pass.colorAttachments[0].level = level
        if let slice {
            pass.colorAttachments[0].slice = slice
        }
        if let depthTexture {
            pass.depthAttachment.texture = depthTexture
            pass.depthAttachment.loadAction = depthLoadAction
            pass.depthAttachment.storeAction = .store
        }
        return pass
    }

    private func createColorOnlyRenderPassDescriptor(colorTarget: AssetHandle) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: colorTarget)
    }

    private func createCubemapRenderPassDescriptor(target: AssetHandle, face: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: target, slice: face, level: 0)
    }

    private func createMippedCubemapRenderPassDescriptor(target: AssetHandle, face: Int, mip: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: target, slice: face, level: mip)
    }

    private func createCubemapRenderPassDescriptor(texture: MTLTexture, face: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTexture: texture, slice: face, level: 0)
    }

    private func createMippedCubemapRenderPassDescriptor(texture: MTLTexture, face: Int, mip: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTexture: texture, slice: face, level: mip)
    }

    // MARK: - IBL generation
    private func iblQualityPreset() -> IBLQualityPreset {
        return IBLQualityPreset(rawValue: settings.iblQualityPreset) ?? .high
    }

    private func iblSampleMultiplier(for preset: IBLQualityPreset) -> Float {
        switch preset {
        case .low:
            return 0.25
        case .medium:
            return 0.5
        case .high:
            return 1.0
        case .ultra:
            return 2.0
        case .custom:
            return max(settings.iblSampleMultiplier, 0.1)
        }
    }

    private func iblConfig(mode: IBLBuildMode) -> IBLGenerationConfig {
        let preset = iblQualityPreset()
        let multiplier = iblSampleMultiplier(for: preset)
        let modeScale: Float = (mode == .interactive) ? 0.2 : 1.0
        let irradianceSamples = UInt32(max(128.0, min(8192.0, modeScale * multiplier * 2048.0)))
        let prefilterBase = max(64.0, min(4096.0, modeScale * multiplier * 1024.0))
        let minSamples = UInt32(max(64.0, min(1024.0, prefilterBase * 0.20)))
        let maxSamples = UInt32(max(128.0, min(4096.0, prefilterBase)))
        return IBLGenerationConfig(
            qualityPreset: preset,
            irradianceSamples: irradianceSamples,
            prefilterSamplesMin: minSamples,
            prefilterSamplesMax: maxSamples,
            fireflyClamp: settings.iblFireflyClamp,
            fireflyClampEnabled: settings.iblFireflyClampEnabled != 0,
            samplingStrategy: mode == .interactive
                ? "interactive reduced-sample cosine + GGX"
                : "cosine + GGX importance sampling"
        )
    }

    private func iblMipCount(for size: Int) -> Int {
        guard size > 0 else { return 1 }
        return Int(floor(log2(Double(size)))) + 1
    }

    private func makeCubemapTexture(size: Int, mipmapped: Bool, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: engineContext.preferences.HDRPixelFormat,
            size: size,
            mipmapped: mipmapped
        )
        if mipmapped {
            descriptor.mipmapLevelCount = iblMipCount(for: size)
        }
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = engineContext.device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }

    private func ensureIBLTextureSet(handles: IBLTextureHandles) {
        ensureIBLTextureSet(
            handles: handles,
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            labelSuffix: "Next"
        )
    }

    private func ensureIBLTextureSet(
        handles: IBLTextureHandles,
        environmentSize: Int,
        irradianceSize: Int,
        prefilteredSize: Int,
        labelSuffix: String
    ) {
        if engineContext.assets.texture(handle: handles.environment) == nil,
           let env = makeCubemapTexture(size: environmentSize, mipmapped: true, label: "IBL.EnvironmentCubemap.\(labelSuffix)") {
            engineContext.assets.registerRuntimeTexture(handle: handles.environment, texture: env)
        }
        if engineContext.assets.texture(handle: handles.irradiance) == nil,
           let irr = makeCubemapTexture(size: irradianceSize, mipmapped: false, label: "IBL.IrradianceCubemap.\(labelSuffix)") {
            engineContext.assets.registerRuntimeTexture(handle: handles.irradiance, texture: irr)
        }
        if engineContext.assets.texture(handle: handles.prefiltered) == nil,
           let pre = makeCubemapTexture(size: prefilteredSize, mipmapped: true, label: "IBL.PrefilteredCubemap.\(labelSuffix)") {
            engineContext.assets.registerRuntimeTexture(handle: handles.prefiltered, texture: pre)
        }
    }

    private func prewarmIBLPipelinesWithTiming() {
        let warmStart = CACurrentMediaTime()
        let cubemapStart = CACurrentMediaTime()
        _ = engineContext.graphics.renderPipelineStates[.Cubemap]
        let cubemapDt = CACurrentMediaTime() - cubemapStart
        let irradianceStart = CACurrentMediaTime()
        _ = engineContext.graphics.renderPipelineStates[.IrradianceMap]
        let irradianceDt = CACurrentMediaTime() - irradianceStart
        let prefilteredStart = CACurrentMediaTime()
        _ = engineContext.graphics.renderPipelineStates[.PrefilteredMap]
        let prefilteredDt = CACurrentMediaTime() - prefilteredStart
        let proceduralStart = CACurrentMediaTime()
        _ = engineContext.graphics.renderPipelineStates[.ProceduralSkyCubemap]
        let proceduralDt = CACurrentMediaTime() - proceduralStart
        let totalDt = CACurrentMediaTime() - warmStart
        EngineLoggerContext.log(
            "IBL pipeline warmup total=\(String(format: "%.3f", totalDt))s [cubemap=\(String(format: "%.3f", cubemapDt))s, irr=\(String(format: "%.3f", irradianceDt))s, pre=\(String(format: "%.3f", prefilteredDt))s, procedural=\(String(format: "%.3f", proceduralDt))s]",
            level: .debug,
            category: .renderer
        )
    }

    private func activeIBLHandles() -> IBLTextureHandles {
        return _iblHandleSets[_activeIBLHandleIndex]
    }

    private func nextIBLHandles() -> IBLTextureHandles {
        let nextIndex = (_activeIBLHandleIndex + 1) % _iblHandleSets.count
        return _iblHandleSets[nextIndex]
    }

    private func skySettingsMatch(_ lhs: SkyLightComponent, _ rhs: SkyLightComponent) -> Bool {
        return !SkySystem.requiresIBLRebuild(previous: lhs, next: rhs)
    }

    private func validateIBLResources(environment: MTLTexture?, irradiance: MTLTexture?, prefiltered: MTLTexture?) {
        if let env = environment {
            MC_ASSERT(env.textureType == .typeCube, "Environment texture must be cubemap.")
            MC_ASSERT(env.mipmapLevelCount >= 1, "Environment texture missing mip levels.")
            MC_ASSERT(env.width == env.height, "Environment texture must be square.")
        }
        if let irr = irradiance {
            MC_ASSERT(irr.textureType == .typeCube, "Irradiance texture must be cubemap.")
        }
        if let pre = prefiltered {
            MC_ASSERT(pre.textureType == .typeCube, "Prefiltered texture must be cubemap.")
            MC_ASSERT(pre.mipmapLevelCount >= 1, "Prefiltered texture missing mip levels.")
            MC_ASSERT(pre.width == pre.height, "Prefiltered texture must be square.")
        }
    }

    private func renderSkyToEnvironmentMap(hdriTexture: MTLTexture, intensity: Float, targetEnvironment: MTLTexture, frameContext: RendererFrameContext, commandBuffer: MTLCommandBuffer) {
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        validateIBLResources(environment: targetEnvironment, irradiance: nil, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetEnvironment, face: face)) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.Cubemap])
            encoder.setCullMode(.none)
            var vp = matrix_identity_float4x4
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            var cubemapParams = SIMD2<Float>(max(intensity, 0.0), Float(face))
            encoder.setFragmentBytes(&cubemapParams, length: MemoryLayout<SIMD2<Float>>.stride, index: FragmentBufferIndex.skyIntensity)
            encoder.setFragmentTexture(hdriTexture, index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
            quadMesh.drawPrimitives(encoder, frameContext: frameContext)
            encoder.endEncoding()
        }
        if targetEnvironment.mipmapLevelCount > 1,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: targetEnvironment)
            blit.endEncoding()
        }
    }

    private func renderIrradianceMap(sourceEnvironment: MTLTexture,
                                     targetIrradiance: MTLTexture,
                                     config: IBLGenerationConfig,
                                     frameContext: RendererFrameContext,
                                     commandBuffer: MTLCommandBuffer) {
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        validateIBLResources(environment: sourceEnvironment, irradiance: targetIrradiance, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetIrradiance, face: face)) else { continue }
            encoder.label = "Irradiance Cubemap face: \(face)"
            encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.IrradianceMap])
            encoder.setCullMode(.none)
            var vp = matrix_identity_float4x4
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            var params = IBLIrradianceParams()
            params.sampleCount = config.irradianceSamples
            params.fireflyClamp = config.fireflyClamp
            params.fireflyClampEnabled = config.fireflyClampEnabled ? 1 : 0
            params.padding = Float(face)
            encoder.setFragmentBytes(&params, length: IBLIrradianceParams.stride, index: FragmentBufferIndex.iblParams)
            encoder.setFragmentTexture(sourceEnvironment, index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
            quadMesh.drawPrimitives(encoder, frameContext: frameContext)
            encoder.endEncoding()
        }
    }

    private func renderPrefilteredSpecularMap(sourceEnvironment: MTLTexture,
                                              targetPrefiltered: MTLTexture,
                                              config: IBLGenerationConfig,
                                              frameContext: RendererFrameContext,
                                              commandBuffer: MTLCommandBuffer) {
        let mipCount = targetPrefiltered.mipmapLevelCount
        let baseSize = targetPrefiltered.width
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        validateIBLResources(environment: sourceEnvironment, irradiance: nil, prefiltered: targetPrefiltered)
        if sourceEnvironment.mipmapLevelCount > 1, let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: sourceEnvironment)
            blit.endEncoding()
        }
        for mip in 0..<mipCount {
            let roughness = Float(mip) / Float(max(mipCount - 1, 1))
            let mipSize = max(1, baseSize >> mip)
            for face in 0..<6 {
                let passDescriptor = createMippedCubemapRenderPassDescriptor(texture: targetPrefiltered, face: face, mip: mip)
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { continue }
                encoder.label = "Specular face \(face), mip \(mip)"
                encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.PrefilteredMap])
                encoder.setCullMode(.none)
                encoder.setViewport(MTLViewport(
                    originX: 0, originY: 0,
                    width: Double(mipSize), height: Double(mipSize),
                    znear: 0, zfar: 1
                ))
                var vp = matrix_identity_float4x4
                encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
                var params = IBLPrefilterParams()
                params.roughness = roughness
                params.sampleCount = prefilterSampleCount(for: roughness, mipIndex: mip, mipCount: mipCount, config: config)
                params.fireflyClamp = config.fireflyClamp
                params.fireflyClampEnabled = config.fireflyClampEnabled ? 1 : 0
                params.envMipCount = Float(sourceEnvironment.mipmapLevelCount)
                params.padding = Float(face)
                encoder.setFragmentBytes(&params, length: IBLPrefilterParams.stride, index: FragmentBufferIndex.iblParams)
                encoder.setFragmentTexture(sourceEnvironment, index: IBLTextureIndex.environment)
                encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
                quadMesh.drawPrimitives(encoder, frameContext: frameContext)
                encoder.endEncoding()
            }
        }
    }

    private func prefilterSampleCount(for roughness: Float, mipIndex: Int, mipCount: Int, config: IBLGenerationConfig) -> UInt32 {
        let glossyFactor = pow(max(1.0 - roughness, 0.0), 2.0)
        let mipT = Float(mipIndex) / Float(max(mipCount - 1, 1))
        let mipScale = max(0.25, 1.0 - mipT * 0.70)
        let range = max(Float(config.prefilterSamplesMax - config.prefilterSamplesMin), 1.0)
        let samples = Float(config.prefilterSamplesMin) + range * glossyFactor * mipScale
        return UInt32(max(Float(config.prefilterSamplesMin), min(Float(config.prefilterSamplesMax), samples)))
    }

    private func createBRDFLUTTexture(pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: _brdfLutSize,
            height: _brdfLutSize,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return engineContext.device.makeTexture(descriptor: descriptor)
    }

    private func resolveBRDFLUTPixelFormat() -> MTLPixelFormat {
        if createBRDFLUTTexture(pixelFormat: .rg16Float) != nil {
            return .rg16Float
        }
        if createBRDFLUTTexture(pixelFormat: .rg32Float) != nil {
            return .rg32Float
        }
        return .rg16Float
    }

    @discardableResult
    private func ensureBRDFLUTTexture() -> MTLTexture? {
        let targetFormat = resolveBRDFLUTPixelFormat()
        if let existing = engineContext.assets.texture(handle: BuiltinAssets.brdfLut),
           existing.width == _brdfLutSize,
           existing.height == _brdfLutSize,
           existing.pixelFormat == targetFormat {
            return existing
        }
        guard let texture = createBRDFLUTTexture(pixelFormat: targetFormat) else { return nil }
        texture.label = "IBL.BRDFLUT"
        engineContext.assets.registerRuntimeTexture(handle: BuiltinAssets.brdfLut, texture: texture)
        return texture
    }

    private func brdfPipelineState(for pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        if pixelFormat == .rg16Float {
            return engineContext.graphics.renderPipelineStates[.BRDF]
        }
        if let cached = _brdfPipelineStateByFormat[pixelFormat] {
            return cached
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "BRDF (\(pixelFormat.rawValue))"
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.depthAttachmentPixelFormat = .invalid
        descriptor.vertexFunction = engineContext.graphics.shaders[.FSQuadVertex]
        descriptor.fragmentFunction = engineContext.graphics.shaders[.BRDFFragment]
        descriptor.vertexDescriptor = engineContext.graphics.vertexDescriptors[.Simple]
        guard let state = try? engineContext.device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        _brdfPipelineStateByFormat[pixelFormat] = state
        return state
    }

    private func renderBRDFLUT(frameContext: RendererFrameContext) {
        guard let brdfTexture = ensureBRDFLUTTexture() else { return }
        guard let pipelineState = brdfPipelineState(for: brdfTexture.pixelFormat) else { return }
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render BRDF LUT"
        let passDescriptor = makeRenderPassDescriptor(colorTexture: brdfTexture)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        encoder.label = "BRDF LUT Encoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setCullMode(.none)
        quadMesh.drawPrimitives(encoder, frameContext: frameContext)
        encoder.endEncoding()
        commandBuffer.commit()
    }

    private func renderProceduralSkyToEnvironmentMap(params: SkyParams, targetEnvironment: MTLTexture, frameContext: RendererFrameContext, commandBuffer: MTLCommandBuffer) {
        guard let cubemapMesh = engineContext.assets.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        validateIBLResources(environment: targetEnvironment, irradiance: nil, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetEnvironment, face: face)) else { continue }
            encoder.label = "Procedural Sky face \(face)"
            encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.ProceduralSkyCubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            var skyParams = params
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            encoder.setFragmentBytes(&skyParams, length: SkyParams.stride, index: FragmentBufferIndex.skyParams)
            cubemapMesh.drawPrimitives(encoder, frameContext: frameContext)
            encoder.endEncoding()
        }
        if targetEnvironment.mipmapLevelCount > 1,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: targetEnvironment)
            blit.endEncoding()
        }
    }

    private func skyParams(from sky: SkyLightComponent) -> SkyParams {
        var params = SkyParams()
        let worldSunDirection = SkySystem.sunDirection(azimuthDegrees: sky.azimuthDegrees,
                                                       elevationDegrees: sky.elevationDegrees)
        params.sunDirection = SkySystem.skyShaderSunDirection(fromWorldSunDirection: worldSunDirection)
        params.sunAngularRadius = max(0.0001, sky.sunSizeDegrees * Float.pi / 180.0)
        params.sunColor = SIMD3<Float>(1.0, 0.98, 0.92)
        params.sunIntensity = max(1.0, sky.intensity * 10.0)
        params.turbidity = max(1.0, sky.turbidity)
        params.intensity = max(0.0, sky.intensity)
        params.skyTime = _totalTime
        params.skyTint = sky.skyTint
        params.zenithTint = sky.zenithTint
        params.horizonTint = sky.horizonTint
        params.gradientStrength = max(0.0, sky.gradientStrength)
        params.hazeDensity = max(0.0, sky.hazeDensity)
        params.hazeFalloff = max(0.01, sky.hazeFalloff)
        params.hazeHeight = sky.hazeHeight
        params.ozoneStrength = max(0.0, sky.ozoneStrength)
        params.ozoneTint = sky.ozoneTint
        params.sunHaloSize = max(0.1, sky.sunHaloSize)
        params.sunHaloIntensity = max(0.0, sky.sunHaloIntensity)
        params.sunHaloSoftness = max(0.05, sky.sunHaloSoftness)
        params.cloudsEnabled = sky.cloudsEnabled ? 1 : 0
        params.cloudsCoverage = min(max(sky.cloudsCoverage, 0.0), 1.0)
        params.cloudsSoftness = min(max(sky.cloudsSoftness, 0.01), 1.0)
        params.cloudsScale = max(0.01, sky.cloudsScale)
        params.cloudsSpeed = sky.cloudsSpeed
        params.cloudsWindDirection = sky.cloudsWindDirection
        params.cloudsHeight = min(max(sky.cloudsHeight, 0.0), 1.0)
        params.cloudsThickness = min(max(sky.cloudsThickness, 0.0), 1.0)
        params.cloudsBrightness = max(0.0, sky.cloudsBrightness)
        params.cloudsSunInfluence = max(0.0, sky.cloudsSunInfluence)
        return params
    }

    private func updateSkyIfNeeded(scene: EngineScene) {
        guard let skyEntry = scene.ecs.activeSkyLight() else { return }
        let entity = skyEntry.0
        var sky = skyEntry.1
        guard sky.enabled else { return }

        let activeHandles = activeIBLHandles()
        var didUpdateHandles = false
        var handleUpdate = sky
        if handleUpdate.iblEnvironmentHandle == nil {
            handleUpdate.iblEnvironmentHandle = activeHandles.environment
            didUpdateHandles = true
        }
        if handleUpdate.iblIrradianceHandle == nil {
            handleUpdate.iblIrradianceHandle = activeHandles.irradiance
            didUpdateHandles = true
        }
        if handleUpdate.iblPrefilteredHandle == nil {
            handleUpdate.iblPrefilteredHandle = activeHandles.prefiltered
            didUpdateHandles = true
        }
        if handleUpdate.iblBrdfHandle == nil {
            handleUpdate.iblBrdfHandle = activeHandles.brdf
            didUpdateHandles = true
        }
        if didUpdateHandles {
            scene.ecs.add(handleUpdate, to: entity)
            sky = handleUpdate
        }

        if sky.mode == .hdri, sky.hdriHandle == nil {
            var resolvedHandle: AssetHandle?
            scene.ecs.viewSky { _, skyComponent in
                if resolvedHandle == nil {
                    resolvedHandle = skyComponent.environmentMapHandle
                }
            }
            if let resolvedHandle {
                var updated = sky
                updated.hdriHandle = resolvedHandle
                updated.needsRebuild = true
                scene.ecs.add(updated, to: entity)
                sky = updated
            }
        }

        let hdriLoaded = sky.mode != .hdri || (sky.hdriHandle.flatMap { engineContext.assets.texture(handle: $0) } != nil)
        if sky.mode == .hdri, !hdriLoaded { return }

        let environment = sky.iblEnvironmentHandle.flatMap { engineContext.assets.texture(handle: $0) }
        let irradiance = sky.iblIrradianceHandle.flatMap { engineContext.assets.texture(handle: $0) }
        let prefiltered = sky.iblPrefilteredHandle.flatMap { engineContext.assets.texture(handle: $0) }
        let isFallbackIBL = (environment?.width ?? 0) <= 1
            || (irradiance?.width ?? 0) <= 1
            || (prefiltered?.width ?? 0) <= 1
        if isFallbackIBL && !sky.needsRebuild {
            sky.needsRebuild = true
            sky.rebuildRequested = true
            scene.ecs.add(sky, to: entity)
        }

        let now = CACurrentMediaTime()
        if !sky.needsRebuild {
            let paramsChanged = _lastSkyLiveSnapshot.map { !SkySystem.liveSkyParamsMatch($0, sky) } ?? true
            let wantsCloudMotion = sky.cloudsEnabled && abs(sky.cloudsSpeed) > 0.0001
            let needsCloudTick = wantsCloudMotion && (now - _lastSkyLiveUpdateTime) > 0.35
            let shouldUpdateLive = paramsChanged || needsCloudTick
            if shouldUpdateLive && !_skyRebuildInFlight && (now - sky.lastRebuildTime) >= _skyRebuildCooldown {
                if let requested = _lastSkyRequestedSnapshot, SkySystem.liveSkyParamsMatch(requested, sky) {
                    _lastSkyLiveUpdateTime = now
                } else {
                var updated = sky
                updated.needsRebuild = true
                updated.rebuildRequested = true
                scene.ecs.add(updated, to: entity)
                sky = updated
                _lastSkyRequestedSnapshot = updated
                _lastSkyLiveUpdateTime = now
                _lastSkyInteractionTime = now
                }
            }
        }
        if _skyRebuildInFlight {
            _pendingSkySnapshot = sky
            return
        }
        if !sky.needsRebuild { return }
        let allowRebuild = sky.realtimeUpdate || sky.rebuildRequested
        if !allowRebuild { return }
        if (now - _lastSkyRebuildStartTime) < _skyRebuildCooldown {
            _pendingSkySnapshot = sky
            return
        }

        var updated = sky
        updated.lastRebuildTime = now
        updated.rebuildRequested = false
        scene.ecs.add(updated, to: entity)

        let snapshot = _pendingSkySnapshot ?? updated
        _pendingSkySnapshot = nil
        let nextIndex = (_activeIBLHandleIndex + 1) % _iblHandleSets.count
        let finalHandles = _iblHandleSets[nextIndex]
        let withinInteractiveWindow = (now - _lastSkyInteractionTime) < _skyInteractiveSettleDelay
        let buildMode: IBLBuildMode = withinInteractiveWindow ? .interactive : .final
        let targetHandles = (buildMode == .interactive ? (_iblFastHandles ?? finalHandles) : finalHandles)
        let modeLabel = buildMode.rawValue
        _skyRebuildInFlight = true
        _lastSkyRebuildStartTime = now
        let requestStart = CACurrentMediaTime()
        EngineLoggerContext.log(
            "IBL rebuild scheduled (t=\(String(format: "%.3f", now)), mode=\(modeLabel))",
            level: .debug,
            category: .renderer
        )
        _skyRebuildQueue.async { [weak self] in
            guard let self = self else { return }
            let isMainThread = Thread.isMainThread
            MC_ASSERT(!isMainThread, "IBL rebuild must not run on the main thread.")
            let threadLabel = isMainThread ? "main" : "background"
            let frameContext = self._skyRebuildFrameContextStorage.beginFrame()
            let generationConfig = self.iblConfig(mode: buildMode)
            let resourceLookupStart = CACurrentMediaTime()
            guard let targetEnv = self.engineContext.assets.texture(handle: targetHandles.environment),
                  let targetIrr = self.engineContext.assets.texture(handle: targetHandles.irradiance),
                  let targetPre = self.engineContext.assets.texture(handle: targetHandles.prefiltered) else {
                EngineLoggerContext.log(
                    "IBL rebuild aborted: missing preallocated textures.",
                    level: .warning,
                    category: .renderer
                )
                DispatchQueue.main.async { [weak self] in
                    self?._skyRebuildInFlight = false
                }
                return
            }
            let resourceLookupDt = CACurrentMediaTime() - resourceLookupStart
            guard let commandBuffer = self.engineContext.commandQueue.makeCommandBuffer() else {
                EngineLoggerContext.log(
                    "IBL rebuild aborted: failed to create command buffer.",
                    level: .warning,
                    category: .renderer
                )
                DispatchQueue.main.async { [weak self] in
                    self?._skyRebuildInFlight = false
                }
                return
            }
            commandBuffer.label = "IBL Rebuild"
            let encodeStart = CACurrentMediaTime()
            var hdriResolveDt: Double = 0.0
            switch snapshot.mode {
            case .hdri:
                let hdriResolveStart = CACurrentMediaTime()
                guard let hdriHandle = snapshot.hdriHandle,
                      let hdriTexture = self.engineContext.assets.texture(handle: hdriHandle) else {
                    EngineLoggerContext.log(
                        "IBL rebuild aborted: HDRI texture not resolved.",
                        level: .warning,
                        category: .renderer
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?._skyRebuildInFlight = false
                    }
                    return
                }
                hdriResolveDt = CACurrentMediaTime() - hdriResolveStart
                self.renderSkyToEnvironmentMap(
                    hdriTexture: hdriTexture,
                    intensity: snapshot.intensity,
                    targetEnvironment: targetEnv,
                    frameContext: frameContext,
                    commandBuffer: commandBuffer
                )
            case .procedural:
                let params = self.skyParams(from: snapshot)
                self.renderProceduralSkyToEnvironmentMap(
                    params: params,
                    targetEnvironment: targetEnv,
                    frameContext: frameContext,
                    commandBuffer: commandBuffer
                )
            }

            self.renderIrradianceMap(
                sourceEnvironment: targetEnv,
                targetIrradiance: targetIrr,
                config: generationConfig,
                frameContext: frameContext,
                commandBuffer: commandBuffer
            )
            self.renderPrefilteredSpecularMap(
                sourceEnvironment: targetEnv,
                targetPrefiltered: targetPre,
                config: generationConfig,
                frameContext: frameContext,
                commandBuffer: commandBuffer
            )
            let encodeDt = CACurrentMediaTime() - encodeStart

            var commitTimestamp: Double = 0.0
            var commitCpuDt: Double = 0.0
            commandBuffer.addCompletedHandler { [weak self] _ in
                let completed = CACurrentMediaTime()
                let commitToCompleteDt = commitTimestamp > 0.0 ? (completed - commitTimestamp) : 0.0
                let totalCpuWallDt = completed - requestStart
                EngineLoggerContext.log(
                    "IBL rebuild timings [mode=\(modeLabel), thread=\(threadLabel), waitUntilCompleted=none]: totalCpuWall=\(String(format: "%.3f", totalCpuWallDt))s, resources=\(String(format: "%.3f", resourceLookupDt))s, hdriResolve=\(String(format: "%.3f", hdriResolveDt))s, encode=\(String(format: "%.3f", encodeDt))s, commitCpu=\(String(format: "%.3f", commitCpuDt))s, commitToComplete=\(String(format: "%.3f", commitToCompleteDt))s",
                    level: .debug,
                    category: .renderer
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self._skyRebuildInFlight = false
                    guard let currentScene = self.delegate?.activeScene(),
                          let currentEntry = currentScene.ecs.activeSkyLight() else { return }
                    let (currentEntity, currentSky) = currentEntry
                    var regen = currentSky
                    if self.skySettingsMatch(currentSky, snapshot) {
                        if buildMode == .interactive {
                            regen.iblEnvironmentHandle = targetHandles.environment
                            regen.iblIrradianceHandle = targetHandles.irradiance
                            regen.iblPrefilteredHandle = targetHandles.prefiltered
                            regen.iblBrdfHandle = targetHandles.brdf
                            regen.needsRebuild = true
                            regen.rebuildRequested = true
                        } else {
                            self._activeIBLHandleIndex = nextIndex
                            regen.iblEnvironmentHandle = finalHandles.environment
                            regen.iblIrradianceHandle = finalHandles.irradiance
                            regen.iblPrefilteredHandle = finalHandles.prefiltered
                            regen.iblBrdfHandle = finalHandles.brdf
                            regen.needsRebuild = false
                            regen.rebuildRequested = false
                        }
                        self._lastSkyLiveSnapshot = regen
                        self._lastSkyRequestedSnapshot = regen
                    } else {
                        regen.needsRebuild = true
                    }
                    if let pending = self._pendingSkySnapshot {
                        let pendingMatches = self.skySettingsMatch(pending, snapshot)
                            && SkySystem.liveSkyParamsMatch(pending, snapshot)
                        if pendingMatches {
                            self._pendingSkySnapshot = nil
                        } else {
                            regen.needsRebuild = true
                            regen.rebuildRequested = true
                        }
                    }
                    currentScene.ecs.add(regen, to: currentEntity)
                    let swapped = CACurrentMediaTime()
                    EngineLoggerContext.log(
                        "IBL rebuild swapped (t=\(String(format: "%.3f", swapped)))",
                        level: .debug,
                        category: .renderer
                    )
                }
            }
            let commitCpuStart = CACurrentMediaTime()
            commitTimestamp = commitCpuStart
            commandBuffer.commit()
            commitCpuDt = CACurrentMediaTime() - commitCpuStart
        }
    }

}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    public func updateScreenSize(view: MTKView) {
        applyViewSizes(view: view)
        delegate?.activeScene()?.updateAspectRatio()
        _renderResources.rebuild(drawableSize: view.drawableSize)
    }

    private func applyViewSizes(view: MTKView) {
        screenSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        drawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if viewportSize.x.isZero || viewportSize.y.isZero {
            viewportSize = screenSize
        }
    }

    private func updateFrameSizingIfNeeded(view: MTKView) {
        if _lastPerfFlags != settings.perfFlags {
            _lastPerfFlags = settings.perfFlags
            updateScreenSize(view: view)
        }
        let currentSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if drawableSize != currentSize
            || !_renderResources.isValid(for: view.drawableSize) {
            drawableSize = currentSize
            updateScreenSize(view: view)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateScreenSize(view: view)
    }


    private func renderToWindow(renderPipelineState: RenderPipelineStateType, view: MTKView, commandBuffer: MTLCommandBuffer, frameContext: RendererFrameContext) {
        guard let rpd = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        let pass = FullscreenPass(
            pipeline: renderPipelineState,
            label: "Final Composite -> Drawable",
            sampler: .LinearClampToZero,
            useSampler: true,
            texture0: engineContext.assets.texture(handle: BuiltinAssets.baseColorRender),
            useTexture0: true,
            texture1: engineContext.assets.texture(handle: BuiltinAssets.bloomPing),
            useTexture1: true,
            outlineMask: nil,
            useOutlineMask: false,
            depth: nil,
            useDepth: false,
            grid: nil,
            useGrid: false,
            settings: settings
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frameContext, graphics: engineContext.graphics)
        encoder.endEncoding()
    }

    public func draw(in view: MTKView) {
        let frameStart = CACurrentMediaTime()
        updateFrameSizingIfNeeded(view: view)
        guard let drawable = view.currentDrawable,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0 else { return }
        let updateStart = CACurrentMediaTime()
        let frameTime = buildFrameTime(timestamp: frameStart)
        let inputState = inputAccumulator?.snapshotAndReset() ?? InputState(
            mousePosition: .zero,
            mouseDelta: .zero,
            scrollDelta: 0,
            mouseButtons: [],
            keys: [],
            viewportOrigin: .zero,
            viewportSize: .zero,
            textInput: ""
        )
        let frame = FrameContext(time: frameTime, input: inputState)
        delegate?.update(frame: frame)
        profiler.record(.update, seconds: CACurrentMediaTime() - updateStart)
        let frameContext = _frameContextStorage.beginFrame()
        _frameContextStorage.updateRendererState(
            settings: settings,
            currentRenderPass: currentRenderPass,
            useDepthPrepass: useDepthPrepass,
            layerFilterMask: layerFilterMask
        )
        let renderStart = CACurrentMediaTime()
        // Scene Pass -> Bloom -> Final Composite -> ImGui overlays
        let sceneView = delegate?.buildSceneView(renderer: self) ?? SceneView(viewportSize: viewportSize)
        guard let overlayCommandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        overlayCommandBuffer.label = "MetalCup Frame"
        let frameId = frameContext.currentFrameCounter()
        let frameIndex = frameContext.currentFrameIndex()
        let gpuPassTimingsEnabled = profiler.gpuPassTimingsEnabled()
        let counterSupported = profiler.gpuCounterSamplingSupported(device: engineContext.device)
        let useCounterSampling = gpuPassTimingsEnabled && counterSupported
        if useCounterSampling {
            _ = profiler.prepareGpuCounterSampling(device: engineContext.device, inFlightFrames: frameContext.maxFramesInFlight())
            profiler.beginGpuCounterFrame(frameIndex: frameIndex, frameId: frameId)
        }
        let graphFrame = RenderGraphFrame(
            renderer: self,
            engineContext: engineContext,
            view: view,
            sceneView: sceneView,
            commandBuffer: overlayCommandBuffer,
            resources: _renderResources,
            delegate: delegate,
            frameContext: frameContext,
            profiler: profiler
        )
        let gpuStart = CACurrentMediaTime()
        if !useCounterSampling {
            overlayCommandBuffer.addCompletedHandler { [weak self] buffer in
                let duration = buffer.gpuEndTime - buffer.gpuStartTime
                let resolved = duration > 0 ? duration : CACurrentMediaTime() - gpuStart
                self?.profiler.record(.gpu, seconds: resolved)
            }
        }
        _renderGraph.execute(frame: graphFrame)

        let overlaysStart = CACurrentMediaTime()
        delegate?.renderOverlays(view: view, commandBuffer: overlayCommandBuffer, frameContext: frameContext)
        profiler.record(.overlays, seconds: CACurrentMediaTime() - overlaysStart)
        profiler.record(.render, seconds: CACurrentMediaTime() - renderStart)

        if let scene = delegate?.activeScene() {
            updateSkyIfNeeded(scene: scene)
        }

        let presentStart = CACurrentMediaTime()
        if useCounterSampling {
            profiler.encodeGpuCounterResolve(commandBuffer: overlayCommandBuffer, frameIndex: frameIndex)
            overlayCommandBuffer.addCompletedHandler { [weak self] buffer in
                self?.profiler.processResolvedGpuCounters(frameIndex: frameIndex, frameId: frameId, commandBuffer: buffer)
            }
        }
        overlayCommandBuffer.present(drawable)
        overlayCommandBuffer.commit()
        profiler.record(.present, seconds: CACurrentMediaTime() - presentStart)
        profiler.record(.frame, seconds: CACurrentMediaTime() - frameStart)
    }

    private func buildFrameTime(timestamp: TimeInterval) -> FrameTime {
        let deltaSeconds: Float
        if let last = _lastFrameTimestamp {
            deltaSeconds = Float(timestamp - last)
        } else {
            deltaSeconds = 0.0
        }
        _lastFrameTimestamp = timestamp
        let clampedUnscaled = min(max(deltaSeconds, 0.0), _maxFrameDelta)
        let unscaledDelta = clampedUnscaled
        let delta = clampedUnscaled * _timeScale
        _unscaledTotalTime += unscaledDelta
        _totalTime += delta
        _frameCount &+= 1
        return FrameTime(
            deltaTime: delta,
            unscaledDeltaTime: unscaledDelta,
            timeScale: _timeScale,
            fixedDeltaTime: _fixedDeltaTime,
            frameCount: _frameCount,
            totalTime: _totalTime,
            unscaledTotalTime: _unscaledTotalTime
        )
    }

}
