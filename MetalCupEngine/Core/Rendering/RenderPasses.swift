/// RenderPasses.swift
/// Render graph pass implementations and helpers.
/// Created by Kaden Cringle

import MetalKit

struct RenderPassBuilder {
    static func color(texture: MTLTexture?, level: Int = 0, clearColor: MTLClearColor = ClearColor.Black) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].level = level
        return pass
    }

    static func depth(texture: MTLTexture?, clearDepth: Double = 1.0) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = clearDepth
        return pass
    }

    static func colorDepth(color texture: MTLTexture?, depth: MTLTexture?, depthLoadAction: MTLLoadAction = .clear) -> MTLRenderPassDescriptor {
        let pass = RenderPassBuilder.color(texture: texture)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = depthLoadAction
        pass.depthAttachment.storeAction = .store
        return pass
    }
}

struct RenderPassHelpers {
    static func setViewport(_ encoder: MTLRenderCommandEncoder, _ size: SIMD2<Float>) {
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(size.x),
            height: Double(size.y),
            znear: 0,
            zfar: 1
        ))
    }

    static func textureSize(_ texture: MTLTexture) -> SIMD2<Float> {
        SIMD2<Float>(Float(texture.width), Float(texture.height))
    }

    static func withRenderPass(_ pass: RenderPassType, _ body: () -> Void) {
        let previous = Renderer.currentRenderPass
        Renderer.currentRenderPass = pass
        body()
        Renderer.currentRenderPass = previous
    }

    static func shouldRenderEditorOverlays(_ sceneView: SceneView) -> Bool {
        return sceneView.isEditorView
    }
}

struct FullscreenPass {
    var pipeline: RenderPipelineStateType
    var label: String
    var sampler: SamplerStateType?
    var texture0: MTLTexture?
    var texture1: MTLTexture?
    var outlineMask: MTLTexture? = nil
    var depth: MTLTexture? = nil
    var grid: MTLTexture? = nil
    var settings: RendererSettings?

    func encode(into encoder: MTLRenderCommandEncoder, quad: MCMesh, frameContext: RendererFrameContext) {
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[pipeline])
        encoder.label = label
        encoder.pushDebugGroup(label)
        encoder.setCullMode(.none)
        if let sampler {
            encoder.setFragmentSamplerState(Graphics.SamplerStates[sampler], index: FragmentSamplerIndex.linearClamp)
        }
        if let texture0 {
            encoder.setFragmentTexture(texture0, index: PostProcessTextureIndex.source)
        }
        if let texture1 {
            encoder.setFragmentTexture(texture1, index: PostProcessTextureIndex.bloom)
        }
        if let outlineMask {
            encoder.setFragmentTexture(outlineMask, index: PostProcessTextureIndex.outlineMask)
        }
        if let depth {
            encoder.setFragmentTexture(depth, index: PostProcessTextureIndex.depth)
        }
        if let grid {
            encoder.setFragmentTexture(grid, index: PostProcessTextureIndex.grid)
        }
        if let settings {
            if let buffer = frameContext.uploadRendererSettings(settings) {
                encoder.setFragmentBuffer(buffer, offset: 0, index: FragmentBufferIndex.rendererSettings)
            }
        }
        quad.drawPrimitives(encoder, frameContext: frameContext)
        encoder.popDebugGroup()
    }
}

final class DepthPrepassPass: RenderGraphPass {
    let name = "DepthPrepassPass"

    func execute(frame: RenderGraphFrame) {
        guard Renderer.useDepthPrepass else { return }
        guard let depth = frame.resources.texture(.baseDepth) else { return }
        let pass = RenderPassBuilder.depth(texture: depth)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Depth Prepass"
        encoder.pushDebugGroup("Depth Prepass")
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(depth))
        RenderPassHelpers.withRenderPass(.depthPrepass) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}

final class ScenePass: RenderGraphPass {
    let name = "ScenePass"

