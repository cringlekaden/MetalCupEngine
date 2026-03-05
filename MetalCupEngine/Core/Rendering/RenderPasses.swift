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

    static func withRenderPass(_ pass: RenderPassType, frameContext: RendererFrameContext, _ body: () -> Void) {
        let previous = frameContext.currentRenderPass()
        frameContext.setCurrentRenderPass(pass)
        body()
        frameContext.setCurrentRenderPass(previous)
    }

    static func shouldRenderEditorOverlays(_ frameContext: RendererFrameContext, fallback sceneView: SceneView) -> Bool {
        let contextFlag = frameContext.viewContext().showEditorOverlays
        return contextFlag || sceneView.isEditorView
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
    let outputs: [RenderPassResourceUsage] = [
        .namedTexture("shadow.map"),
        .buffer("shadow.constants")
    ]

    func execute(frame: RenderGraphFrame) {
        frame.renderer.shadowRenderer.render(frame: frame)
    }
}

final class DepthPrepassPass: RenderGraphPass {
    let name = "DepthPrepassPass"
    let gpuPass: RendererProfiler.GpuPass? = .depthPrepass
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .baseDepth)),
        .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.baseDepth),
        .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth, requiredUsage: .shaderRead)
    ]

    func execute(frame: RenderGraphFrame) {
        guard frame.frameContext.useDepthPrepass() else { return }
        guard let depth = frame.resourceRegistry.texture(.baseDepth) else { return }
        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.depth(texture: depth)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Depth Prepass"
        encoder.pushDebugGroup("Depth Prepass")
        frame.profiler.sampleGpuPassBegin(.depthPrepass, encoder: encoder, frameIndex: frameIndex)
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(depth))
        RenderPassHelpers.withRenderPass(.depthPrepass, frameContext: frame.frameContext) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.depthPrepass, encoder: encoder, frameIndex: frameIndex)
        frame.resourceRegistry.registerNamedTexture(
            RenderNamedResourceKey.forwardPlusCullingDepth,
            texture: depth,
            lifetime: .transientPerFrame
        )
    }
}

final class CullingDepthFallbackPass: RenderGraphPass {
    let name = "CullingDepthFallbackPass"
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .baseDepth)),
        .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.baseDepth),
        .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth, requiredUsage: .shaderRead)
    ]

    func execute(frame: RenderGraphFrame) {
        guard !frame.frameContext.useDepthPrepass() else { return }
        guard let depth = frame.resourceRegistry.texture(.baseDepth) else { return }
        let pass = RenderPassBuilder.depth(texture: depth)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Culling Depth Fallback"
        encoder.pushDebugGroup("Culling Depth Fallback")
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(depth))
        RenderPassHelpers.withRenderPass(.depthPrepass, frameContext: frame.frameContext) {
            frame.delegate?.renderScene(into: encoder, frameContext: frame.frameContext)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        frame.resourceRegistry.registerNamedTexture(
            RenderNamedResourceKey.forwardPlusCullingDepth,
            texture: depth,
            lifetime: .transientPerFrame
        )
    }
}

final class LightCullingPass: RenderGraphPass {
    let name = "LightCullingPass"
    let inputs: [RenderPassResourceUsage] = [
        .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth, requiredUsage: .shaderRead)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .buffer(RenderNamedResourceKey.forwardPlusLightGrid, requiredUsage: [.computeWrite]),
        .buffer(RenderNamedResourceKey.forwardPlusLightIndexList, requiredUsage: [.computeWrite]),
        .buffer(RenderNamedResourceKey.forwardPlusLightIndexCount, requiredUsage: [.computeWrite]),
        .buffer(RenderNamedResourceKey.forwardPlusClusterParams, requiredUsage: [.computeWrite])
    ]
    private let tileSize = SIMD2<UInt32>(ForwardPlusConfig.tileSizeX, ForwardPlusConfig.tileSizeY)
    private let maxLightsPerCluster: UInt32 = ForwardPlusConfig.maxLightsPerCluster
    private var computePipeline: MTLComputePipelineState?
#if DEBUG
    private var wasForwardPlusEnabledLastFrame = false
