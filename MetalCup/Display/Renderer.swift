//
//  Renderer.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit
import simd

final class Renderer: NSObject {

    private var _bloomParams = BloomParams()
    private var _bloomBlurPasses: Int = 6

    // MARK: - Render targets / descriptors

    private var _baseRenderPassDescriptor: MTLRenderPassDescriptor!

    // MARK: - Cubemap view projections

    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private let _views: [float4x4] = [
        float4x4(lookAt: .zero, center: [ 1, 0, 0], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [-1, 0, 0], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [ 0,-1, 0], up: [0, 0,-1]),
        float4x4(lookAt: .zero, center: [ 0, 1, 0], up: [0, 0, 1]),
        float4x4(lookAt: .zero, center: [ 0, 0, 1], up: [0,-1, 0]),
        float4x4(lookAt: .zero, center: [ 0, 0,-1], up: [0,-1, 0])
    ]
    private var _viewProjections: [float4x4]!

    // MARK: - Static sizes

    public static var ScreenSize = SIMD2<Float>(0, 0)
    public static var DrawableSize = SIMD2<Float>(0, 0)
    public static var AspectRatio: Float {
        return ScreenSize.y.isZero ? 1 : ScreenSize.x / ScreenSize.y
    }

    // MARK: - Init

    init(_ mtkView: MTKView) {
        super.init()
        _viewProjections = _views.map { _projection * $0 }
        SceneManager.SetScene(Preferences.initialSceneType)
        updateScreenSize(view: mtkView) // builds render targets + base pass desc
        // IBL generation
        renderSkyToEnvironmentMap()
        renderIrradianceMap()
        renderPrefilteredSpecularMap()
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
        Assets.Textures.setTexture(
            textureType: .BaseColorRender,
            texture: Engine.Device.makeTexture(descriptor: baseColorDesc)!
        )

        // Base depth
        let baseDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.defaultDepthPixelFormat,
            width: Int(Renderer.DrawableSize.x),
            height: Int(Renderer.DrawableSize.y),
            mipmapped: false
        )
        baseDepthDesc.usage = [.renderTarget, .shaderRead]
        baseDepthDesc.storageMode = .private
        Assets.Textures.setTexture(
            textureType: .BaseDepthRender,
            texture: Engine.Device.makeTexture(descriptor: baseDepthDesc)!
        )

