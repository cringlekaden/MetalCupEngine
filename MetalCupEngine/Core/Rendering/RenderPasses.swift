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

    static func colorLoad(texture: MTLTexture?, level: Int = 0) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
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

    static func withRenderPass(_ pass: RenderPassType, renderer: Renderer, frameContext: RendererFrameContext, _ body: () -> Void) {
        let previous = frameContext.currentRenderPass()
        renderer.currentRenderPass = pass
        frameContext.setCurrentRenderPass(pass)
        body()
        renderer.currentRenderPass = previous
        frameContext.setCurrentRenderPass(previous)
    }

    static func shouldRenderEditorOverlays(_ sceneView: SceneView) -> Bool {
        return sceneView.isEditorView
    }
}

struct FullscreenPass {
    var pipeline: RenderPipelineStateType
    var label: String
    var sampler: SamplerStateType
    var useSampler: Bool
    var texture0: MTLTexture?
    var useTexture0: Bool
    var texture1: MTLTexture?
    var useTexture1: Bool
    var outlineMask: MTLTexture?
    var useOutlineMask: Bool
    var depth: MTLTexture?
    var useDepth: Bool
    var grid: MTLTexture?
    var useGrid: Bool
    var settings: RendererSettings?

    func encode(into encoder: MTLRenderCommandEncoder, quad: MCMesh, frameContext: RendererFrameContext, graphics: Graphics) {
        encoder.setRenderPipelineState(graphics.renderPipelineStates[pipeline])
        encoder.label = label
        encoder.pushDebugGroup(label)
        encoder.setCullMode(.none)
        if useSampler {
            encoder.setFragmentSamplerState(graphics.samplerStates[sampler], index: FragmentSamplerIndex.linearClamp)
        }
        let fallback = frameContext.engineContext().fallbackTextures
        if useTexture0 {
            encoder.setFragmentTexture(texture0 ?? fallback.blackRGBA, index: PostProcessTextureIndex.source)
        }
        if useTexture1 {
            encoder.setFragmentTexture(texture1 ?? fallback.blackRGBA, index: PostProcessTextureIndex.bloom)
        }
        if useOutlineMask {
            encoder.setFragmentTexture(outlineMask ?? fallback.blackRGBA, index: PostProcessTextureIndex.outlineMask)
        }
        if useDepth {
            encoder.setFragmentTexture(depth ?? fallback.depth1x1, index: PostProcessTextureIndex.depth)
        }
        if useGrid {
            encoder.setFragmentTexture(grid ?? fallback.blackRGBA, index: PostProcessTextureIndex.grid)
        }
        let resolvedSettings = settings ?? frameContext.rendererSettings()
        let settingsBuffer = frameContext.uploadRendererSettings(resolvedSettings)
        encoder.setFragmentBuffer(settingsBuffer.buffer, offset: settingsBuffer.offset, index: FragmentBufferIndex.rendererSettings)
        quad.drawPrimitives(encoder, frameContext: frameContext)
        encoder.popDebugGroup()
    }
}

final class ShadowPass: RenderGraphPass {
    let name = "ShadowPass"
    let gpuPass: RendererProfiler.GpuPass? = .shadows

    func execute(frame: RenderGraphFrame) {
        frame.renderer.shadowRenderer.render(frame: frame)
    }
}

final class DepthPrepassPass: RenderGraphPass {
    let name = "DepthPrepassPass"
    let gpuPass: RendererProfiler.GpuPass? = .depthPrepass

    func execute(frame: RenderGraphFrame) {
        guard frame.renderer.useDepthPrepass else { return }
        guard let depth = frame.resources.texture(.baseDepth) else { return }
        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.depth(texture: depth)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Depth Prepass"
        encoder.pushDebugGroup("Depth Prepass")
        frame.profiler.sampleGpuPassBegin(.depthPrepass, encoder: encoder, frameIndex: frameIndex)
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(depth))
        RenderPassHelpers.withRenderPass(.depthPrepass, renderer: frame.renderer, frameContext: frame.frameContext) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.depthPrepass, encoder: encoder, frameIndex: frameIndex)
    }
}