#endif

    func execute(frame: RenderGraphFrame) {
#if DEBUG
        MC_ASSERT(ForwardPlusClusterParams.stride == ForwardPlusClusterParams.expectedMetalStride,
                  "ForwardPlusClusterParams ABI mismatch: expected stride \(ForwardPlusClusterParams.expectedMetalStride), got \(ForwardPlusClusterParams.stride).")
        MC_ASSERT(MemoryLayout<ForwardPlusClusterParams>.alignment == ForwardPlusClusterParams.expectedMetalAlignment,
                  "ForwardPlusClusterParams ABI mismatch: expected alignment \(ForwardPlusClusterParams.expectedMetalAlignment), got \(MemoryLayout<ForwardPlusClusterParams>.alignment).")
        MC_ASSERT(ForwardPlusIndexHeader.stride == ForwardPlusIndexHeader.expectedMetalStride,
                  "ForwardPlusIndexHeader ABI mismatch: expected stride \(ForwardPlusIndexHeader.expectedMetalStride), got \(ForwardPlusIndexHeader.stride).")
        MC_ASSERT(MemoryLayout<ForwardPlusIndexHeader>.alignment == ForwardPlusIndexHeader.expectedMetalAlignment,
                  "ForwardPlusIndexHeader ABI mismatch: expected alignment \(ForwardPlusIndexHeader.expectedMetalAlignment), got \(MemoryLayout<ForwardPlusIndexHeader>.alignment).")
        MC_ASSERT(ForwardPlusCullLight.stride == ForwardPlusCullLight.expectedMetalStride,
                  "ForwardPlusCullLight ABI mismatch: expected stride \(ForwardPlusCullLight.expectedMetalStride), got \(ForwardPlusCullLight.stride).")
        MC_ASSERT(MemoryLayout<ForwardPlusCullLight>.alignment == ForwardPlusCullLight.expectedMetalAlignment,
                  "ForwardPlusCullLight ABI mismatch: expected alignment \(ForwardPlusCullLight.expectedMetalAlignment), got \(MemoryLayout<ForwardPlusCullLight>.alignment).")
        MC_ASSERT(ForwardPlusCullUniforms.stride == ForwardPlusCullUniforms.expectedMetalStride,
                  "ForwardPlusCullUniforms ABI mismatch: expected stride \(ForwardPlusCullUniforms.expectedMetalStride), got \(ForwardPlusCullUniforms.stride).")
#endif
        guard let baseDepth = frame.resourceRegistry.namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth) else {
#if DEBUG
            fatalError("LightCullingPass requires \(RenderNamedResourceKey.forwardPlusCullingDepth) to be produced before culling.")
#else
            return
#endif
        }

        let viewport = SIMD2<UInt32>(UInt32(max(baseDepth.width, 1)), UInt32(max(baseDepth.height, 1)))
        let tileCount = SIMD2<UInt32>(
            max(1, (viewport.x + tileSize.x - 1) / tileSize.x),
            max(1, (viewport.y + tileSize.y - 1) / tileSize.y)
        )
        let tileTotalU32 = max(1, tileCount.x * tileCount.y)
        let tileTotal = Int(tileTotalU32)
        let gridByteCount = max(tileTotal * MemoryLayout<SIMD2<UInt32>>.stride, MemoryLayout<SIMD2<UInt32>>.stride)
        let indexCapacity64 = UInt64(tileTotalU32) * UInt64(maxLightsPerCluster)
        let indexCapacity = Int(min(indexCapacity64, UInt64(Int.max / MemoryLayout<UInt32>.stride)))
        let indexListByteCount = max(indexCapacity * MemoryLayout<UInt32>.stride, MemoryLayout<UInt32>.stride)
        let device = frame.engineContext.device

        guard let gridBuffer = device.makeBuffer(length: gridByteCount, options: [.storageModeShared]),
              let indexListBuffer = device.makeBuffer(length: indexListByteCount, options: [.storageModeShared]),
              let indexCountBuffer = device.makeBuffer(length: ForwardPlusIndexHeader.stride, options: [.storageModeShared]),
              let clusterParamsBuffer = device.makeBuffer(length: ForwardPlusClusterParams.stride, options: [.storageModeShared]) else {
            return
        }

        gridBuffer.label = "ForwardPlus.LightGrid"
        indexListBuffer.label = "ForwardPlus.LightIndexList"
        indexCountBuffer.label = "ForwardPlus.LightIndexCount"
        clusterParamsBuffer.label = "ForwardPlus.ClusterParams"
        gridBuffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: gridBuffer.length)
        indexListBuffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: indexListBuffer.length)
        indexCountBuffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: indexCountBuffer.length)

        var params = ForwardPlusClusterParams()
        params.header = SIMD4<UInt32>(
            ForwardPlusConfig.abiVersion,
            ForwardPlusConfig.zSliceCount,
            tileCount.x,
            tileCount.y
        )
        params.tileAndViewport = SIMD4<UInt32>(
            tileSize.x,
            tileSize.y,
            viewport.x,
            viewport.y
        )
        withUnsafeBytes(of: &params) { bytes in
            clusterParamsBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: ForwardPlusClusterParams.stride)
        }
        var indexHeader = ForwardPlusIndexHeader()
        indexHeader.abiVersion = ForwardPlusConfig.abiVersion
        indexHeader.totalIndexCount = 0
        indexHeader.overflowClusterCount = 0
        indexHeader.maxIndexCapacity = UInt32(indexCapacity)
        withUnsafeBytes(of: &indexHeader) { bytes in
            indexCountBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: ForwardPlusIndexHeader.stride)
        }

        let forwardPlusEnabled = frame.frameContext.rendererSettings().hasPerfFlag(.forwardPlusEnabled)
        if forwardPlusEnabled {
            runComputeCulling(frame: frame,
                              depthTexture: baseDepth,
                              tileCount: tileCount,
                              viewport: viewport,
                              indexCapacity: UInt32(indexCapacity),
                              clusterParamsBuffer: clusterParamsBuffer,
                              indexHeaderBuffer: indexCountBuffer,
                              gridBuffer: gridBuffer,
                              indexListBuffer: indexListBuffer)
        }

        frame.resourceRegistry.registerBuffer(
            RenderNamedResourceKey.forwardPlusLightGrid,
            buffer: gridBuffer,
            lifetime: .transientPerFrame,
            usage: [.computeWrite]
        )
        frame.resourceRegistry.registerBuffer(
            RenderNamedResourceKey.forwardPlusLightIndexList,
            buffer: indexListBuffer,
            lifetime: .transientPerFrame,
            usage: [.computeWrite]
        )
        frame.resourceRegistry.registerBuffer(
            RenderNamedResourceKey.forwardPlusLightIndexCount,
            buffer: indexCountBuffer,
            lifetime: .transientPerFrame,
            usage: [.computeWrite]
        )
        frame.resourceRegistry.registerBuffer(
            RenderNamedResourceKey.forwardPlusClusterParams,
            buffer: clusterParamsBuffer,
            lifetime: .transientPerFrame,
            usage: [.computeWrite]
        )
