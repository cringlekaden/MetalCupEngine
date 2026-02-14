/// Renderer.swift
/// Renderer entry point and frame orchestration.
/// Created by Kaden Cringle

import MetalKit
import simd
import QuartzCore
import Foundation

public enum RenderPassType {
    case main
    case picking
    case depthPrepass
}

public final class Renderer: NSObject {
    weak var delegate: RendererDelegate?
    public static var settings = RendererSettings()
    public static let profiler = RendererProfiler()
    public static var currentRenderPass: RenderPassType = .main
    public static var useDepthPrepass: Bool = true

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private var _lastPerfFlags: UInt32 = Renderer.settings.perfFlags
    private let _renderResources = RenderResources()
    private let _renderGraph = RenderGraph()
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
    private var _didLogIBLReport = false

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
        _viewProjections = _views.map { _projection * $0 }
        updateScreenSize(view: mtkView) // builds render targets + base pass desc
        BuiltinAssets.registerIBLTextures(
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            brdfLutSize: _brdfLutSize
        )
        // IBL generation
        if let sky = SceneManager.currentScene.ecs.activeSkyLight()?.1, sky.enabled {
            switch sky.mode {
            case .hdri:
                renderSkyToEnvironmentMap(hdriHandle: sky.hdriHandle, intensity: sky.intensity)
            case .procedural:
                let sunDir = SkySystem.sunDirection(azimuthDegrees: sky.azimuthDegrees, elevationDegrees: sky.elevationDegrees)
                var params = SkyParams()
                params.sunDirection = sunDir
                params.turbidity = max(1.0, sky.turbidity)
                params.intensity = max(0.0, sky.intensity)
                params.skyTint = sky.skyTint
                params.sunAngularRadius = 0.00935
                params.sunIntensity = max(1.0, sky.intensity * 10.0)
                params.sunColor = SIMD3<Float>(1.0, 0.98, 0.92)
                renderProceduralSkyToEnvironmentMap(params: params)
            }
            renderIrradianceMap()
            renderPrefilteredSpecularMap()
        } else {
            BuiltinAssets.registerFallbackIBLTextures()
        }
        renderBRDFLUT()
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