final class ScenePass: RenderGraphPass {
    let name = "ScenePass"
    let gpuPass: RendererProfiler.GpuPass? = .scene

    func execute(frame: RenderGraphFrame) {
        let sceneStart = CACurrentMediaTime()
        guard
            let baseColor = frame.resources.texture(.baseColor),
            let baseDepth = frame.resources.texture(.baseDepth)
        else { return }

        let depthLoad: MTLLoadAction = frame.renderer.useDepthPrepass ? .load : .clear
        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.colorDepth(color: baseColor, depth: baseDepth, depthLoadAction: depthLoad)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(frame.engineContext.graphics.renderPipelineStates.hdrInstancedPipeline(settings: frame.renderer.settings))
        encoder.label = "Scene Pass"
        encoder.pushDebugGroup("Scene Pass")
        frame.profiler.sampleGpuPassBegin(.scene, encoder: encoder, frameIndex: frameIndex)
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(baseColor))
        RenderPassHelpers.withRenderPass(.main, renderer: frame.renderer, frameContext: frame.frameContext) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.scene, encoder: encoder, frameIndex: frameIndex)
        frame.profiler.record(.scene, seconds: CACurrentMediaTime() - sceneStart)
    }
}

final class PickingPass: RenderGraphPass {
    let name = "PickingPass"
    let gpuPass: RendererProfiler.GpuPass? = .picking

    func execute(frame: RenderGraphFrame) {
        // Outline relies on the pickId buffer, so keep it current while a selection is active.
        let hasSelection = frame.renderer.settings.outlineEnabled != 0
            && RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView)
            && !frame.sceneView.selectedEntityIds.isEmpty
        let needsPickingPass = frame.engineContext.pickingSystem.hasPendingRequest() || hasSelection
        guard needsPickingPass else { return }
        guard
            let pickId = frame.resources.texture(.pickId),
            let pickDepth = frame.resources.texture(.pickDepth)
        else { return }
        let request = frame.engineContext.pickingSystem.consumeRequest()

        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.color(texture: pickId, clearColor: MTLClearColorMake(0, 0, 0, 0))
        pass.depthAttachment.texture = pickDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0

        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Picking Pass"
        encoder.pushDebugGroup("Picking Pass")
        frame.profiler.sampleGpuPassBegin(.picking, encoder: encoder, frameIndex: frameIndex)
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(pickId))
        RenderPassHelpers.withRenderPass(.picking, renderer: frame.renderer, frameContext: frame.frameContext) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.picking, encoder: encoder, frameIndex: frameIndex)

        if let request, let readbackBuffer = frame.frameContext.pickReadbackBuffer() {
            frame.engineContext.pickingSystem.enqueueReadback(
                request: request,
                pickTexture: pickId,
                readbackBuffer: readbackBuffer,
                commandBuffer: frame.commandBuffer
            ) { pickedId, mask in
                frame.delegate?.handlePickResult(PickResult(pickedId: pickedId, mask: mask))
            }
        }
    }
}

final class GridOverlayPass: RenderGraphPass {
    let name = "GridOverlayPass"
    let gpuPass: RendererProfiler.GpuPass? = .grid

    func execute(frame: RenderGraphFrame) {
        guard frame.renderer.settings.gridEnabled != 0,
              RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView) else { return }
        guard let grid = frame.resources.texture(.gridColor) else { return }
        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.color(texture: grid, clearColor: MTLClearColorMake(0, 0, 0, 0))
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Grid Overlay"
        encoder.pushDebugGroup("Grid Overlay")
        defer {
            encoder.popDebugGroup()
            encoder.endEncoding()
            frame.profiler.sampleGpuPassEnd(.grid, encoder: encoder, frameIndex: frameIndex)
        }

