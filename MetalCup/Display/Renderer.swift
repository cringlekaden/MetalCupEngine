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
    private var _shCoeffs: [SIMD3<Float>] = Array(repeating: .zero, count: 9)
    
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
        // Compute SH coefficients from the equirectangular HDR texture (linear)
        if let hdrTex = Assets.Textures[SceneManager.currentScene.environmentMap2D] {
            _shCoeffs = computeDiffuseSH(from: hdrTex)
        }
        renderIrradianceMap()
    }
    
    private func createBaseRenderPassDescriptor() {
        let baseColorTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.defaultColorPixelFormat, width: Int(Renderer.DrawableSize.x), height: Int(Renderer.DrawableSize.y), mipmapped: false)
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
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func renderIrradianceMap() {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Render Irradiance Map"
        for face in 0..<6 {
            let passDescriptor = createIrradianceMapRenderPassDescriptor(face: face)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { continue }
            encoder.label = "Cubemap face \(face)"
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.IrradianceMap])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var vp = _viewProjections[face]
            encoder.setVertexBytes(&vp, length: MemoryLayout<float4x4>.stride, index: 1)
            // Pass pre-convolved SH coefficients (9 x float3) to fragment shader at buffer index 0
            _shCoeffs.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress, bytes.count > 0 {
                    encoder.setFragmentBytes(base, length: bytes.count, index: 0)
                }
            }
            Assets.Meshes[.Cubemap].drawPrimitives(encoder)
            encoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // MARK: - SH Helpers (order 2, 9 coefficients)
    private func Y00(_ n: SIMD3<Float>) -> Float { 0.282095 }
    private func Y1m1(_ n: SIMD3<Float>) -> Float { 0.488603 * n.y }
    private func Y10(_ n: SIMD3<Float>) -> Float { 0.488603 * n.z }
    private func Y11(_ n: SIMD3<Float>) -> Float { 0.488603 * n.x }
    private func Y2m2(_ n: SIMD3<Float>) -> Float { 1.092548 * n.x * n.y }
    private func Y2m1(_ n: SIMD3<Float>) -> Float { 1.092548 * n.y * n.z }
    private func Y20(_ n: SIMD3<Float>) -> Float { 0.315392 * (3.0 * n.z * n.z - 1.0) }
    private func Y21(_ n: SIMD3<Float>) -> Float { 1.092548 * n.x * n.z }
    private func Y22(_ n: SIMD3<Float>) -> Float { 0.546274 * (n.x * n.x - n.y * n.y) }

    private func evalSH9(_ n: SIMD3<Float>) -> [Float] {
        return [
            Y00(n),
            Y1m1(n), Y10(n), Y11(n),
            Y2m2(n), Y2m1(n), Y20(n), Y21(n), Y22(n)
        ]
    }

    // Compute diffuse irradiance SH coefficients (pre-convolved by cosine kernel) from an equirectangular HDR texture.
    private func computeDiffuseSH(from hdr: MTLTexture) -> [SIMD3<Float>] {
        precondition(hdr.textureType == .type2D, "Expected 2D HDR texture for SH projection")
        let width = hdr.width
        let height = hdr.height
        let stepX = max(1, width / 512) // downsample sampling grid to keep cost reasonable
        let stepY = max(1, height / 256)
        // Determine pixel format and bytes per pixel
        let isRGBA32F = hdr.pixelFormat == .rgba32Float
        let isRGBA16F = hdr.pixelFormat == .rgba16Float
        precondition(isRGBA32F || isRGBA16F, "HDR texture must be rgba16Float or rgba32Float")
        let bytesPerPixel = isRGBA32F ? 16 : 8
        // Readback entire texture once
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height
        var raw = [UInt8](repeating: 0, count: totalBytes)
        hdr.getBytes(&raw, bytesPerRow: bytesPerRow, from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1)), mipmapLevel: 0)
        // Accumulate SH coefficients c_lm = ∫ L(ω) Y_lm(ω) dω
        var coeffs = Array(repeating: SIMD3<Float>(repeating: 0), count: 9)
        let dphi: Float = (2.0 * .pi) / Float(width)
        let dtheta: Float = .pi / Float(height)
        func readPixel(x: Int, y: Int) -> SIMD3<Float> {
            let rowPtr = y * bytesPerRow
            let offset = rowPtr + x * bytesPerPixel
            if isRGBA32F {
                // 4 floats per pixel
                return raw.withUnsafeBytes { ptr -> SIMD3<Float> in
                    let base = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                    return SIMD3<Float>(base[0], base[1], base[2])
                }
            } else {
                // rgba16f -> convert to Float via Float16
                return raw.withUnsafeBytes { ptr -> SIMD3<Float> in
                    let base = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt16.self)
                    let r = Float(Float16(bitPattern: base[0]))
                    let g = Float(Float16(bitPattern: base[1]))
                    let b = Float(Float16(bitPattern: base[2]))
                    return SIMD3<Float>(r, g, b)
                }
            }
        }
        for y in stride(from: 0, to: height, by: stepY) {
            // theta in [0, pi]
            let theta = (Float(y) + 0.5) * dtheta
            let sinTheta = sin(theta)
            if sinTheta <= 0 { continue }
            for x in stride(from: 0, to: width, by: stepX) {
                // phi in [0, 2*pi)
                let phi = (Float(x) + 0.5) * dphi
                let dir = SIMD3<Float>(
                    -sin(theta) * cos(phi),
                    cos(theta),
                    -sin(theta) * sin(phi)
                )
                let L = readPixel(x: x, y: y)
                let w = sinTheta * dtheta * dphi * Float(stepX * stepY)
                let b = evalSH9(dir)
                for i in 0..<9 {
                    coeffs[i] += L * (b[i] * w)
                }
            }
        }
        // Convolve with cosine kernel per band: k0 = pi, k1 = 2pi/3, k2 = pi/4
        let k0: Float = .pi
        let k1: Float = (2.0 * .pi) / 3.0
        let k2: Float = .pi / 4.0
        // Indices per band: l0 -> [0], l1 -> [1,2,3], l2 -> [4..8]
        coeffs[0] *= k0
        coeffs[1] *= k1; coeffs[2] *= k1; coeffs[3] *= k1
        for i in 4..<9 { coeffs[i] *= k2 }
        return coeffs
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

