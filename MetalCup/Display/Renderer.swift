//
//  Renderer.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit
import simd

class Renderer: NSObject {
    
    private var _baseRenderPassDescriptor : MTLRenderPassDescriptor!
    private let _projection = float4x4(perspectiveFov: .pi / 2, aspect: 1.0, nearZ: 0.1, farZ: 10.0)
    private let _views: [float4x4] = [float4x4(lookAt: .zero, center: [1,0,0], up: [0,-1,0]),
                             float4x4(lookAt: .zero, center: [-1,0,0], up: [0,-1,0]),
                             float4x4(lookAt: .zero, center: [0,-1,0], up: [0,0,-1]),
                             float4x4(lookAt: .zero, center: [0,1,0], up: [0,0,1]),
                             float4x4(lookAt: .zero, center: [0,0,1], up: [0,-1,0]),
                             float4x4(lookAt: .zero, center: [0,0,-1], up: [0,-1,0])]
    private var _viewProjections: [float4x4]!
    
    public static var ScreenSize = SIMD2<Float>(0, 0)
    public static var DrawableSize = SIMD2<Float>(0, 0)
    public static var AspectRatio: Float {
        return ScreenSize.y.isZero ? 1 : ScreenSize.x / ScreenSize.y
    }
    
    init(_ mtkView: MTKView) {
        super.init()
        _viewProjections = _views.map { _projection * $0 }
        SceneManager.SetScene(Preferences.initialSceneType)
        updateScreenSize(view: mtkView)
        renderSkyToEnvironmentMap()
        renderIrradianceMap()
        renderPrefilteredSpecularMap()
        renderBRDFLUT()
    }
    
    private func createBaseRenderPassDescriptor() {
        let baseColorTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.HDRColorPixelFormat, width: Int(Renderer.DrawableSize.x), height: Int(Renderer.DrawableSize.y), mipmapped: false)
        baseColorTextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender, texture: Engine.Device.makeTexture(descriptor: baseColorTextureDescriptor)!)
        let baseDepthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.defaultDepthPixelFormat, width: Int(Renderer.DrawableSize.x), height: Int(Renderer.DrawableSize.y), mipmapped: false)
        baseDepthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        baseDepthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender, texture: Engine.Device.makeTexture(descriptor: baseDepthTextureDescriptor)!)
        _baseRenderPassDescriptor = MTLRenderPassDescriptor()
        _baseRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender]
        _baseRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        _baseRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _baseRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _baseRenderPassDescriptor.depthAttachment.loadAction = .clear
        _baseRenderPassDescriptor.depthAttachment.storeAction = .store
    }
    
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
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.Cubemap], index: 0)
            Assets.Meshes[.Cubemap].drawPrimitives(encoder)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: Assets.Textures[.EnvironmentCubemap]!)
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
            encoder.setFragmentSamplerState(Graphics.SamplerStates[.Cubemap], index: 0)
            Assets.Meshes[.Cubemap].drawPrimitives(encoder)
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func renderPrefilteredSpecularMap() {
        let mipCount = Assets.Textures[.PrefilteredCubemap]?.mipmapLevelCount ?? 0
        let baseSize = Assets.Textures[.PrefilteredCubemap]?.width
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Prefiltered Specular Map"
        for mip in 0..<mipCount {
            let roughness = Float(mip) / Float(mipCount - 1)
            let mipSize = max(1, baseSize! >> mip)
            for face in 0..<6 {
                let passDescriptor = createPrefilteredSpecularMapRenderPassDescriptor(face: face, mip: mip)
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { continue }
                encoder.label = "Specular Cubemap face: \(face), mip: \(mip)"
                encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.PrefilteredMap])
                encoder.setCullMode(.front)
                encoder.setFrontFacing(.clockwise)
                encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(mipSize), height: Double(mipSize), znear: 0, zfar: 1))
                var vp = _viewProjections[face]
                var r = roughness
                encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
                encoder.setFragmentBytes(&r, length: MemoryLayout<Float>.stride, index: 0)
                encoder.setFragmentTexture(Assets.Textures[.EnvironmentCubemap], index: 0)
                encoder.setFragmentSamplerState(Graphics.SamplerStates[.Cubemap], index: 0)
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
}

extension Renderer: MTKViewDelegate {
    
    public func updateScreenSize(view: MTKView) {
        Renderer.ScreenSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        Renderer.DrawableSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        SceneManager.currentScene.updateAspectRatio()
        createBaseRenderPassDescriptor()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateScreenSize(view: view)
    }
    
    func renderToTexture(commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _baseRenderPassDescriptor)
        renderCommandEncoder?.label = "Render To Texture Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Rendering Scene to Texture")
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder!)
        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }
    
    func renderToScreen(view: MTKView, commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)
        renderCommandEncoder?.label = "Render To Screen Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Rendering Texture to Screen")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
        renderCommandEncoder?.setFragmentTexture(Assets.Textures[.BaseColorRender], index: 0)
        Assets.Meshes[.Quad].drawPrimitives(renderCommandEncoder!)
        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, view.drawableSize.width > 0, view.drawableSize.height > 0 else {
            return
        }
        let currentSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        if Renderer.DrawableSize.x != currentSize.x || Renderer.DrawableSize.y != currentSize.y || Assets.Textures[.BaseColorRender] == nil || Assets.Textures[.BaseDepthRender] == nil {
            Renderer.DrawableSize = currentSize
            createBaseRenderPassDescriptor()
        }

        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))

        let commandBuffer = Engine.CommandQueue.makeCommandBuffer()
        commandBuffer?.label = "MetalCup Scene Render Command Buffer"

        // Render to texture pass
        renderToTexture(commandBuffer: commandBuffer!)
        
        renderToScreen(view: view, commandBuffer: commandBuffer!)
        
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}