#if DEBUG
        if forwardPlusEnabled && !wasForwardPlusEnabledLastFrame {
            runForwardPlusEnableSelfCheck(
                frame: frame,
                depthTexture: baseDepth,
                clusterParamsBuffer: clusterParamsBuffer,
                indexHeaderBuffer: indexCountBuffer
            )
        }
        wasForwardPlusEnabledLastFrame = forwardPlusEnabled
#endif
    }

    private func runComputeCulling(frame: RenderGraphFrame,
                                   depthTexture: MTLTexture,
                                   tileCount: SIMD2<UInt32>,
                                   viewport: SIMD2<UInt32>,
                                   indexCapacity: UInt32,
                                   clusterParamsBuffer: MTLBuffer,
                                   indexHeaderBuffer: MTLBuffer,
                                   gridBuffer: MTLBuffer,
                                   indexListBuffer: MTLBuffer) {
        guard let pipeline = resolvePipeline(frame: frame) else { return }
        let snapshotLights = frame.sceneSnapshot?.lightData ?? []
        let cullLights = snapshotLights.map { light in
            var out = ForwardPlusCullLight()
            out.positionAndRange = SIMD4<Float>(light.position, max(light.range, 0.0))
            out.directionAndType = SIMD4<Float>(light.direction, Float(light.type))
            out.colorAndIntensity = SIMD4<Float>(light.color, max(light.brightness, 0.0))
            out.spotParams = SIMD4<Float>(light.innerConeCos, light.outerConeCos, 0.0, 0.0)
            return out
        }
        let lightBufferLength = max(ForwardPlusCullLight.stride(cullLights.count), ForwardPlusCullLight.stride)
        guard let lightBuffer = frame.engineContext.device.makeBuffer(length: lightBufferLength, options: [.storageModeShared]),
              let uniformsBuffer = frame.engineContext.device.makeBuffer(length: ForwardPlusCullUniforms.stride, options: [.storageModeShared]) else {
            return
        }
        lightBuffer.label = "ForwardPlus.CullLights"
        uniformsBuffer.label = "ForwardPlus.CullUniforms"
        if cullLights.isEmpty {
            lightBuffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: lightBufferLength)
        } else {
            cullLights.withUnsafeBytes { bytes in
                lightBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
            }
        }

        var uniforms = ForwardPlusCullUniforms()
        if let snapshot = frame.sceneSnapshot {
            uniforms.viewMatrix = snapshot.sceneConstants.viewMatrix
            uniforms.projectionMatrix = snapshot.sceneConstants.projectionMatrix
        }
        uniforms.params0 = SIMD4<UInt32>(viewport.x, viewport.y, UInt32(cullLights.count), maxLightsPerCluster)
        uniforms.params1 = SIMD4<UInt32>(tileCount.x, tileCount.y, indexCapacity, 0)
#if DEBUG
        MC_ASSERT(uniforms.viewMatrix.columns.0.x.isFinite &&
                  uniforms.projectionMatrix.columns.0.x.isFinite,
                  "Forward+ cull uniforms contain invalid matrix values.")
