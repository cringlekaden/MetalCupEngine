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
    public var useDepthPrepass: Bool = false
    public var layerFilterMask: LayerMask = .all

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private var _lastPerfFlags: UInt32 = 0
    private let _renderResources: RenderResources
    private let _renderGraph = RenderGraph()
    private let _frameContextStorage: RendererFrameContextStorage
    let shadowRenderer: ShadowRenderer
    private var _lastFrameTimestamp: TimeInterval?
    private var _frameCount: UInt64 = 0
    private var _totalTime: Float = 0.0
    private var _unscaledTotalTime: Float = 0.0
    private var _timeScale: Float = 1.0
    private var _fixedDeltaTime: Float = 1.0 / 60.0
    private let _maxFrameDelta: Float = 0.25
    // MARK: - Views for capturing cubemap faces
    private let _views: [float4x4] = [
        float4x4(lookAt: .zero, center: [ 1, 0, 0], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [-1, 0, 0], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [ 0,-1, 0], up: [0, 0,-1]),
        float4x4(lookAt: .zero, center: [ 0, 1, 0], up: [0, 0, 1]),
        float4x4(lookAt: .zero, center: [ 0, 0, 1], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [ 0, 0,-1], up: [0,-1, 0])
    ]
    private var _viewProjections: [float4x4]!
    private let _environmentSize = 2048
    private let _irradianceSize = 64
    private let _prefilteredSize = 1024
    private let _brdfLutSize = 512
    private let _skyRebuildQueue = DispatchQueue(label: "MetalCup.Renderer.SkyRebuild", qos: .userInitiated)
    private var _skyRebuildInFlight = false
    private var _skyLiveUpdateInFlight = false
    private var _lastSkyLiveSnapshot: SkyLightComponent?
    private var _lastSkyLiveUpdateTime: Double = 0.0

    private struct IBLTextureHandles {
        let environment: AssetHandle
        let irradiance: AssetHandle
        let prefiltered: AssetHandle
        let brdf: AssetHandle
    }

    private var _iblHandleSets: [IBLTextureHandles] = []
    private var _activeIBLHandleIndex = 0

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
        self.shadowRenderer = ShadowRenderer(engineContext: engineContext)
        super.init()
        self._lastPerfFlags = settings.perfFlags
        _viewProjections = _views.map { _projection * $0 }
        updateScreenSize(view: mtkView) // builds render targets + base pass desc
        BuiltinAssets.registerIBLTextures(
            assetManager: engineContext.assets,
            preferences: engineContext.preferences,
            device: engineContext.device,
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            brdfLutSize: _brdfLutSize
        )
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

    private func iblConfig() -> IBLGenerationConfig {
        let preset = iblQualityPreset()
        let multiplier = iblSampleMultiplier(for: preset)
        let irradianceSamples = UInt32(max(512.0, min(8192.0, multiplier * 2048.0)))
        let prefilterBase = max(128.0, min(4096.0, multiplier * 1024.0))
        let minSamples = UInt32(max(128.0, min(1024.0, prefilterBase * 0.25)))
        let maxSamples = UInt32(max(512.0, min(4096.0, prefilterBase)))
        return IBLGenerationConfig(
            qualityPreset: preset,
            irradianceSamples: irradianceSamples,
            prefilterSamplesMin: minSamples,
            prefilterSamplesMax: maxSamples,
            fireflyClamp: settings.iblFireflyClamp,
            fireflyClampEnabled: settings.iblFireflyClampEnabled != 0,
            samplingStrategy: "cosine + GGX importance sampling"
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
        if engineContext.assets.texture(handle: handles.environment) == nil,
           let env = makeCubemapTexture(size: _environmentSize, mipmapped: true, label: "IBL.EnvironmentCubemap.Next") {
            engineContext.assets.registerRuntimeTexture(handle: handles.environment, texture: env)
        }
        if engineContext.assets.texture(handle: handles.irradiance) == nil,
           let irr = makeCubemapTexture(size: _irradianceSize, mipmapped: false, label: "IBL.IrradianceCubemap.Next") {
            engineContext.assets.registerRuntimeTexture(handle: handles.irradiance, texture: irr)
        }
        if engineContext.assets.texture(handle: handles.prefiltered) == nil,
           let pre = makeCubemapTexture(size: _prefilteredSize, mipmapped: true, label: "IBL.PrefilteredCubemap.Next") {
            engineContext.assets.registerRuntimeTexture(handle: handles.prefiltered, texture: pre)
        }
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

    private func renderSkyToEnvironmentMap(hdriHandle: AssetHandle?, intensity: Float, targetEnvironment: MTLTexture, frameContext: RendererFrameContext) {
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Sky To Cubemap"
        guard let cubemapMesh = engineContext.assets.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        guard let envHandle = hdriHandle,
              let envTexture = engineContext.assets.texture(handle: envHandle) else { return }
        validateIBLResources(environment: targetEnvironment, irradiance: nil, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetEnvironment, face: face)) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.Cubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            var skyIntensity = intensity
            encoder.setFragmentBytes(&skyIntensity, length: MemoryLayout<Float>.stride, index: FragmentBufferIndex.skyIntensity)
            encoder.setFragmentTexture(envTexture, index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
            cubemapMesh.drawPrimitives(encoder, frameContext: frameContext)
            encoder.endEncoding()
        }
        if targetEnvironment.mipmapLevelCount > 1,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: targetEnvironment)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderIrradianceMap(sourceEnvironment: MTLTexture, targetIrradiance: MTLTexture, frameContext: RendererFrameContext) {
        let config = iblConfig()
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        guard let cubemapMesh = engineContext.assets.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        validateIBLResources(environment: sourceEnvironment, irradiance: targetIrradiance, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetIrradiance, face: face)) else { continue }
            encoder.label = "Irradiance Cubemap face: \(face)"
            encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.IrradianceMap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            var params = IBLIrradianceParams()
            params.sampleCount = config.irradianceSamples
            params.fireflyClamp = config.fireflyClamp
            params.fireflyClampEnabled = config.fireflyClampEnabled ? 1 : 0
            encoder.setFragmentBytes(&params, length: IBLIrradianceParams.stride, index: FragmentBufferIndex.iblParams)
            encoder.setFragmentTexture(sourceEnvironment, index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
            cubemapMesh.drawPrimitives(encoder, frameContext: frameContext)
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderPrefilteredSpecularMap(sourceEnvironment: MTLTexture, targetPrefiltered: MTLTexture, frameContext: RendererFrameContext) {
        let config = iblConfig()
        let mipCount = targetPrefiltered.mipmapLevelCount
        let baseSize = targetPrefiltered.width
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        guard let cubemapMesh = engineContext.assets.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
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
                encoder.setCullMode(.front)
                encoder.setFrontFacing(.clockwise)
                encoder.setViewport(MTLViewport(
                    originX: 0, originY: 0,
                    width: Double(mipSize), height: Double(mipSize),
                    znear: 0, zfar: 1
                ))
                var vp = _viewProjections[face]
                encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
                var params = IBLPrefilterParams()
                params.roughness = roughness
                params.sampleCount = prefilterSampleCount(for: roughness, config: config)
                params.fireflyClamp = config.fireflyClamp
                params.fireflyClampEnabled = config.fireflyClampEnabled ? 1 : 0
                params.envMipCount = Float(sourceEnvironment.mipmapLevelCount)
                encoder.setFragmentBytes(&params, length: IBLPrefilterParams.stride, index: FragmentBufferIndex.iblParams)
                encoder.setFragmentTexture(sourceEnvironment, index: IBLTextureIndex.environment)
                encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
                cubemapMesh.drawPrimitives(encoder, frameContext: frameContext)
                encoder.endEncoding()
            }
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func prefilterSampleCount(for roughness: Float, config: IBLGenerationConfig) -> UInt32 {
        let glossyFactor = pow(max(1.0 - roughness, 0.0), 2.0)
        let range = max(Float(config.prefilterSamplesMax - config.prefilterSamplesMin), 1.0)
        let samples = Float(config.prefilterSamplesMin) + range * glossyFactor
        return UInt32(max(Float(config.prefilterSamplesMin), min(Float(config.prefilterSamplesMax), samples)))
    }

    private func renderBRDFLUT(frameContext: RendererFrameContext) {
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render BRDF LUT"
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.brdfLut)) else { return }
        guard let quadMesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        let pass = FullscreenPass(
            pipeline: .BRDF,
            label: "BRDF LUT Encoder",
            sampler: .LinearClampToZero,
            useSampler: false,
            texture0: nil,
            useTexture0: false,
            texture1: nil,
            useTexture1: false,
            outlineMask: nil,
            useOutlineMask: false,
            depth: nil,
            useDepth: false,
            grid: nil,
            useGrid: false,
            settings: nil
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frameContext, graphics: engineContext.graphics)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderProceduralSkyToEnvironmentMap(params: SkyParams, targetEnvironment: MTLTexture, frameContext: RendererFrameContext) {
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Procedural Sky To Cubemap"
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
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func skyParams(from sky: SkyLightComponent) -> SkyParams {
        var params = SkyParams()
        params.sunDirection = SkySystem.sunDirection(azimuthDegrees: sky.azimuthDegrees, elevationDegrees: -sky.elevationDegrees)
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
            scene.ecs.add(sky, to: entity)
        }

        let now = CACurrentMediaTime()
        if !sky.needsRebuild {
            let paramsChanged = _lastSkyLiveSnapshot.map { !SkySystem.liveSkyParamsMatch($0, sky) } ?? true
            let wantsCloudMotion = sky.cloudsEnabled && abs(sky.cloudsSpeed) > 0.0001
            let needsCloudTick = wantsCloudMotion && (now - _lastSkyLiveUpdateTime) > 0.25
            let shouldUpdateLive = paramsChanged || needsCloudTick
            if shouldUpdateLive && !_skyLiveUpdateInFlight && !_skyRebuildInFlight {
                let liveSnapshot = sky
                _skyLiveUpdateInFlight = true
                _skyRebuildQueue.async { [weak self] in
                    guard let self = self else { return }
                    guard let targetEnv = self.engineContext.assets.texture(handle: activeHandles.environment) else {
                        DispatchQueue.main.async { [weak self] in
                            self?._skyLiveUpdateInFlight = false
                        }
                        return
                    }
                    let frameContext = RendererFrameContextStorage(engineContext: self.engineContext).beginFrame()
                    switch liveSnapshot.mode {
                    case .hdri:
                        if liveSnapshot.hdriHandle != nil {
                            self.renderSkyToEnvironmentMap(
                                hdriHandle: liveSnapshot.hdriHandle,
                                intensity: liveSnapshot.intensity,
                                targetEnvironment: targetEnv,
                                frameContext: frameContext
                            )
                        }
                    case .procedural:
                        let params = self.skyParams(from: liveSnapshot)
                        self.renderProceduralSkyToEnvironmentMap(params: params, targetEnvironment: targetEnv, frameContext: frameContext)
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?._skyLiveUpdateInFlight = false
                        self?._lastSkyLiveSnapshot = liveSnapshot
                        self?._lastSkyLiveUpdateTime = now
                    }
                }
            }
        }
        if _skyRebuildInFlight { return }
        if !sky.needsRebuild { return }
        let allowRebuild = sky.realtimeUpdate || sky.rebuildRequested
        if !allowRebuild { return }
        if sky.realtimeUpdate && !sky.rebuildRequested && (now - sky.lastRebuildTime) < 0.2 { return }

        var updated = sky
        updated.lastRebuildTime = now
        updated.rebuildRequested = false
        scene.ecs.add(updated, to: entity)

        let snapshot = updated
        let nextIndex = (_activeIBLHandleIndex + 1) % _iblHandleSets.count
        let nextHandles = _iblHandleSets[nextIndex]
        _skyRebuildInFlight = true
        _skyRebuildQueue.async { [weak self] in
            guard let self = self else { return }
            let frameContext = RendererFrameContextStorage(engineContext: self.engineContext).beginFrame()
            self.ensureIBLTextureSet(handles: nextHandles)
            guard let targetEnv = self.engineContext.assets.texture(handle: nextHandles.environment),
                  let targetIrr = self.engineContext.assets.texture(handle: nextHandles.irradiance),
                  let targetPre = self.engineContext.assets.texture(handle: nextHandles.prefiltered) else {
                DispatchQueue.main.async { [weak self] in
                    self?._skyRebuildInFlight = false
                }
                return
            }
            switch snapshot.mode {
            case .hdri:
                self.renderSkyToEnvironmentMap(
                    hdriHandle: snapshot.hdriHandle,
                    intensity: snapshot.intensity,
                    targetEnvironment: targetEnv,
                    frameContext: frameContext
                )
            case .procedural:
                let params = self.skyParams(from: snapshot)
                self.renderProceduralSkyToEnvironmentMap(params: params, targetEnvironment: targetEnv, frameContext: frameContext)
            }

            self.renderIrradianceMap(sourceEnvironment: targetEnv, targetIrradiance: targetIrr, frameContext: frameContext)
            self.renderPrefilteredSpecularMap(sourceEnvironment: targetEnv, targetPrefiltered: targetPre, frameContext: frameContext)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self._skyRebuildInFlight = false
                guard let currentScene = self.delegate?.activeScene(),
                      let currentEntry = currentScene.ecs.activeSkyLight() else { return }
                let (currentEntity, currentSky) = currentEntry
                var regen = currentSky
                if self.skySettingsMatch(currentSky, snapshot) {
                    self._activeIBLHandleIndex = nextIndex
                    regen.iblEnvironmentHandle = nextHandles.environment
                    regen.iblIrradianceHandle = nextHandles.irradiance
                    regen.iblPrefilteredHandle = nextHandles.prefiltered
                    regen.iblBrdfHandle = nextHandles.brdf
                    regen.needsRebuild = false
                    self._lastSkyLiveSnapshot = regen
                } else {
                    regen.needsRebuild = true
                }
                currentScene.ecs.add(regen, to: currentEntity)
            }
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
        guard let commandBuffer = engineContext.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MetalCup Frame"
        let frameContext = _frameContextStorage.beginFrame()
        _frameContextStorage.updateRendererState(
            settings: settings,
            currentRenderPass: currentRenderPass,
            useDepthPrepass: useDepthPrepass,
            layerFilterMask: layerFilterMask
        )
        let gpuStart = CACurrentMediaTime()
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.profiler.record(.gpu, seconds: CACurrentMediaTime() - gpuStart)
        }

        let renderStart = CACurrentMediaTime()
        // Scene Pass -> Bloom -> Final Composite -> ImGui overlays
        let sceneView = delegate?.buildSceneView(renderer: self) ?? SceneView(viewportSize: viewportSize)
        let graphFrame = RenderGraphFrame(
            renderer: self,
            engineContext: engineContext,
            view: view,
            sceneView: sceneView,
            commandBuffer: commandBuffer,
            resources: _renderResources,
            delegate: delegate,
            frameContext: frameContext,
            profiler: profiler
        )
        _renderGraph.execute(frame: graphFrame)

        if let pickRequest = engineContext.pickingSystem.consumeRequest(),
           let pickTexture = engineContext.assets.texture(handle: BuiltinAssets.pickIdRender),
           let readbackBuffer = frameContext.pickReadbackBuffer() {
            engineContext.pickingSystem.enqueueReadback(
                request: pickRequest,
                pickTexture: pickTexture,
                readbackBuffer: readbackBuffer,
                commandBuffer: commandBuffer
            ) { pickedId, mask in
                self.delegate?.handlePickResult(PickResult(pickedId: pickedId, mask: mask))
            }
        }

        let overlaysStart = CACurrentMediaTime()
        delegate?.renderOverlays(view: view, commandBuffer: commandBuffer, frameContext: frameContext)
        profiler.record(.overlays, seconds: CACurrentMediaTime() - overlaysStart)
        profiler.record(.render, seconds: CACurrentMediaTime() - renderStart)

        if let scene = delegate?.activeScene() {
            updateSkyIfNeeded(scene: scene)
        }

        let presentStart = CACurrentMediaTime()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