        frame.profiler.sampleGpuPassBegin(.grid, encoder: encoder, frameIndex: frameIndex)
        guard
            let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh),
            var params = frame.engineContext.debugDraw.gridParams()
        else { return }

        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(grid))
        encoder.setRenderPipelineState(frame.engineContext.graphics.renderPipelineStates[.GridOverlay])
        encoder.setCullMode(.none)
        let depthTexture = frame.resources.texture(.baseDepth) ?? frame.engineContext.fallbackTextures.depth1x1
        encoder.setFragmentSamplerState(frame.engineContext.graphics.samplerStates[.LinearClampToZero], index: FragmentSamplerIndex.linearClamp)
        encoder.setFragmentTexture(depthTexture, index: PostProcessTextureIndex.depth)
        encoder.setFragmentBytes(&params, length: GridParams.stride, index: FragmentBufferIndex.gridParams)
        let settingsBuffer = frame.frameContext.uploadRendererSettings(frame.renderer.settings)
        encoder.setFragmentBuffer(settingsBuffer.buffer, offset: settingsBuffer.offset, index: FragmentBufferIndex.rendererSettings)
        quadMesh.drawPrimitives(encoder, frameContext: frame.frameContext)
    }
}

final class DebugDrawPass: RenderGraphPass {
    let name = "DebugDrawPass"
    let gpuPass: RendererProfiler.GpuPass? = nil

    func execute(frame: RenderGraphFrame) {
        guard frame.engineContext.physicsSettings.debugDrawEnabled,
              RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView),
              let scene = frame.delegate?.activeScene(),
              let grid = frame.resources.texture(.gridColor) else { return }
        let lines = frame.engineContext.debugDraw.lines()
        if lines.isEmpty {
            if frame.renderer.settings.gridEnabled == 0 {
                let pass = RenderPassBuilder.color(texture: grid, clearColor: MTLClearColorMake(0, 0, 0, 0))
                if let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                    encoder.label = "Debug Draw Clear"
                    encoder.endEncoding()
                }
            }
            return
        }
        let sceneConstants = scene.getSceneConstants()
        let cameraPosition = SIMD3<Float>(
            sceneConstants.cameraPositionAndIBL.x,
            sceneConstants.cameraPositionAndIBL.y,
            sceneConstants.cameraPositionAndIBL.z
        )
        let thickness = max(0.0001, frame.engineContext.debugDraw.lineThickness)
        var vertices: [DebugLineVertex] = []
        vertices.reserveCapacity(lines.count * 6)
        for line in lines {
            let p0 = line.start
            let p1 = line.end
            let dir = p1 - p0
            let length = simd_length(dir)
            if length < 0.0001 { continue }
            let lineDir = dir / length
            let mid = (p0 + p1) * 0.5
            var viewDir = cameraPosition - mid
            if simd_length_squared(viewDir) < 0.0001 {
                viewDir = SIMD3<Float>(0, 0, 1)
            }
            viewDir = simd_normalize(viewDir)
            var right = simd_cross(lineDir, viewDir)
            if simd_length_squared(right) < 0.0001 {
                right = simd_cross(lineDir, SIMD3<Float>(0, 1, 0))
                if simd_length_squared(right) < 0.0001 {
                    right = simd_cross(lineDir, SIMD3<Float>(1, 0, 0))
                }
            }
            right = simd_normalize(right)
            let offset = right * (thickness * 0.5)
            let v0 = p0 - offset
            let v1 = p0 + offset
            let v2 = p1 - offset
            let v3 = p1 + offset
            let color = line.color
            vertices.append(DebugLineVertex(position: v0, color: color))
            vertices.append(DebugLineVertex(position: v1, color: color))
            vertices.append(DebugLineVertex(position: v2, color: color))
            vertices.append(DebugLineVertex(position: v2, color: color))
            vertices.append(DebugLineVertex(position: v1, color: color))
            vertices.append(DebugLineVertex(position: v3, color: color))
        }
        if vertices.isEmpty { return }
        guard let buffer = frame.engineContext.device.makeBuffer(bytes: vertices,
                                                                 length: DebugLineVertex.stride(vertices.count),
                                                                 options: [.storageModeShared]) else { return }
        let size = RenderPassHelpers.textureSize(grid)
        let pass = frame.renderer.settings.gridEnabled != 0
            ? RenderPassBuilder.colorLoad(texture: grid)
            : RenderPassBuilder.color(texture: grid, clearColor: MTLClearColorMake(0, 0, 0, 0))
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Debug Draw"
        RenderPassHelpers.setViewport(encoder, size)
        encoder.setRenderPipelineState(frame.engineContext.graphics.renderPipelineStates[.DebugLines])
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer, offset: 0, index: VertexBufferIndex.vertices)
        var constants = sceneConstants
        if !frame.frameContext.iblReady() { constants.cameraPositionAndIBL.w = 0.0 }
        let constantsBuffer = frame.frameContext.uploadSceneConstants(constants)
        encoder.setVertexBuffer(constantsBuffer, offset: 0, index: VertexBufferIndex.sceneConstants)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
    }
}