#endif
        withUnsafeBytes(of: &uniforms) { bytes in
            uniformsBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: ForwardPlusCullUniforms.stride)
        }

        guard let encoder = frame.commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Forward+ Light Culling"
        encoder.pushDebugGroup("Forward+ Light Culling")
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(depthTexture, index: ShaderBindings.ComputeTexture.depth)
        encoder.setBuffer(lightBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.cullLights)
        encoder.setBuffer(clusterParamsBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.clusterParams)
        encoder.setBuffer(indexHeaderBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.indexHeader)
        encoder.setBuffer(uniformsBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.cullUniforms)
        encoder.setBuffer(gridBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.lightGrid)
        encoder.setBuffer(indexListBuffer, offset: 0, index: ShaderBindings.ComputeBuffer.lightIndexList)

        let w = min(pipeline.threadExecutionWidth, Int(tileSize.x))
        let maxThreads = max(pipeline.maxTotalThreadsPerThreadgroup / max(w, 1), 1)
        let h = min(maxThreads, Int(tileSize.y))
        let threadsPerThreadgroup = MTLSize(width: max(w, 1), height: max(h, 1), depth: 1)
        let threadgroups = MTLSize(
            width: (Int(tileCount.x) + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (Int(tileCount.y) + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.popDebugGroup()
        encoder.endEncoding()

#if DEBUG
        scheduleForwardPlusDebugValidation(
            commandBuffer: frame.commandBuffer,
            gridBuffer: gridBuffer,
            indexListBuffer: indexListBuffer,
            indexHeaderBuffer: indexHeaderBuffer,
            tileCount: Int(tileCount.x * tileCount.y),
            lightCount: cullLights.count,
            maxLightsPerCluster: Int(maxLightsPerCluster)
        )
#endif
    }

#if DEBUG
    private func scheduleForwardPlusDebugValidation(commandBuffer: MTLCommandBuffer,
                                                    gridBuffer: MTLBuffer,
                                                    indexListBuffer: MTLBuffer,
                                                    indexHeaderBuffer: MTLBuffer,
                                                    tileCount: Int,
                                                    lightCount: Int,
                                                    maxLightsPerCluster: Int) {
        commandBuffer.addCompletedHandler { _ in
            let header = indexHeaderBuffer.contents().bindMemory(to: ForwardPlusIndexHeader.self, capacity: 1).pointee
            let maxCapacity = Int(header.maxIndexCapacity)
            let totalIndexCount = Int(header.totalIndexCount)
            MC_ASSERT(totalIndexCount <= maxCapacity,
                      "Forward+ validation failed: totalIndexCount \(totalIndexCount) exceeds maxIndexCapacity \(maxCapacity).")

            let entryCount = max(tileCount, 1)
            let gridEntries = gridBuffer.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: entryCount)
            let indices = indexListBuffer.contents().bindMemory(to: UInt32.self, capacity: max(maxCapacity, 1))

            for i in 0..<entryCount {
                let entry = gridEntries[i]
                let offset = Int(entry.x)
                let count = Int(entry.y)
                MC_ASSERT(count <= maxLightsPerCluster,
                          "Forward+ validation failed: cluster \(i) count \(count) exceeds maxLightsPerCluster \(maxLightsPerCluster).")
                if count == 0 {
                    continue
                }
                MC_ASSERT(offset < totalIndexCount,
                          "Forward+ validation failed: cluster \(i) offset \(offset) is out of bounds (totalIndexCount \(totalIndexCount)).")
                MC_ASSERT(offset + count <= totalIndexCount,
                          "Forward+ validation failed: cluster \(i) range [\(offset), \(offset + count)) exceeds totalIndexCount \(totalIndexCount).")
                MC_ASSERT(offset + count <= maxCapacity,
                          "Forward+ validation failed: cluster \(i) range [\(offset), \(offset + count)) exceeds maxIndexCapacity \(maxCapacity).")
                if lightCount <= 0 {
                    MC_ASSERT(count == 0, "Forward+ validation failed: cluster \(i) has lights while snapshot lightCount is zero.")
                    continue
                }
                for j in 0..<count {
                    let lightIndex = Int(indices[offset + j])
                    MC_ASSERT(lightIndex < lightCount,
                              "Forward+ validation failed: cluster \(i) contains lightIndex \(lightIndex) >= lightCount \(lightCount).")
                }
            }
        }
    }

    private func runForwardPlusEnableSelfCheck(frame: RenderGraphFrame,
                                               depthTexture: MTLTexture,
                                               clusterParamsBuffer: MTLBuffer,
                                               indexHeaderBuffer: MTLBuffer) {
        MC_ASSERT(depthTexture.usage.contains(.shaderRead),
                  "Forward+ self-check failed: culling depth texture must be shader-readable.")
        MC_ASSERT(frame.resourceRegistry.namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth) != nil,
                  "Forward+ self-check failed: missing culling depth texture contract resource.")

        let requiredBuffers = [
            RenderNamedResourceKey.forwardPlusLightGrid,
            RenderNamedResourceKey.forwardPlusLightIndexList,
            RenderNamedResourceKey.forwardPlusLightIndexCount,
            RenderNamedResourceKey.forwardPlusClusterParams
        ]
        for key in requiredBuffers {
            let metadata = frame.resourceRegistry.bufferMetadata(key)
            MC_ASSERT(metadata != nil, "Forward+ self-check failed: missing required buffer '\(key)'.")
            MC_ASSERT(metadata?.usage.contains(.computeWrite) == true,
                      "Forward+ self-check failed: buffer '\(key)' must declare computeWrite usage.")
            MC_ASSERT(metadata?.storageMode == .shared || metadata?.storageMode == .private,
                      "Forward+ self-check failed: buffer '\(key)' has unsupported storage mode.")
        }

        MC_ASSERT(ForwardPlusConfig.abiVersion == ForwardPlusClusterParams.abiVersion,
                  "Forward+ self-check failed: ABI mismatch between config and cluster params.")
        MC_ASSERT(ForwardPlusConfig.abiVersion == ForwardPlusIndexHeader.abiVersion,
                  "Forward+ self-check failed: ABI mismatch between config and index header.")
        MC_ASSERT(ForwardPlusConfig.zSliceCount > 0, "Forward+ self-check failed: zSliceCount must be > 0.")

        let clusterParams = clusterParamsBuffer.contents().bindMemory(to: ForwardPlusClusterParams.self, capacity: 1).pointee
        MC_ASSERT(clusterParams.header.x == ForwardPlusConfig.abiVersion,
                  "Forward+ self-check failed: cluster params ABI version mismatch.")
        MC_ASSERT(clusterParams.header.y == ForwardPlusConfig.zSliceCount,
                  "Forward+ self-check failed: cluster params z-slice count mismatch.")

        let indexHeader = indexHeaderBuffer.contents().bindMemory(to: ForwardPlusIndexHeader.self, capacity: 1).pointee
        MC_ASSERT(indexHeader.abiVersion == ForwardPlusConfig.abiVersion,
                  "Forward+ self-check failed: index header ABI version mismatch.")
        MC_ASSERT(indexHeader.maxIndexCapacity > 0,
                  "Forward+ self-check failed: index list capacity must be > 0.")
    }