    func execute(frame: RenderGraphFrame) {
        let sceneStart = CACurrentMediaTime()
        guard
            let baseColor = frame.resources.texture(.baseColor),
            let baseDepth = frame.resources.texture(.baseDepth)
        else { return }

        let depthLoad: MTLLoadAction = Renderer.useDepthPrepass ? .load : .clear
        let pass = RenderPassBuilder.colorDepth(color: baseColor, depth: baseDepth, depthLoadAction: depthLoad)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRBasic])
        encoder.label = "Scene Pass"
        encoder.pushDebugGroup("Scene Pass")
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(baseColor))
        RenderPassHelpers.withRenderPass(.main) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        Renderer.profiler.record(.scene, seconds: CACurrentMediaTime() - sceneStart)
    }
}

final class PickingPass: RenderGraphPass {
    let name = "PickingPass"

    func execute(frame: RenderGraphFrame) {
        guard
            let pickId = frame.resources.texture(.pickId),
            let pickDepth = frame.resources.texture(.pickDepth)
        else { return }

        let pass = RenderPassBuilder.color(texture: pickId, clearColor: MTLClearColorMake(0, 0, 0, 0))
        pass.depthAttachment.texture = pickDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0

        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Picking Pass"
        encoder.pushDebugGroup("Picking Pass")
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(pickId))
        RenderPassHelpers.withRenderPass(.picking) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
    }
}

final class GridOverlayPass: RenderGraphPass {
    let name = "GridOverlayPass"

    func execute(frame: RenderGraphFrame) {
        guard let grid = frame.resources.texture(.gridColor) else { return }
        let pass = RenderPassBuilder.color(texture: grid, clearColor: MTLClearColorMake(0, 0, 0, 0))
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Grid Overlay"
        encoder.pushDebugGroup("Grid Overlay")
        defer {
            encoder.popDebugGroup()
            encoder.endEncoding()
        }

        if Renderer.settings.gridEnabled == 0 || !RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView) {
            return
        }
        guard
            let depth = frame.resources.texture(.baseDepth),
            let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh),
            var params = DebugDraw.gridParams()
        else { return }

        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(grid))
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GridOverlay])
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(Graphics.SamplerStates[.LinearClampToZero], index: FragmentSamplerIndex.linearClamp)
        encoder.setFragmentTexture(depth, index: PostProcessTextureIndex.depth)
        encoder.setFragmentBytes(&params, length: GridParams.stride, index: FragmentBufferIndex.gridParams)
        if let buffer = frame.frameContext.uploadRendererSettings(Renderer.settings) {
            encoder.setFragmentBuffer(buffer, offset: 0, index: FragmentBufferIndex.rendererSettings)
        }
        quadMesh.drawPrimitives(encoder, frameContext: frame.frameContext)
    }
}

final class SelectionOutlinePass: RenderGraphPass {
    let name = "SelectionOutlinePass"

    func execute(frame: RenderGraphFrame) {
        OutlineSystem.encodeSelectionOutline(frame: frame)
    }
}

final class BloomExtractPass: RenderGraphPass {
    let name = "BloomExtractPass"

    func execute(frame: RenderGraphFrame) {
        let settings = Renderer.settings
        if settings.bloomEnabled == 0 {
            if let ping = frame.resources.texture(.bloomPing),
               let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: 0)) {
                encoder.label = "Bloom Clear"
                encoder.endEncoding()
            }
            return
        }
        guard
            let sceneTex = frame.resources.texture(.baseColor),
            let ping = frame.resources.texture(.bloomPing),
            let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh)
        else { return }

        let extractStart = CACurrentMediaTime()
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: 0)) else { return }
        let size0 = mipSize(for: ping, mip: 0)
        var params = settings
        params.bloomTexelSize = SIMD2<Float>(1.0 / size0.x, 1.0 / size0.y)
        params.bloomMipLevel = 0
        RenderPassHelpers.setViewport(encoder, size0)
        let pass = FullscreenPass(
            pipeline: .BloomExtract,
            label: "Bloom Extract",
            sampler: .LinearClampToZero,
            texture0: sceneTex,
            texture1: nil,
            settings: params
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frame.frameContext)
        encoder.endEncoding()
        Renderer.profiler.record(.bloomExtract, seconds: CACurrentMediaTime() - extractStart)
    }

    private func mipSize(for texture: MTLTexture, mip: Int) -> SIMD2<Float> {
        let w = max(1, texture.width >> mip)
        let h = max(1, texture.height >> mip)
        return SIMD2<Float>(Float(w), Float(h))
    }
}