final class SelectionOutlinePass: RenderGraphPass {
    let name = "SelectionOutlinePass"
    let gpuPass: RendererProfiler.GpuPass? = .outline

    func execute(frame: RenderGraphFrame) {
        OutlineSystem.encodeSelectionOutline(frame: frame)
    }
}

final class BloomExtractPass: RenderGraphPass {
    let name = "BloomExtractPass"
    let gpuPass: RendererProfiler.GpuPass? = .bloomExtract

    func execute(frame: RenderGraphFrame) {
        let settings = frame.renderer.settings
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
            let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh)
        else { return }

        let extractStart = CACurrentMediaTime()
        let frameIndex = frame.frameContext.currentFrameIndex()
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: 0)) else { return }
        let size0 = mipSize(for: ping, mip: 0)
        var params = settings
        params.bloomTexelSize = SIMD2<Float>(1.0 / size0.x, 1.0 / size0.y)
        params.bloomMipLevel = 0
        RenderPassHelpers.setViewport(encoder, size0)
        frame.profiler.sampleGpuPassBegin(.bloomExtract, encoder: encoder, frameIndex: frameIndex)
        let pass = FullscreenPass(
            pipeline: .BloomExtract,
            label: "Bloom Extract",
            sampler: .LinearClampToZero,
            useSampler: true,
            texture0: sceneTex,
            useTexture0: true,
            texture1: nil,
            useTexture1: false,
            outlineMask: nil,
            useOutlineMask: false,
            depth: nil,
            useDepth: false,
            grid: nil,
            useGrid: false,
            settings: params
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.bloomExtract, encoder: encoder, frameIndex: frameIndex)
        frame.profiler.record(.bloomExtract, seconds: CACurrentMediaTime() - extractStart)
    }

    private func mipSize(for texture: MTLTexture, mip: Int) -> SIMD2<Float> {
        let w = max(1, texture.width >> mip)
        let h = max(1, texture.height >> mip)
        return SIMD2<Float>(Float(w), Float(h))
    }
}

final class BloomBlurPass: RenderGraphPass {
    let name = "BloomBlurPass"
    let gpuPass: RendererProfiler.GpuPass? = .bloomBlur

    func execute(frame: RenderGraphFrame) {
        let settings = frame.renderer.settings
        if settings.bloomEnabled == 0 { return }
        guard
            let ping = frame.resources.texture(.bloomPing),
            let pong = frame.resources.texture(.bloomPong),
            let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh)
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

        let frameIndex = frame.frameContext.currentFrameIndex()
        var didSampleBegin = false
        var didSampleEnd = false