#endif

    private func resolvePipeline(frame: RenderGraphFrame) -> MTLComputePipelineState? {
        if let computePipeline { return computePipeline }
        guard let fn = frame.engineContext.resources.resolveFunction(
            "kernel_forward_plus_cull",
            device: frame.engineContext.device,
            fallbackLibrary: frame.engineContext.defaultLibrary
        ) else {
            frame.engineContext.log.logWarning("Forward+ compute function 'kernel_forward_plus_cull' not found; using empty culling output.", category: .renderer)
            return nil
        }
        do {
            let pipeline = try frame.engineContext.device.makeComputePipelineState(function: fn)
            computePipeline = pipeline
            return pipeline
        } catch {
            frame.engineContext.log.logWarning("Failed to create Forward+ compute pipeline: \(error)", category: .renderer)
            return nil
        }
    }
}

final class ScenePass: RenderGraphPass {
    let name = "ScenePass"
    let gpuPass: RendererProfiler.GpuPass? = .scene
    let inputs: [RenderPassResourceUsage] = [
        .texture(.baseDepth),
        .buffer(RenderNamedResourceKey.forwardPlusLightGrid),
        .buffer(RenderNamedResourceKey.forwardPlusLightIndexList),
        .buffer(RenderNamedResourceKey.forwardPlusLightIndexCount),
        .buffer(RenderNamedResourceKey.forwardPlusClusterParams)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.baseColor)
    ]

    func execute(frame: RenderGraphFrame) {
        let sceneStart = CACurrentMediaTime()
        guard
            let baseColor = frame.resourceRegistry.texture(.baseColor),
            let baseDepth = frame.resourceRegistry.texture(.baseDepth)
        else { return }

        let depthLoad: MTLLoadAction = frame.frameContext.useDepthPrepass() ? .load : .clear
        let frameIndex = frame.frameContext.currentFrameIndex()
        let pass = RenderPassBuilder.colorDepth(color: baseColor, depth: baseDepth, depthLoadAction: depthLoad)
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(frame.engineContext.graphics.renderPipelineStates.hdrInstancedPipeline(settings: frame.frameContext.rendererSettings()))
        encoder.label = "Scene Pass"
        encoder.pushDebugGroup("Scene Pass")
        frame.profiler.sampleGpuPassBegin(.scene, encoder: encoder, frameIndex: frameIndex)
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(baseColor))
        RenderPassHelpers.withRenderPass(.main, frameContext: frame.frameContext) {
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
    let outputs: [RenderPassResourceUsage] = [
        .texture(.pickId, expectedFormat: .r32Uint),
        .texture(.pickDepth)
    ]

    func execute(frame: RenderGraphFrame) {
        // Outline relies on the pickId buffer, so keep it current while a selection is active.
        let hasSelection = frame.frameContext.rendererSettings().outlineEnabled != 0
            && RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView)
            && !frame.sceneView.selectedEntityIds.isEmpty
        let needsPickingPass = frame.engineContext.pickingSystem.hasPendingRequest() || hasSelection
        guard needsPickingPass else { return }
        guard
            let pickId = frame.resourceRegistry.texture(.pickId),
            let pickDepth = frame.resourceRegistry.texture(.pickDepth)
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
        RenderPassHelpers.withRenderPass(.picking, frameContext: frame.frameContext) {
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
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .gridColor))
    ]
    let inputs: [RenderPassResourceUsage] = [
        .texture(.baseDepth)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.gridColor)
    ]

    func execute(frame: RenderGraphFrame) {
        guard frame.frameContext.rendererSettings().gridEnabled != 0,
              RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView) else { return }
        guard let grid = frame.resourceRegistry.texture(.gridColor) else { return }
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
        let depthTexture = frame.resourceRegistry.texture(.baseDepth) ?? frame.engineContext.fallbackTextures.depth1x1
        encoder.setFragmentSamplerState(frame.engineContext.graphics.samplerStates[.LinearClampToZero], index: FragmentSamplerIndex.linearClamp)
        encoder.setFragmentTexture(depthTexture, index: PostProcessTextureIndex.depth)
        encoder.setFragmentBytes(&params, length: GridParams.stride, index: FragmentBufferIndex.gridParams)
        let settingsBuffer = frame.frameContext.uploadRendererSettings(frame.frameContext.rendererSettings())
        encoder.setFragmentBuffer(settingsBuffer.buffer, offset: settingsBuffer.offset, index: FragmentBufferIndex.rendererSettings)
        quadMesh.drawPrimitives(encoder, frameContext: frame.frameContext)
    }
}