final class BloomBlurPass: RenderGraphPass {
    let name = "BloomBlurPass"

    func execute(frame: RenderGraphFrame) {
        let settings = Renderer.settings
        if settings.bloomEnabled == 0 { return }
        guard
            let ping = frame.resources.texture(.bloomPing),
            let pong = frame.resources.texture(.bloomPong),
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
                guard let encH = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: pong, level: mip)) else { return }
                RenderPassHelpers.setViewport(encH, size)
                let passH = FullscreenPass(
                    pipeline: .BloomBlurH,
                    label: "Bloom Blur H \(mip) \(i)",
                    sampler: .LinearClampToZero,
                    texture0: ping,
                    texture1: nil,
                    settings: params
                )
                passH.encode(into: encH, quad: quadMesh, frameContext: frame.frameContext)
                encH.endEncoding()

                guard let encV = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: mip)) else { return }
                RenderPassHelpers.setViewport(encV, size)
                let passV = FullscreenPass(
                    pipeline: .BloomBlurV,
                    label: "Bloom Blur V \(mip) \(i)",
                    sampler: .LinearClampToZero,
                    texture0: pong,
                    texture1: nil,
                    settings: params
                )
                passV.encode(into: encV, quad: quadMesh, frameContext: frame.frameContext)
                encV.endEncoding()
                blurTotal += CACurrentMediaTime() - blurStart
            }
        }

        blurMip(0)

        if mipCount > 1 {
            for mip in 1..<mipCount {
                let prevSize = mipSize(ping, mip - 1)
                let size = mipSize(ping, mip)
                var params = settings
                params.bloomTexelSize = SIMD2<Float>(1.0 / prevSize.x, 1.0 / prevSize.y)
                params.bloomMipLevel = Float(mip - 1)

                let downsampleStart = CACurrentMediaTime()
                guard let enc = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: mip)) else { return }
                RenderPassHelpers.setViewport(enc, size)
                let pass = FullscreenPass(
                    pipeline: .BloomDownsample,
                    label: "Bloom Downsample \(mip)",
                    sampler: .LinearClampToZero,
                    texture0: ping,
                    texture1: nil,
                    settings: params
                )
                pass.encode(into: enc, quad: quadMesh, frameContext: frame.frameContext)
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

final class FinalCompositePass: RenderGraphPass {
    let name = "FinalCompositePass"

    func execute(frame: RenderGraphFrame) {
        guard
            let baseColor = frame.resources.texture(.baseColor),
            let bloom = frame.resources.texture(.bloomPing),
            let outline = frame.resources.texture(.outlineMask),
            let grid = frame.resources.texture(.gridColor),
            let quadMesh = AssetManager.mesh(handle: BuiltinAssets.fullscreenQuadMesh),
            let finalColor = frame.resources.texture(.finalColor)
        else { return }

        let compositeStart = CACurrentMediaTime()
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: finalColor)) else { return }
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(finalColor))
        let pass = FullscreenPass(
            pipeline: .Final,
            label: "Final Composite",
            sampler: .LinearClampToZero,
            texture0: baseColor,
            texture1: bloom,
            outlineMask: outline,
            grid: grid,
            settings: Renderer.settings
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frame.frameContext)
        encoder.endEncoding()
        Renderer.profiler.record(.composite, seconds: CACurrentMediaTime() - compositeStart)
    }
}
