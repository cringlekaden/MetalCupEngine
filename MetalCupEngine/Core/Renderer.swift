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
}

public final class Renderer: NSObject {
    public var delegate: RendererDelegate?
    public var inputAccumulator: InputAccumulator?
    public static var settings = RendererSettings()
    public static let profiler = RendererProfiler()
    public static var currentRenderPass: RenderPassType = .main
    public static var useDepthPrepass: Bool = true
    public static var layerFilterMask: LayerMask = .all
    public static weak var activeRenderer: Renderer?

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private var _lastPerfFlags: UInt32 = Renderer.settings.perfFlags
    private let _renderResources = RenderResources()
    private let _renderGraph = RenderGraph()
    private let _frameContextStorage = RendererFrameContextStorage()
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

    private struct IBLTextureHandles {
        let environment: AssetHandle
        let irradiance: AssetHandle
        let prefiltered: AssetHandle
        let brdf: AssetHandle
    }

    private var _iblHandleSets: [IBLTextureHandles] = []
    private var _activeIBLHandleIndex = 0

    // MARK: - Static sizes

    public static var ScreenSize = SIMD2<Float>(0, 0)
    public static var DrawableSize = SIMD2<Float>(0, 0)
    public static var ViewportSize = SIMD2<Float>(0, 0)
    public static var AspectRatio: Float {
        let size = (ViewportSize.x > 0 && ViewportSize.y > 0) ? ViewportSize : ScreenSize
        return size.y.isZero ? 1 : size.x / size.y
    }

    // MARK: - Init

    init(_ mtkView: MTKView) {
        super.init()
        Renderer.activeRenderer = self
        _viewProjections = _views.map { _projection * $0 }
        updateScreenSize(view: mtkView) // builds render targets + base pass desc
        BuiltinAssets.registerIBLTextures(
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            brdfLutSize: _brdfLutSize
        )
        BuiltinAssets.registerFallbackIBLTextures()
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
        pass.colorAttachments[0].texture = AssetManager.texture(handle: colorTarget)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        pass.colorAttachments[0].level = level
        if let slice {
            pass.colorAttachments[0].slice = slice
        }
        if let depthTarget {
            pass.depthAttachment.texture = AssetManager.texture(handle: depthTarget)
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
        return IBLQualityPreset(rawValue: Renderer.settings.iblQualityPreset) ?? .high
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
            return max(Renderer.settings.iblSampleMultiplier, 0.1)
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
            fireflyClamp: Renderer.settings.iblFireflyClamp,
            fireflyClampEnabled: Renderer.settings.iblFireflyClampEnabled != 0,
            samplingStrategy: "cosine + GGX importance sampling"
        )
    }

    private func iblMipCount(for size: Int) -> Int {
        guard size > 0 else { return 1 }
        return Int(floor(log2(Double(size)))) + 1
    }