final class DebugDrawPass: RenderGraphPass {
    let name = "DebugDrawPass"
    let gpuPass: RendererProfiler.GpuPass? = nil
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .gridColor))
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.gridColor)
    ]

    func execute(frame: RenderGraphFrame) {
        let allowDebugDraw = RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView)
            || (frame.engineContext.physicsSettings.debugDrawInPlay && !frame.sceneView.isEditorView)
        guard frame.engineContext.physicsSettings.debugDrawEnabled,
              allowDebugDraw,
              let snapshot = frame.sceneSnapshot,
              let grid = frame.resourceRegistry.texture(.gridColor) else { return }
        let debugDraw = frame.engineContext.debugDraw
        let lines = debugDraw.lines()
        let polylines = debugDraw.polylines()
        if lines.isEmpty && polylines.isEmpty {
            if frame.frameContext.rendererSettings().gridEnabled == 0 {
                let pass = RenderPassBuilder.color(texture: grid, clearColor: MTLClearColorMake(0, 0, 0, 0))
                if let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                    encoder.label = "Debug Draw Clear"
                    encoder.endEncoding()
                }
            }
            return
        }
        let sceneConstants = snapshot.sceneConstants
        let cameraPosition = SIMD3<Float>(
            sceneConstants.cameraPositionAndIBL.x,
            sceneConstants.cameraPositionAndIBL.y,
            sceneConstants.cameraPositionAndIBL.z
        )
        let thickness = max(0.0001, frame.engineContext.debugDraw.lineThickness)
        var vertices: [DebugLineVertex] = []
        vertices.reserveCapacity((lines.count + polylines.count * 2) * 6)

        @inline(__always)
        func resolveRight(lineDir: SIMD3<Float>, anchor: SIMD3<Float>) -> SIMD3<Float> {
            var viewDir = cameraPosition - anchor
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
            return simd_normalize(right)
        }

        @inline(__always)
        func appendQuad(v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>, color: SIMD4<Float>, u0: Float, u1: Float) {
            vertices.append(DebugLineVertex(position: v0, color: color, uv: SIMD2<Float>(u0, 0)))
            vertices.append(DebugLineVertex(position: v1, color: color, uv: SIMD2<Float>(u0, 1)))
            vertices.append(DebugLineVertex(position: v2, color: color, uv: SIMD2<Float>(u1, 0)))
            vertices.append(DebugLineVertex(position: v2, color: color, uv: SIMD2<Float>(u1, 0)))
            vertices.append(DebugLineVertex(position: v1, color: color, uv: SIMD2<Float>(u0, 1)))
            vertices.append(DebugLineVertex(position: v3, color: color, uv: SIMD2<Float>(u1, 1)))
        }

        for line in lines {
            let p0 = line.start
            let p1 = line.end
            let dir = p1 - p0
            let length = simd_length(dir)
            if length < 0.0001 { continue }
            let lineDir = dir / length
            let right = resolveRight(lineDir: lineDir, anchor: (p0 + p1) * 0.5)
            let offset = right * (thickness * 0.5)
            let v0 = p0 - offset
            let v1 = p0 + offset
            let v2 = p1 - offset
            let v3 = p1 + offset
            appendQuad(v0: v0, v1: v1, v2: v2, v3: v3, color: line.color, u0: 0.0, u1: 1.0)
        }

        for polyline in polylines {
            let points = polyline.points
            let pointCount = points.count
            if pointCount < 2 { continue }

            let closed = polyline.closed
            let segmentCount = closed ? pointCount : pointCount - 1
            if segmentCount <= 0 { continue }

            var segmentDirs = Array(repeating: SIMD3<Float>.zero, count: segmentCount)
            var segmentRights = Array(repeating: SIMD3<Float>.zero, count: segmentCount)
            var segmentLengths = Array(repeating: Float(0), count: segmentCount)
            for segmentIndex in 0..<segmentCount {
                let nextIndex = (segmentIndex + 1) % pointCount
                let dir = points[nextIndex] - points[segmentIndex]
                let len = simd_length(dir)
                if len < 0.0001 { continue }
                let lineDir = dir / len
                segmentDirs[segmentIndex] = lineDir
                segmentLengths[segmentIndex] = len
                segmentRights[segmentIndex] = resolveRight(lineDir: lineDir, anchor: (points[segmentIndex] + points[nextIndex]) * 0.5)
            }

            var leftOffsets = Array(repeating: SIMD3<Float>.zero, count: pointCount)
            var rightOffsets = Array(repeating: SIMD3<Float>.zero, count: pointCount)
            for pointIndex in 0..<pointCount {
                let prevSegment = (pointIndex - 1 + segmentCount) % segmentCount
                let nextSegment = pointIndex % segmentCount

                let right: SIMD3<Float>
                if !closed && pointIndex == 0 {
                    right = segmentRights[0]
                } else if !closed && pointIndex == pointCount - 1 {
                    right = segmentRights[segmentCount - 1]
                } else {
                    let rightPrev = segmentRights[prevSegment]
                    let rightNext = segmentRights[nextSegment]
                    if simd_length_squared(rightPrev) < 1e-8 {
                        right = rightNext
                    } else if simd_length_squared(rightNext) < 1e-8 {
                        right = rightPrev
                    } else {
                        var miter = rightPrev + rightNext
                        if simd_length_squared(miter) < 1e-8 {
                            right = rightNext
                            let offset = right * (thickness * 0.5)
                            leftOffsets[pointIndex] = points[pointIndex] - offset
                            rightOffsets[pointIndex] = points[pointIndex] + offset
                            continue
                        }
                        miter = simd_normalize(miter)
                        let denominator = max(0.25, abs(simd_dot(miter, rightNext)))
                        var scale = 1.0 / denominator
                        scale = min(scale, 4.0)
                        var candidate = miter * (thickness * 0.5 * scale)
                        if simd_dot(candidate, rightNext) < 0 {
                            candidate = -candidate
                        }
                        leftOffsets[pointIndex] = points[pointIndex] - candidate
                        rightOffsets[pointIndex] = points[pointIndex] + candidate
                        continue
                    }
                }

                let offset = right * (thickness * 0.5)
                leftOffsets[pointIndex] = points[pointIndex] - offset
                rightOffsets[pointIndex] = points[pointIndex] + offset
            }

            var uByPoint = Array(repeating: Float(0.5), count: pointCount)
            if !closed {
                let total = segmentLengths.reduce(0, +)
                if total > 0.0001 {
                    var accum: Float = 0
                    uByPoint[0] = 0
                    for segmentIndex in 0..<segmentCount {
                        let next = segmentIndex + 1
                        accum += segmentLengths[segmentIndex]
                        uByPoint[next] = min(1.0, accum / total)
                    }
                }
            }

            for segmentIndex in 0..<segmentCount {
                if segmentLengths[segmentIndex] < 0.0001 { continue }
                let nextIndex = (segmentIndex + 1) % pointCount
                appendQuad(
                    v0: leftOffsets[segmentIndex],
                    v1: rightOffsets[segmentIndex],
                    v2: leftOffsets[nextIndex],
                    v3: rightOffsets[nextIndex],
                    color: polyline.color,
                    u0: uByPoint[segmentIndex],
                    u1: uByPoint[nextIndex]
                )
            }
        }
        if vertices.isEmpty { return }
        guard let buffer = frame.engineContext.device.makeBuffer(bytes: vertices,
                                                                 length: DebugLineVertex.stride(vertices.count),
                                                                 options: [.storageModeShared]) else { return }
        let size = RenderPassHelpers.textureSize(grid)
        let pass = frame.frameContext.rendererSettings().gridEnabled != 0
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
    let inputs: [RenderPassResourceUsage] = [
        .texture(.pickId, expectedFormat: .r32Uint)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.outlineMask, expectedFormat: .r8Unorm)
    ]

    func execute(frame: RenderGraphFrame) {
        OutlineSystem.encodeSelectionOutline(frame: frame)
    }
}

