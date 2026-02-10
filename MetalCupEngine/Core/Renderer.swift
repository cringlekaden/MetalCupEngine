//
//  Renderer.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit
import simd
import QuartzCore
import Foundation

public final class Renderer: NSObject {
    weak var delegate: RendererDelegate?
    public static var settings = RendererSettings()
    public static let profiler = RendererProfiler()

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private var _lastPerfFlags: UInt32 = Renderer.settings.perfFlags
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

    // MARK: - Render target rebuild

    private func rebuildRenderTargets() {
        // Base HDR scene color
        let baseColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            width: Int(Renderer.DrawableSize.x),
            height: Int(Renderer.DrawableSize.y),
            mipmapped: false
        )
        baseColorDesc.usage = [.renderTarget, .shaderRead]
        baseColorDesc.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: baseColorDesc) {
            AssetManager.registerRuntimeTexture(handle: BuiltinAssets.baseColorRender, texture: texture)
        }
        // Final LDR scene color
        let finalColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.defaultColorPixelFormat,
            width: Int(Renderer.DrawableSize.x),
            height: Int(Renderer.DrawableSize.y),
            mipmapped: false
        )
        finalColorDesc.usage = [.renderTarget, .shaderRead]
        finalColorDesc.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: finalColorDesc) {
            AssetManager.registerRuntimeTexture(handle: BuiltinAssets.finalColorRender, texture: texture)
        }
        // Base depth
        let baseDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.defaultDepthPixelFormat,
            width: Int(Renderer.DrawableSize.x),
            height: Int(Renderer.DrawableSize.y),
            mipmapped: false
        )
        baseDepthDesc.usage = [.renderTarget, .shaderRead]
        baseDepthDesc.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: baseDepthDesc) {
            AssetManager.registerRuntimeTexture(handle: BuiltinAssets.baseDepthRender, texture: texture)
        }
        // Bloom half-res ping/pong
        let useHalfResBloom = Renderer.settings.hasPerfFlag(.halfResBloom)
        let divisor = useHalfResBloom ? 2 : 1
        let bw = max(1, Int(Renderer.DrawableSize.x) / divisor)
        let bh = max(1, Int(Renderer.DrawableSize.y) / divisor)
        let bloomDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            width: bw,
            height: bh,
            mipmapped: true
        )
        bloomDesc.usage = [.renderTarget, .shaderRead]
        bloomDesc.storageMode = .private
        if let ping = Engine.Device.makeTexture(descriptor: bloomDesc) {
            AssetManager.registerRuntimeTexture(handle: BuiltinAssets.bloomPing, texture: ping)
        }
        if let pong = Engine.Device.makeTexture(descriptor: bloomDesc) {
            AssetManager.registerRuntimeTexture(handle: BuiltinAssets.bloomPong, texture: pong)
        }
        Renderer.settings.bloomTexelSize = SIMD2<Float>(1.0 / Float(bw), 1.0 / Float(bh))
    }

    // MARK: - Render pass descriptor helpers
    private func createColorAndDepthRenderPassDescriptor(colorTarget: AssetHandle, depthTarget: AssetHandle) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = AssetManager.texture(handle: colorTarget)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        pass.depthAttachment.texture = AssetManager.texture(handle: depthTarget)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        return pass
    }

    private func createColorOnlyRenderPassDescriptor(colorTarget: AssetHandle) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = AssetManager.texture(handle: colorTarget)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createColorOnlyRenderPassDescriptor(colorTarget: AssetHandle, level: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = AssetManager.texture(handle: colorTarget)
        pass.colorAttachments[0].level = level
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createCubemapRenderPassDescriptor(target: AssetHandle, face: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = AssetManager.texture(handle: target)
        pass.colorAttachments[0].slice = face
        pass.colorAttachments[0].level = 0
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createMippedCubemapRenderPassDescriptor(target: AssetHandle, face: Int, mip: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = AssetManager.texture(handle: target)
        pass.colorAttachments[0].slice = face
        pass.colorAttachments[0].level = mip
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    // MARK: - IBL generation

    private func renderSkyToEnvironmentMap(hdriHandle: AssetHandle?, intensity: Float) {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        guard let envHandle = hdriHandle,
              let envTexture = AssetManager.texture(handle: envHandle) else { return }
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.environmentCubemap, face: face)) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Cubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            var skyIntensity = intensity
            encoder.setFragmentBytes(&skyIntensity, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentTexture(envTexture, index: 0)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
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
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.irradianceCubemap, face: face)) else { continue }
            encoder.label = "Irradiance Cubemap face: \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.IrradianceMap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.environmentCubemap), index: 0)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
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
        let mipCount = prefiltered.mipmapLevelCount
        let baseSize = prefiltered.width
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
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
                var r = roughness
                encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
                encoder.setFragmentBytes(&r, length: MemoryLayout<Float>.stride, index: 0)
                encoder.setFragmentTexture(env, index: 0)
                encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
                cubemapMesh.drawPrimitives(encoder)
                encoder.endEncoding()
            }
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderBRDFLUT() {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render BRDF LUT"
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.brdfLut)) else { return }
        encoder.label = "BRDF LUT Encoder"
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.BRDF])
        encoder.setCullMode(.none)
        if let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh) {
            quadMesh.drawPrimitives(encoder)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderProceduralSkyToEnvironmentMap(params: SkyParams) {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Procedural Sky To Cubemap"
        guard let cubemapMesh = AssetManager.mesh(handle: BuiltinAssets.cubemapMesh) else { return }
        for face in 0..<6 {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createCubemapRenderPassDescriptor(target: BuiltinAssets.environmentCubemap, face: face)) else { continue }
            encoder.label = "Procedural Sky face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ProceduralSkyCubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            var skyParams = params
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            encoder.setFragmentBytes(&skyParams, length: SkyParams.stride, index: 0)
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

    // MARK: - Bloom (multi-scale)

    private func renderBloom(commandBuffer: MTLCommandBuffer) {
        let settings = Renderer.settings
        if settings.bloomEnabled == 0 { return }
        guard
            let sceneTex = AssetManager.texture(handle: BuiltinAssets.baseColorRender),
            let ping = AssetManager.texture(handle: BuiltinAssets.bloomPing),
            let pong = AssetManager.texture(handle: BuiltinAssets.bloomPong),
            let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh)
        else { return }

        let maxBloomMips = max(1, Int(settings.bloomMaxMips))
        let mipCount = min(maxBloomMips, ping.mipmapLevelCount)
        if mipCount == 0 { return }

        func mipSize(_ texture: MTLTexture, _ mip: Int) -> SIMD2<Float> {
            let w = max(1, texture.width >> mip)
            let h = max(1, texture.height >> mip)
            return SIMD2<Float>(Float(w), Float(h))
        }

        func setViewport(_ encoder: MTLRenderCommandEncoder, _ size: SIMD2<Float>) {
            encoder.setViewport(MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(size.x),
                height: Double(size.y),
                znear: 0,
                zfar: 1
            ))
        }

        // Pass 1: Extract bright -> ping mip 0
        let extractStart = CACurrentMediaTime()
        do {
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.bloomPing, level: 0)) else { return }
            enc.label = "Bloom Extract"
            enc.pushDebugGroup("Bloom Extract")
            enc.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomExtract])
            enc.setCullMode(.none)
            enc.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
            enc.setFragmentTexture(sceneTex, index: 0)
            var params = settings
            let size0 = mipSize(ping, 0)
            params.bloomTexelSize = SIMD2<Float>(1.0 / size0.x, 1.0 / size0.y)
            params.bloomMipLevel = 0
            enc.setFragmentBytes(&params, length: RendererSettings.stride, index: 0)
            setViewport(enc, size0)
            quadMesh.drawPrimitives(enc)
            enc.popDebugGroup()
            enc.endEncoding()
        }
        Renderer.profiler.record(.bloomExtract, seconds: CACurrentMediaTime() - extractStart)

        let passes = max(1, Int(settings.blurPasses))

        var blurTotal: Double = 0
        var downsampleTotal: Double = 0
        func blurMip(_ mip: Int) {
            let size = mipSize(ping, mip)
            var params = settings
            params.bloomTexelSize = SIMD2<Float>(1.0 / size.x, 1.0 / size.y)
            params.bloomMipLevel = Float(mip)

            for i in 0..<passes {
                let blurStart = CACurrentMediaTime()
                // Horizontal: ping -> pong
                guard let encH = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.bloomPong, level: mip)) else { return }
                encH.label = "Bloom Blur H \(mip) \(i)"
                encH.pushDebugGroup("Bloom Blur H")
                encH.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomBlurH])
                encH.setCullMode(.none)
                encH.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
                encH.setFragmentTexture(ping, index: 0)
                encH.setFragmentBytes(&params, length: RendererSettings.stride, index: 0)
                setViewport(encH, size)
                quadMesh.drawPrimitives(encH)
                encH.popDebugGroup()
                encH.endEncoding()

                // Vertical: pong -> ping
                guard let encV = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.bloomPing, level: mip)) else { return }
                encV.label = "Bloom Blur V \(mip) \(i)"
                encV.pushDebugGroup("Bloom Blur V")
                encV.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomBlurV])
                encV.setCullMode(.none)
                encV.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
                encV.setFragmentTexture(pong, index: 0)
                encV.setFragmentBytes(&params, length: RendererSettings.stride, index: 0)
                setViewport(encV, size)
                quadMesh.drawPrimitives(encV)
                encV.popDebugGroup()
                encV.endEncoding()
                blurTotal += CACurrentMediaTime() - blurStart
            }
        }

        // Blur mip 0
        blurMip(0)

        // Downsample + blur chain
        if mipCount > 1 {
            for mip in 1..<mipCount {
                let prevSize = mipSize(ping, mip - 1)
                let size = mipSize(ping, mip)
                var params = settings
                params.bloomTexelSize = SIMD2<Float>(1.0 / prevSize.x, 1.0 / prevSize.y)
                params.bloomMipLevel = Float(mip - 1)

                let downsampleStart = CACurrentMediaTime()
                guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: BuiltinAssets.bloomPing, level: mip)) else { return }
                enc.label = "Bloom Downsample \(mip)"
                enc.pushDebugGroup("Bloom Downsample")
                enc.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomDownsample])
                enc.setCullMode(.none)
                enc.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
                enc.setFragmentTexture(ping, index: 0)
                enc.setFragmentBytes(&params, length: RendererSettings.stride, index: 0)
                setViewport(enc, size)
                quadMesh.drawPrimitives(enc)
                enc.popDebugGroup()
                enc.endEncoding()
                downsampleTotal += CACurrentMediaTime() - downsampleStart

                blurMip(mip)
            }
        }
        if downsampleTotal > 0 {
            Renderer.profiler.record(.bloomDownsample, seconds: downsampleTotal)
        }
        if blurTotal > 0 {
            Renderer.profiler.record(.bloomBlur, seconds: blurTotal)
        }
    }
}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    public func updateScreenSize(view: MTKView) {
        Renderer.ScreenSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        Renderer.DrawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if Renderer.ViewportSize.x.isZero || Renderer.ViewportSize.y.isZero {
            Renderer.ViewportSize = Renderer.ScreenSize
        }
        SceneManager.currentScene.updateAspectRatio()
        rebuildRenderTargets()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateScreenSize(view: view)
    }

    private func renderColorAndDepthToTexture(renderPipelineState: RenderPipelineStateType, colorTarget: AssetHandle, depthTarget: AssetHandle, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createColorAndDepthRenderPassDescriptor(colorTarget: colorTarget, depthTarget: depthTarget)) else { return }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineState])
        encoder.label = "Render To Texture"
        encoder.pushDebugGroup("Scene -> colorTarget & depthTarget")
        delegate?.renderScene(into: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
    
    private func renderColorToTexture(renderPipelineState: RenderPipelineStateType, colorTarget: AssetHandle, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: createColorOnlyRenderPassDescriptor(colorTarget: colorTarget)) else { return }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineState])
        encoder.label = "Render To Texture"
        encoder.pushDebugGroup("Scene -> colorTarget")
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
        encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.baseColorRender), index: 0)
        encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.bloomPing), index: 1)
        var settings = Renderer.settings
        encoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: 0)
        if let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh) {
            quadMesh.drawPrimitives(encoder)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    private func renderToWindow(renderPipelineState: RenderPipelineStateType, view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let rpd = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineState])
        encoder.label = "Render To Screen"
        encoder.pushDebugGroup("Final Composite -> Drawable")
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: 0)
        encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.baseColorRender), index: 0)
        encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.bloomPing), index: 1)
        var settings = Renderer.settings
        encoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: 0)
        if let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh) {
            quadMesh.drawPrimitives(encoder)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    public func draw(in view: MTKView) {
        let frameStart = CACurrentMediaTime()
        Mouse.BeginFrame()
        GameTime.UpdateTime(1.0 / Float(view.preferredFramesPerSecond))
        guard let drawable = view.currentDrawable,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0 else { return }
        let currentSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if _lastPerfFlags != Renderer.settings.perfFlags {
            _lastPerfFlags = Renderer.settings.perfFlags
            updateScreenSize(view: view)
        }
        if Renderer.DrawableSize != currentSize
            || AssetManager.texture(handle: BuiltinAssets.baseColorRender) == nil
            || AssetManager.texture(handle: BuiltinAssets.baseDepthRender) == nil {
            Renderer.DrawableSize = currentSize
            updateScreenSize(view: view)
        }
        let updateStart = CACurrentMediaTime()
        delegate?.update()
        Renderer.profiler.record(.update, seconds: CACurrentMediaTime() - updateStart)
        updateSkyIfNeeded(scene: SceneManager.currentScene)
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MetalCup Frame Command Buffer"
        let gpuStart = CACurrentMediaTime()
        commandBuffer.addCompletedHandler { _ in
            Renderer.profiler.record(.gpu, seconds: CACurrentMediaTime() - gpuStart)
        }

        let renderStart = CACurrentMediaTime()
        let sceneStart = CACurrentMediaTime()
        renderColorAndDepthToTexture(
            renderPipelineState: .HDRBasic,
            colorTarget: BuiltinAssets.baseColorRender,
            depthTarget: BuiltinAssets.baseDepthRender,
            commandBuffer: commandBuffer
        )
        Renderer.profiler.record(.scene, seconds: CACurrentMediaTime() - sceneStart)
        let bloomStart = CACurrentMediaTime()
        renderBloom(commandBuffer: commandBuffer)
        Renderer.profiler.record(.bloom, seconds: CACurrentMediaTime() - bloomStart)
        let compositeStart = CACurrentMediaTime()
        renderColorToTexture(
            renderPipelineState: .Final,
            colorTarget: BuiltinAssets.finalColorRender,
            commandBuffer: commandBuffer
        )
        Renderer.profiler.record(.composite, seconds: CACurrentMediaTime() - compositeStart)
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