        func blurMip(_ mip: Int) {
            let size = mipSize(ping, mip)
            var params = settings
            params.bloomTexelSize = SIMD2<Float>(1.0 / size.x, 1.0 / size.y)
            params.bloomMipLevel = Float(mip)

            for i in 0..<passes {
                let blurStart = CACurrentMediaTime()
                guard let encH = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: pong, level: mip)) else { return }
                RenderPassHelpers.setViewport(encH, size)
                if !didSampleBegin {
                    frame.profiler.sampleGpuPassBegin(.bloomBlur, encoder: encH, frameIndex: frameIndex)
                    didSampleBegin = true
                }
                let passH = FullscreenPass(
                    pipeline: .BloomBlurH,
                    label: "Bloom Blur H \(mip) \(i)",
                    sampler: .LinearClampToZero,
                    useSampler: true,
                    texture0: ping,
                    useTexture0: true,
                    texture1: nil,
                    useTexture1: false,
                    outlineMask: nil,
                    useOutlineMask: false,
                    depth: nil,
                    useDepth: false,
                    grid: nil,
                    useGrid: false,
                    settings: params
                )
                passH.encode(into: encH, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
                encH.endEncoding()

                guard let encV = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: mip)) else { return }
                RenderPassHelpers.setViewport(encV, size)
                if !didSampleBegin {
                    frame.profiler.sampleGpuPassBegin(.bloomBlur, encoder: encV, frameIndex: frameIndex)
                    didSampleBegin = true
                }
                let passV = FullscreenPass(
                    pipeline: .BloomBlurV,
                    label: "Bloom Blur V \(mip) \(i)",
                    sampler: .LinearClampToZero,
                    useSampler: true,
                    texture0: pong,
                    useTexture0: true,
                    texture1: nil,
                    useTexture1: false,
                    outlineMask: nil,
                    useOutlineMask: false,
                    depth: nil,
                    useDepth: false,
                    grid: nil,
                    useGrid: false,
                    settings: params
                )
                passV.encode(into: encV, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
                if mip == (mipCount - 1), i == (passes - 1), !didSampleEnd {
                    frame.profiler.sampleGpuPassEnd(.bloomBlur, encoder: encV, frameIndex: frameIndex)
                    didSampleEnd = true
                }
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
                    useSampler: true,
                    texture0: ping,
                    useTexture0: true,
                    texture1: nil,
                    useTexture1: false,
                    outlineMask: nil,
                    useOutlineMask: false,
                    depth: nil,
                    useDepth: false,
                    grid: nil,
                    useGrid: false,
                    settings: params
                )
                pass.encode(into: enc, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
                enc.endEncoding()
                downsampleTotal += CACurrentMediaTime() - downsampleStart

                blurMip(mip)
            }
        }

        if downsampleTotal > 0 {
            frame.profiler.record(.bloomDownsample, seconds: downsampleTotal)
        }
        if blurTotal > 0 {
            frame.profiler.record(.bloomBlur, seconds: blurTotal)
        }
    }
}

final class FinalCompositePass: RenderGraphPass {
    let name = "FinalCompositePass"
    let gpuPass: RendererProfiler.GpuPass? = .finalComposite

    func execute(frame: RenderGraphFrame) {
        guard
            let baseColor = frame.resources.texture(.baseColor),
            let bloom = frame.resources.texture(.bloomPing),
            let outline = frame.resources.texture(.outlineMask),
            let grid = frame.resources.texture(.gridColor),
            let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh),
            let finalColor = frame.resources.texture(.finalColor)
        else { return }

        let compositeStart = CACurrentMediaTime()
        let frameIndex = frame.frameContext.currentFrameIndex()
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: finalColor)) else { return }
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(finalColor))
        frame.profiler.sampleGpuPassBegin(.finalComposite, encoder: encoder, frameIndex: frameIndex)
        let showEditorOverlays = RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView)
        let pass = FullscreenPass(
            pipeline: .Final,
            label: "Final Composite",
            sampler: .LinearClampToZero,
            useSampler: true,
            texture0: baseColor,
            useTexture0: true,
            texture1: bloom,
            useTexture1: true,
            outlineMask: showEditorOverlays ? outline : nil,
            useOutlineMask: showEditorOverlays,
            depth: nil,
            useDepth: false,
            grid: showEditorOverlays ? grid : nil,
            useGrid: showEditorOverlays,
            settings: frame.renderer.settings
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.finalComposite, encoder: encoder, frameIndex: frameIndex)
        frame.profiler.record(.composite, seconds: CACurrentMediaTime() - compositeStart)
    }
}