final class BloomExtractPass: RenderGraphPass {
    let name = "BloomExtractPass"
    let gpuPass: RendererProfiler.GpuPass? = .bloomExtract
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .bloomPing))
    ]
    let inputs: [RenderPassResourceUsage] = [
        .texture(.baseColor)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.bloomPing)
    ]

    func execute(frame: RenderGraphFrame) {
        let settings = frame.frameContext.rendererSettings()
        if settings.bloomEnabled == 0 {
            if let ping = frame.resourceRegistry.texture(.bloomPing),
               let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: ping, level: 0)) {
                encoder.label = "Bloom Clear"
                encoder.endEncoding()
            }
            return
        }
        guard
            let sceneTex = frame.resourceRegistry.texture(.baseColor),
            let ping = frame.resourceRegistry.texture(.bloomPing),
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
    let allowedDoubleWriteOutputs: Set<RenderResourceHandle> = [
        .texture(RenderTextureHandle(key: .bloomPing)),
        .texture(RenderTextureHandle(key: .bloomPong))
    ]
    let inputs: [RenderPassResourceUsage] = [
        .texture(.bloomPing),
        .texture(.bloomPong)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.bloomPing),
        .texture(.bloomPong)
    ]

    func execute(frame: RenderGraphFrame) {
        let settings = frame.frameContext.rendererSettings()
        if settings.bloomEnabled == 0 { return }
        guard
            let ping = frame.resourceRegistry.texture(.bloomPing),
            let pong = frame.resourceRegistry.texture(.bloomPong),
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

        var blurTotal: Double = 0
        var downsampleTotal: Double = 0

        let frameIndex = frame.frameContext.currentFrameIndex()
        var didSampleBegin = false
        var didSampleEnd = false

        // Build bloom pyramid from extracted mip0.
        if mipCount > 1 {
            for mip in 1..<mipCount {
                let sourceMip = mip - 1
                let size = mipSize(ping, mip)
                var params = settings
                params.bloomMipLevel = Float(sourceMip)

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
            }
        }

        // Dual-filter upsample: fold low mips back into higher mips.
        if mipCount > 1 {
            for mip in stride(from: mipCount - 2, through: 0, by: -1) {
                let size = mipSize(ping, mip)
                var params = settings
                let blurStart = CACurrentMediaTime()
                params.bloomMipLevel = Float(mip)
                guard let enc = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: pong, level: mip)) else { return }
                RenderPassHelpers.setViewport(enc, size)
                if !didSampleBegin {
                    frame.profiler.sampleGpuPassBegin(.bloomBlur, encoder: enc, frameIndex: frameIndex)
                    didSampleBegin = true
                }
                let upsample = FullscreenPass(
                    pipeline: .BloomBlurH,
                    label: "Bloom Upsample \(mip)",
                    sampler: .LinearClampToZero,
                    useSampler: true,
                    texture0: ping,
                    useTexture0: true,
                    texture1: ping,
                    useTexture1: true,
                    outlineMask: nil,
                    useOutlineMask: false,
                    depth: nil,
                    useDepth: false,
                    grid: nil,
                    useGrid: false,
                    settings: params
                )
                upsample.encode(into: enc, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
                if mip == 0, !didSampleEnd {
                    frame.profiler.sampleGpuPassEnd(.bloomBlur, encoder: enc, frameIndex: frameIndex)
                    didSampleEnd = true
                }
                enc.endEncoding()

                // Persist current upsample result back into ping for the next higher mip.
                guard let blit = frame.commandBuffer.makeBlitCommandEncoder() else { return }
                blit.label = "Bloom Upsample Copy \(mip)"
                let copyWidth = max(1, ping.width >> mip)
                let copyHeight = max(1, ping.height >> mip)
                blit.copy(
                    from: pong,
                    sourceSlice: 0,
                    sourceLevel: mip,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
                    to: ping,
                    destinationSlice: 0,
                    destinationLevel: mip,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blit.endEncoding()

                if mipCount == 2 && mip == 0 && !didSampleEnd {
                    didSampleEnd = true
                }
                blurTotal += CACurrentMediaTime() - blurStart
            }
        } else if !didSampleEnd {
            didSampleEnd = true
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
    let inputs: [RenderPassResourceUsage] = [
        .texture(.baseColor),
        .texture(.bloomPing),
        .texture(.outlineMask),
        .texture(.gridColor)
    ]
    let outputs: [RenderPassResourceUsage] = [
        .texture(.finalColor)
    ]

    func execute(frame: RenderGraphFrame) {
        guard
            let baseColor = frame.resourceRegistry.texture(.baseColor),
            let bloom = frame.resourceRegistry.texture(.bloomPing),
            let outline = frame.resourceRegistry.texture(.outlineMask),
            let grid = frame.resourceRegistry.texture(.gridColor),
            let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh),
            let finalColor = frame.resourceRegistry.texture(.finalColor)
        else { return }

        let compositeStart = CACurrentMediaTime()
        let frameIndex = frame.frameContext.currentFrameIndex()
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: RenderPassBuilder.color(texture: finalColor)) else { return }
        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(finalColor))
        frame.profiler.sampleGpuPassBegin(.finalComposite, encoder: encoder, frameIndex: frameIndex)
        let showEditorOverlays = RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView)
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
            settings: frame.frameContext.rendererSettings()
        )
        pass.encode(into: encoder, quad: quadMesh, frameContext: frame.frameContext, graphics: frame.engineContext.graphics)
        encoder.endEncoding()
        frame.profiler.sampleGpuPassEnd(.finalComposite, encoder: encoder, frameIndex: frameIndex)
        frame.profiler.record(.composite, seconds: CACurrentMediaTime() - compositeStart)
    }
}