    private func createColorOnlyRenderPassDescriptor(colorTarget: AssetHandle) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: colorTarget)
    }

    private func createCubemapRenderPassDescriptor(target: AssetHandle, face: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: target, slice: face, level: 0)
    }

    private func createMippedCubemapRenderPassDescriptor(target: AssetHandle, face: Int, mip: Int) -> MTLRenderPassDescriptor {
        makeRenderPassDescriptor(colorTarget: target, slice: face, level: mip)
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

    private func validateIBLResources() {
        guard let env = AssetManager.texture(handle: BuiltinAssets.environmentCubemap),
              let irradiance = AssetManager.texture(handle: BuiltinAssets.irradianceCubemap),
              let prefiltered = AssetManager.texture(handle: BuiltinAssets.prefilteredCubemap) else { return }
        assert(env.textureType == .typeCube)
        assert(irradiance.textureType == .typeCube)
        assert(prefiltered.textureType == .typeCube)
        assert(env.mipmapLevelCount >= 1)
        assert(prefiltered.mipmapLevelCount >= 1)
        assert(env.width == env.height)
        assert(prefiltered.width == prefiltered.height)
    }

    private func logIBLReportIfNeeded(config: IBLGenerationConfig, environment: MTLTexture?) {
        guard !_didLogIBLReport else { return }
        _didLogIBLReport = true
        let envSize = environment?.width ?? 0
        let envMips = environment?.mipmapLevelCount ?? 0
        let prefiltered = AssetManager.texture(handle: BuiltinAssets.prefilteredCubemap)
        let prefilteredMips = prefiltered?.mipmapLevelCount ?? 0
        print(
            "IBL_REPORT::preset=\(config.qualityPreset) irradianceSamples=\(config.irradianceSamples) " +
            "prefilterSamples[min:\(config.prefilterSamplesMin),max:\(config.prefilterSamplesMax)] " +
            "fireflyClamp=\(config.fireflyClamp) enabled=\(config.fireflyClampEnabled) " +
            "envSize=\(envSize) envMips=\(envMips) prefilteredMips=\(prefilteredMips) " +
            "sampling=\(config.samplingStrategy)"
        )
    }

    private func renderSkyToEnvironmentMap(hdriHandle: AssetHandle?, intensity: Float) {
        _didLogIBLReport = false
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        guard let envHandle = hdriHandle,
              let envTexture = AssetManager.texture(handle: envHandle) else { return }
        ensureIBLRenderTargets()
        validateIBLResources()
        logIBLReportIfNeeded(config: iblConfig(), environment: envTexture)
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.environmentCubemap, face: face)) else { continue }
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
            cubemapMesh.drawPrimitives(encoder)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder(),
           let env = AssetManager.texture(handle: BuiltinAssets.environmentCubemap) {
            blit.generateMipmaps(for: env)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderIrradianceMap() {
        let config = iblConfig()
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        ensureIBLRenderTargets()
        validateIBLResources()
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.irradianceCubemap, face: face)) else { continue }
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
            encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.environmentCubemap), index: IBLTextureIndex.environment)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
            cubemapMesh.drawPrimitives(encoder)
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderPrefilteredSpecularMap() {
        guard
            let prefiltered = AssetManager.texture(handle: BuiltinAssets.prefilteredCubemap),
            let env = AssetManager.texture(handle: BuiltinAssets.environmentCubemap)
        else { return }
        let config = iblConfig()
        let mipCount = prefiltered.mipmapLevelCount
        let baseSize = prefiltered.width
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        ensureIBLRenderTargets()
        validateIBLResources()
        logIBLReportIfNeeded(config: config, environment: env)
        for mip in 0..<mipCount {
            let roughness = Float(mip) / Float(max(mipCount - 1, 1))
            let mipSize = max(1, baseSize >> mip)
            for face in 0..<6 {
                let passDescriptor = createMippedCubemapRenderPassDescriptor(target: BuiltinAssets.prefilteredCubemap, face: face, mip: mip)
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
                params.envMipCount = Float(mipCount)
                encoder.setFragmentBytes(&params, length: IBLPrefilterParams.stride, index: FragmentBufferIndex.iblParams)
                encoder.setFragmentTexture(env, index: IBLTextureIndex.environment)
                encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
                cubemapMesh.drawPrimitives(encoder)
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

    private func renderBRDFLUT() {
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
        pass.encode(into: encoder, quad: quadMesh)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderProceduralSkyToEnvironmentMap(params: SkyParams) {
        _didLogIBLReport = false
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Procedural Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        ensureIBLRenderTargets()
        validateIBLResources()
        logIBLReportIfNeeded(config: iblConfig(), environment: AssetManager.texture(handle: BuiltinAssets.environmentCubemap))
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.environmentCubemap, face: face)) else { continue }
            encoder.label = "Procedural Sky face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ProceduralSkyCubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            var skyParams = params
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: VertexBufferIndex.cubemapViewProjection)
            encoder.setFragmentBytes(&skyParams, length: SkyParams.stride, index: FragmentBufferIndex.skyParams)
            cubemapMesh.drawPrimitives(encoder)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder(),
           let env = AssetManager.texture(handle: BuiltinAssets.environmentCubemap) {
            blit.generateMipmaps(for: env)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func updateSkyIfNeeded(scene: EngineScene) {
        guard let skyEntry = scene.ecs.activeSkyLight() else { return }
        let entity = skyEntry.0
        let sky = skyEntry.1
        guard sky.enabled else { return }

        let now = CACurrentMediaTime()
        if _skyRebuildInFlight { return }
        if !sky.needsRegenerate { return }
        if sky.realtimeUpdate, (now - sky.lastRegenerateTime) < 0.2 { return }

        var updated = sky
        updated.needsRegenerate = false
        updated.lastRegenerateTime = now
        scene.ecs.add(updated, to: entity)

        let snapshot = updated
        _skyRebuildInFlight = true
        _skyRebuildQueue.async { [weak self] in
            guard let self = self else { return }
            switch snapshot.mode {
            case .hdri:
                self.renderSkyToEnvironmentMap(hdriHandle: snapshot.hdriHandle, intensity: snapshot.intensity)
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
                self.renderProceduralSkyToEnvironmentMap(params: params)
            }

            self.renderIrradianceMap()
            self.renderPrefilteredSpecularMap()

            DispatchQueue.main.async {
                self._skyRebuildInFlight = false
                if let current = SceneManager.currentScene.ecs.activeSkyLight()?.1, current != snapshot {
                    var regen = current
                    regen.needsRegenerate = true
                    if let entity = SceneManager.currentScene.ecs.activeSkyLight()?.0 {
                        SceneManager.currentScene.ecs.add(regen, to: entity)
                    }
                }
            }
        }
    }

    private func ensureIBLRenderTargets() {
        if let env = AssetManager.texture(handle: BuiltinAssets.environmentCubemap),
           env.usage.contains(.renderTarget) {
            return
        }
        BuiltinAssets.registerIBLTextures(
            environmentSize: _environmentSize,
            irradianceSize: _irradianceSize,
            prefilteredSize: _prefilteredSize,
            brdfLutSize: _brdfLutSize
        )
    }

}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    public func updateScreenSize(view: MTKView) {
        applyViewSizes(view: view)
        SceneManager.currentScene.updateAspectRatio()
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


    private func renderToWindow(renderPipelineState: RenderPipelineStateType, view: MTKView, commandBuffer: MTLCommandBuffer) {
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
        pass.encode(into: encoder, quad: quadMesh)
        encoder.endEncoding()
    }

    public func draw(in view: MTKView) {
        let frameStart = CACurrentMediaTime()
        defer { Mouse.BeginFrame() }
        GameTime.UpdateTime(1.0 / Float(view.preferredFramesPerSecond))
        guard let drawable = view.currentDrawable,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0 else { return }
        updateFrameSizingIfNeeded(view: view)
        let updateStart = CACurrentMediaTime()
        delegate?.update()
        Renderer.profiler.record(.update, seconds: CACurrentMediaTime() - updateStart)
        updateSkyIfNeeded(scene: SceneManager.currentScene)
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MetalCup Frame"
        RendererFrameContext.shared.beginFrame()
        let gpuStart = CACurrentMediaTime()
        commandBuffer.addCompletedHandler { _ in
            Renderer.profiler.record(.gpu, seconds: CACurrentMediaTime() - gpuStart)
        }

        let renderStart = CACurrentMediaTime()
        // Scene Pass -> Bloom -> Final Composite -> ImGui overlays
        let graphFrame = RenderGraphFrame(
            view: view,
            commandBuffer: commandBuffer,
            resources: _renderResources,
            delegate: delegate
        )
        _renderGraph.execute(frame: graphFrame)

        if let pickRequest = SceneManager.consumePickRequest(),
           let pickTexture = AssetManager.texture(handle: BuiltinAssets.pickIdRender),
           let readbackBuffer = RendererFrameContext.shared.pickReadbackBuffer() {
            let width = max(1, pickTexture.width)
            let height = max(1, pickTexture.height)
            let clampedX = max(0, min(pickRequest.x, width - 1))
            let clampedY = max(0, min(pickRequest.y, height - 1))
            let origin = MTLOrigin(x: clampedX, y: clampedY, z: 0)
            let size = MTLSize(width: 1, height: 1, depth: 1)
            if let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.label = "Pick Readback Blit"
                blit.copy(from: pickTexture,
                          sourceSlice: 0,
                          sourceLevel: 0,
                          sourceOrigin: origin,
                          sourceSize: size,
                          to: readbackBuffer,
                          destinationOffset: 0,
                          destinationBytesPerRow: MemoryLayout<UInt32>.stride,
                          destinationBytesPerImage: MemoryLayout<UInt32>.stride)
                blit.endEncoding()
            }
            commandBuffer.addCompletedHandler { _ in
                let pointer = readbackBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
                let pickedId = pointer.pointee
                SceneManager.handlePickResult(pickedId)
            }
        }

        let overlaysStart = CACurrentMediaTime()
        delegate?.renderOverlays(view: view, commandBuffer: commandBuffer)
        Renderer.profiler.record(.overlays, seconds: CACurrentMediaTime() - overlaysStart)
        Renderer.profiler.record(.render, seconds: CACurrentMediaTime() - renderStart)
        
        let presentStart = CACurrentMediaTime()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        Renderer.profiler.record(.present, seconds: CACurrentMediaTime() - presentStart)
        Renderer.profiler.record(.frame, seconds: CACurrentMediaTime() - frameStart)
    }
}