        // Bloom half-res ping/pong
        let bw = max(1, Int(Renderer.DrawableSize.x) / 2)
        let bh = max(1, Int(Renderer.DrawableSize.y) / 2)
        let bloomDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            width: bw,
            height: bh,
            mipmapped: false
        )
        bloomDesc.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BloomPing, texture: Engine.Device.makeTexture(descriptor: bloomDesc)!)
        Assets.Textures.setTexture(textureType: .BloomPong, texture: Engine.Device.makeTexture(descriptor: bloomDesc)!)

        // Update bloom texel size for blur shaders
        _bloomParams.texelSize = SIMD2<Float>(1.0 / Float(bw), 1.0 / Float(bh))
    }

    private func createBaseRenderPassDescriptor() {
        _baseRenderPassDescriptor = MTLRenderPassDescriptor()
        _baseRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender]
        _baseRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        _baseRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _baseRenderPassDescriptor.colorAttachments[0].clearColor = ClearColor.Black
        _baseRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _baseRenderPassDescriptor.depthAttachment.loadAction = .clear
        _baseRenderPassDescriptor.depthAttachment.storeAction = .store
    }

    // MARK: - Generic 2D pass descriptor helper

    private func create2DRenderPassDescriptor(target: TextureType) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = Assets.Textures[target]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    // MARK: - Cubemap/IBL descriptors

    private func createCubemapRenderPassDescriptor(face: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = Assets.Textures[.EnvironmentCubemap]
        pass.colorAttachments[0].slice = face
        pass.colorAttachments[0].level = 0
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createIrradianceMapRenderPassDescriptor(face: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = Assets.Textures[.IrradianceCubemap]
        pass.colorAttachments[0].slice = face
        pass.colorAttachments[0].level = 0
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createPrefilteredSpecularMapRenderPassDescriptor(face: Int, mip: Int) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = Assets.Textures[.PrefilteredCubemap]
        pass.colorAttachments[0].slice = face
        pass.colorAttachments[0].level = mip
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    private func createBRDFRenderPassDescriptor() -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = Assets.Textures[.BRDF_LUT]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = ClearColor.Black
        return pass
    }

    // MARK: - IBL generation

    private func renderSkyToEnvironmentMap() {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Sky To Cubemap"
        for face in 0..<6 {
            let passDescriptor = createCubemapRenderPassDescriptor(face: face)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Cubemap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            encoder.setFragmentTexture(Assets.Textures[SceneManager.currentScene.environmentMap2D], index: 0)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
            Assets.Meshes[.Cubemap].drawPrimitives(encoder)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder(),
           let env = Assets.Textures[.EnvironmentCubemap] {
            blit.generateMipmaps(for: env)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderIrradianceMap() {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        for face in 0..<6 {
            let passDescriptor = createIrradianceMapRenderPassDescriptor(face: face)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { continue }
            encoder.label = "Irradiance Cubemap face: \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.IrradianceMap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            encoder.setFragmentTexture(Assets.Textures[.EnvironmentCubemap], index: 0)
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
            Assets.Meshes[.Cubemap].drawPrimitives(encoder)
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderPrefilteredSpecularMap() {
        guard
            let prefiltered = Assets.Textures[.PrefilteredCubemap],
            let env = Assets.Textures[.EnvironmentCubemap]
        else { return }
        let mipCount = prefiltered.mipmapLevelCount
        let baseSize = prefiltered.width
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        for mip in 0..<mipCount {
            let roughness = Float(mip) / Float(max(mipCount - 1, 1))
            let mipSize = max(1, baseSize >> mip)
            for face in 0..<6 {
                let passDescriptor = createPrefilteredSpecularMapRenderPassDescriptor(face: face, mip: mip)
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
                Assets.Meshes[.Cubemap].drawPrimitives(encoder)
                encoder.endEncoding()
            }
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func renderBRDFLUT() {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render BRDF LUT"
        let passDescriptor = createBRDFRenderPassDescriptor()
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.label = "BRDF LUT Encoder"
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.BRDF])
        encoder.setCullMode(.none)
        Assets.Meshes[.FullscreenQuad].drawPrimitives(encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - Bloom (extract + blur ping-pong)

    private func renderBloom(commandBuffer: MTLCommandBuffer) {
        guard
            let sceneTex = Assets.Textures[.BaseColorRender],
            let ping = Assets.Textures[.BloomPing],
            let pong = Assets.Textures[.BloomPong]
        else { return }
        // Pass 1: Extract bright -> ping
        do {
            let pass = create2DRenderPassDescriptor(target: .BloomPing)
            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            enc.label = "Bloom Extract"
            enc.pushDebugGroup("Bloom Extract")
            enc.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomExtract])
            enc.setCullMode(.none)
            // Inputs
            enc.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
            enc.setFragmentTexture(sceneTex, index: 0)
            // Params (buffer(0))
            var params = _bloomParams
            enc.setFragmentBytes(&params, length: MemoryLayout<BloomParams>.stride, index: 0)
            Assets.Meshes[.FullscreenQuad].drawPrimitives(enc)
            enc.popDebugGroup()
            enc.endEncoding()
        }
        // Passes 2..N: blur ping/pong
        for i in 0..<_bloomBlurPasses {
            // Horizontal: ping -> pong
            do {
                let pass = create2DRenderPassDescriptor(target: .BloomPong)
                guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
                enc.label = "Bloom Blur H \(i)"
                enc.pushDebugGroup("Bloom Blur H")
                enc.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomBlurH])
                enc.setCullMode(.none)
                enc.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
                enc.setFragmentTexture(ping, index: 0)
                var params = _bloomParams
                enc.setFragmentBytes(&params, length: MemoryLayout<BloomParams>.stride, index: 0)
                Assets.Meshes[.FullscreenQuad].drawPrimitives(enc)
                enc.popDebugGroup()
                enc.endEncoding()
            }
            // Vertical: pong -> ping
            do {
                let pass = create2DRenderPassDescriptor(target: .BloomPing)
                guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
                enc.label = "Bloom Blur V \(i)"
                enc.pushDebugGroup("Bloom Blur V")
                enc.setRenderPipelineState(Graphics.RenderPipelineStates[.BloomBlurV])
                enc.setCullMode(.none)
                enc.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
                enc.setFragmentTexture(pong, index: 0)
                var params = _bloomParams
                enc.setFragmentBytes(&params, length: MemoryLayout<BloomParams>.stride, index: 0)
                Assets.Meshes[.FullscreenQuad].drawPrimitives(enc)
                enc.popDebugGroup()
                enc.endEncoding()
            }
        }
    }
}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    public func updateScreenSize(view: MTKView) {
        Renderer.ScreenSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        Renderer.DrawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        SceneManager.currentScene.updateAspectRatio()

        rebuildRenderTargets()
        createBaseRenderPassDescriptor()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateScreenSize(view: view)
    }

    private func renderToTexture(commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: _baseRenderPassDescriptor) else { return }
        encoder.label = "Render To Texture"
        encoder.pushDebugGroup("Scene -> BaseColorRender")
        SceneManager.Render(renderCommandEncoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    private func renderToScreen(view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let rpd = view.currentRenderPassDescriptor else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.label = "Render To Screen"
        encoder.pushDebugGroup("Final Composite -> Drawable")
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
        encoder.setCullMode(.none)
        // Bind inputs explicitly (fullscreen quad path won't)
        encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClamp], index: 0)
        encoder.setFragmentTexture(Assets.Textures[.BaseColorRender], index: 0)
        encoder.setFragmentTexture(Assets.Textures[.BloomPing], index: 1)
        // Params (buffer(0)) - intensity used in final composite
        var params = _bloomParams
        encoder.setFragmentBytes(&params, length: MemoryLayout<BloomParams>.stride, index: 0)
        Assets.Meshes[.FullscreenQuad].drawPrimitives(encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0 else { return }
        let currentSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if Renderer.DrawableSize != currentSize || Assets.Textures[.BaseColorRender] == nil || Assets.Textures[.BaseDepthRender] == nil {
            Renderer.DrawableSize = currentSize
            updateScreenSize(view: view)
        }
        
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "MetalCup Frame Command Buffer"

        renderToTexture(commandBuffer: commandBuffer)

        renderBloom(commandBuffer: commandBuffer)

        renderToScreen(view: view, commandBuffer: commandBuffer)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