    private func makeCubemapTexture(size: Int, mipmapped: Bool, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            size: size,
            mipmapped: mipmapped
        )
        if mipmapped {
            descriptor.mipmapLevelCount = iblMipCount(for: size)
        }
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = Engine.Device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }

    private func ensureIBLTextureSet(handles: IBLTextureHandles) {
        if AssetManager.texture(handle: handles.environment) == nil,
           let env = makeCubemapTexture(size: _environmentSize, mipmapped: true, label: "IBL.EnvironmentCubemap.Next") {
            AssetManager.registerRuntimeTexture(handle: handles.environment, texture: env)
        }
        if AssetManager.texture(handle: handles.irradiance) == nil,
           let irr = makeCubemapTexture(size: _irradianceSize, mipmapped: false, label: "IBL.IrradianceCubemap.Next") {
            AssetManager.registerRuntimeTexture(handle: handles.irradiance, texture: irr)
        }
        if AssetManager.texture(handle: handles.prefiltered) == nil,
           let pre = makeCubemapTexture(size: _prefilteredSize, mipmapped: true, label: "IBL.PrefilteredCubemap.Next") {
            AssetManager.registerRuntimeTexture(handle: handles.prefiltered, texture: pre)
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
        return lhs.mode == rhs.mode
            && lhs.enabled == rhs.enabled
            && lhs.intensity == rhs.intensity
            && lhs.skyTint == rhs.skyTint
            && lhs.turbidity == rhs.turbidity
            && lhs.azimuthDegrees == rhs.azimuthDegrees
            && lhs.elevationDegrees == rhs.elevationDegrees
            && lhs.hdriHandle == rhs.hdriHandle
            && lhs.realtimeUpdate == rhs.realtimeUpdate
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
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        guard let envHandle = hdriHandle,
              let envTexture = AssetManager.texture(handle: envHandle) else { return }
        validateIBLResources(environment: targetEnvironment, irradiance: nil, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetEnvironment, face: face)) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Cubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            var skyIntensity = intensity
            encoder.setFragmentBytes(&skyIntensity, length: MemoryLayout<Float>.stride, index: FragmentBufferIndex.skyIntensity)
            encoder.setFragmentTexture(envTexture, index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
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
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        validateIBLResources(environment: sourceEnvironment, irradiance: targetIrradiance, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetIrradiance, face: face)) else { continue }
            encoder.label = "Irradiance Cubemap face: \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.IrradianceMap])
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
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
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
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
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
                encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.PrefilteredMap])
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
                encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
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
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render BRDF LUT"
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.brdfLut)) else { return }
        guard let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        let pass = FullscreenPass(
            pipeline: .BRDF,
            label: "BRDF LUT Encoder",
            sampler: nil,
            texture0: nil,
            texture1: nil,
            settings: nil
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frameContext)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderProceduralSkyToEnvironmentMap(params: SkyParams, targetEnvironment: MTLTexture, frameContext: RendererFrameContext) {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Procedural Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        validateIBLResources(environment: targetEnvironment, irradiance: nil, prefiltered: nil)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(texture: targetEnvironment, face: face)) else { continue }
            encoder.label = "Procedural Sky face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ProceduralSkyCubemap])
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
                updated.needsRegenerate = true
                scene.ecs.add(updated, to: entity)
                sky = updated
            }
        }

        let hdriLoaded = sky.mode != .hdri || (sky.hdriHandle.flatMap { AssetManager.texture(handle: $0) } != nil)
        if sky.mode == .hdri, !hdriLoaded { return }

        let environment = sky.iblEnvironmentHandle.flatMap { AssetManager.texture(handle: $0) }
        let irradiance = sky.iblIrradianceHandle.flatMap { AssetManager.texture(handle: $0) }
        let prefiltered = sky.iblPrefilteredHandle.flatMap { AssetManager.texture(handle: $0) }
        let isFallbackIBL = (environment?.width ?? 0) <= 1
            || (irradiance?.width ?? 0) <= 1
            || (prefiltered?.width ?? 0) <= 1
        if isFallbackIBL && !sky.needsRegenerate {
            sky.needsRegenerate = true
            scene.ecs.add(sky, to: entity)
        }

        let now = CACurrentMediaTime()
        if _skyRebuildInFlight { return }
        if !sky.needsRegenerate { return }
        if sky.realtimeUpdate, (now - sky.lastRegenerateTime) < 0.2 { return }

        var updated = sky
        updated.lastRegenerateTime = now
        scene.ecs.add(updated, to: entity)

        let snapshot = updated
        let nextIndex = (_activeIBLHandleIndex + 1) % _iblHandleSets.count
        let nextHandles = _iblHandleSets[nextIndex]
        _skyRebuildInFlight = true
        _skyRebuildQueue.async { [weak self] in
            guard let self = self else { return }
            let frameContext = RendererFrameContextStorage().beginFrame()
            self.ensureIBLTextureSet(handles: nextHandles)
            guard let targetEnv = AssetManager.texture(handle: nextHandles.environment),
                  let targetIrr = AssetManager.texture(handle: nextHandles.irradiance),
                  let targetPre = AssetManager.texture(handle: nextHandles.prefiltered) else {
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
                let sunDir = SkySystem.sunDirection(azimuthDegrees: snapshot.azimuthDegrees, elevationDegrees: snapshot.elevationDegrees)
                var params = SkyParams()
                params.sunDirection = sunDir
                params.turbidity = max(1.0, snapshot.turbidity)
                params.intensity = max(0.0, snapshot.intensity)
                params.skyTint = snapshot.skyTint
                params.sunAngularRadius = 0.00935
                params.sunIntensity = max(1.0, snapshot.intensity * 10.0)
                params.sunColor = SIMD3<Float>(1.0, 0.98, 0.92)
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
                    regen.needsRegenerate = false
                } else {
                    regen.needsRegenerate = true
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
        Renderer.ScreenSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        Renderer.DrawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if Renderer.ViewportSize.x.isZero || Renderer.ViewportSize.y.isZero {
            Renderer.ViewportSize = Renderer.ScreenSize
        }
    }

    private func updateFrameSizingIfNeeded(view: MTKView) {
        if _lastPerfFlags != Renderer.settings.perfFlags {
            _lastPerfFlags = Renderer.settings.perfFlags
            updateScreenSize(view: view)
        }
        let currentSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if Renderer.DrawableSize != currentSize
            || !_renderResources.isValid(for: view.drawableSize) {
            Renderer.DrawableSize = currentSize
            updateScreenSize(view: view)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateScreenSize(view: view)
    }


    private func renderToWindow(renderPipelineState: RenderPipelineStateType, view: MTKView, commandBuffer: MTLCommandBuffer, frameContext: RendererFrameContext) {
        guard let rpd = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        guard let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        let pass = FullscreenPass(
            pipeline: renderPipelineState,
            label: "Final Composite -> Drawable",
            sampler: .LinearClampToZero,
            texture0: AssetManager.texture(handle: BuiltinAssets.baseColorRender),
            texture1: AssetManager.texture(handle: BuiltinAssets.bloomPing),
            settings: Renderer.settings
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frameContext)
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
        Renderer.profiler.record(.update, seconds: CACurrentMediaTime() - updateStart)
        if let scene = delegate?.activeScene() {
            updateSkyIfNeeded(scene: scene)
        }
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MetalCup Frame"
        let frameContext = _frameContextStorage.beginFrame()
        let gpuStart = CACurrentMediaTime()
        commandBuffer.addCompletedHandler { _ in
            Renderer.profiler.record(.gpu, seconds: CACurrentMediaTime() - gpuStart)
        }

        let renderStart = CACurrentMediaTime()
        // Scene Pass -> Bloom -> Final Composite -> ImGui overlays
        let scene = delegate?.activeScene()
        let sceneView = delegate?.buildSceneView() ?? SceneView(viewportSize: Renderer.ViewportSize)
        let graphFrame = RenderGraphFrame(
            view: view,
            sceneView: sceneView,
            commandBuffer: commandBuffer,
            resources: _renderResources,
            delegate: delegate,
            frameContext: frameContext
        )
        _renderGraph.execute(frame: graphFrame)

        if let pickRequest = PickingSystem.consumeRequest(),
           let pickTexture = AssetManager.texture(handle: BuiltinAssets.pickIdRender),
           let readbackBuffer = frameContext.pickReadbackBuffer() {
            PickingSystem.enqueueReadback(
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
        Renderer.profiler.record(.overlays, seconds: CACurrentMediaTime() - overlaysStart)
        Renderer.profiler.record(.render, seconds: CACurrentMediaTime() - renderStart)
        
        let presentStart = CACurrentMediaTime()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        Renderer.profiler.record(.present, seconds: CACurrentMediaTime() - presentStart)
        Renderer.profiler.record(.frame, seconds: CACurrentMediaTime() - frameStart)
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
