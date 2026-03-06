/// SceneRenderer.swift
/// Provides a single render entry point for scene rendering.
/// Created by Kaden Cringle.

import MetalKit
import QuartzCore
import simd

public struct RenderFrameSnapshot {
    public struct Renderable {
        let entity: Entity
        let meshHandle: AssetHandle?
        let meshRenderer: MeshRendererComponent
        let inheritedMaterialHandle: AssetHandle?
        let worldTransform: TransformComponent
    }

    let sceneKey: ObjectIdentifier
    let frameToken: UInt64
    let signature: UInt64
    let sceneConstants: SceneConstants
    let activeSkyLight: SkyLightComponent?
    let directionalLights: [LightData]
    let localLights: [LightData]
    let directionalShadowLightDirection: SIMD3<Float>?
    let animationPayload: AnimationSnapshotPayload?
    let renderables: [Renderable]
}

public enum SceneRenderer {
    private struct FrameCacheKey: Hashable {
        let sceneKey: ObjectIdentifier
        let frameToken: UInt64
        let snapshotSignature: UInt64
        let viewSignature: UInt64
        let cullingConfigSignature: UInt64
        let stateRevision: UInt64
        let assetStateRevision: UInt64
    }

    private struct FrameCacheEntry {
        let key: FrameCacheKey
        let snapshot: RenderFrameSnapshot
        let result: RenderBatchResult?
    }

    private static var frameCache: [FrameCacheKey: FrameCacheEntry] = [:]
    private struct SnapshotPreparationKey: Hashable {
        let sceneKey: ObjectIdentifier
        let frameToken: UInt64
        let viewSignature: UInt64
    }

    #if DEBUG
    private static var preparedSnapshotFrameToken: UInt64 = 0
    private static var preparedSnapshotKeys: Set<SnapshotPreparationKey> = []
    #else
    private static var lastMissingSnapshotFrameToken: UInt64 = 0
    private static var missingSnapshotLogKeys: Set<SnapshotPreparationKey> = []
    #endif

    #if DEBUG
    private static var didInstanceSanityCheck = false
    #endif
    @discardableResult
    public static func render(scene: EngineScene, view: SceneView, context: RenderContext, frameContext: RendererFrameContext) -> RenderOutputs {
        frameContext.setViewContext(
            RenderViewContext(
                viewId: view.viewId,
                viewportSize: view.viewportSize,
                layerFilterMask: view.layerMask,
                depthPrepassEnabled: view.depthPrepassEnabled,
                debugFlags: view.debugFlags,
                showEditorOverlays: view.isEditorView
            )
        )
        prepareRenderFrameSnapshot(scene: scene, frameContext: frameContext)
        if let encoder = context.renderEncoder {
            renderScene(into: encoder, scene: scene, frameContext: frameContext)
        }
        return RenderOutputs(color: context.colorTarget,
                             depth: context.depthTarget,
                             pickingId: context.idTarget)
    }

    @discardableResult
    public static func render(scene: EngineScene, view: SceneView, context: RenderContext, engineContext: EngineContext) -> RenderOutputs {
        let storage = RendererFrameContextStorage(engineContext: engineContext)
        let frameContext = storage.beginFrame()
        return render(scene: scene, view: view, context: context, frameContext: frameContext)
    }

    static func renderScene(into encoder: MTLRenderCommandEncoder, scene: EngineScene, frameContext: RendererFrameContext) {
        encoder.pushDebugGroup("Rendering Scene \(scene.name)...")
        guard let snapshot = currentFrameSnapshot(scene: scene, frameContext: frameContext) else {
            encoder.popDebugGroup()
            return
        }
        // Reserved seam for future skinning data consumption.
        _ = snapshot.animationPayload
        prepareLightingInputs(snapshot: snapshot, frameContext: frameContext)
        syncIBLTextures(snapshot: snapshot, frameContext: frameContext)
        let sceneConstantsBuffer = resolvedSceneConstantsBuffer(snapshot: snapshot, frameContext: frameContext)
        switch frameContext.currentRenderPass() {
        case .main:
            bindRendererSettings(encoder, settings: frameContext.rendererSettings(), frameContext: frameContext)
            bindShadowResources(encoder, frameContext: frameContext)
            bindLightingInputs(encoder, frameContext: frameContext)
            renderSky(encoder, snapshot: snapshot, frameContext: frameContext, sceneConstantsBuffer: sceneConstantsBuffer)
            renderMeshes(encoder, snapshot: snapshot, pass: .main, frameContext: frameContext, sceneConstantsBuffer: sceneConstantsBuffer)
        case .shadow:
            renderMeshes(encoder, snapshot: snapshot, pass: .shadow, frameContext: frameContext, sceneConstantsBuffer: sceneConstantsBuffer)
        case .picking:
            renderMeshes(encoder, snapshot: snapshot, pass: .picking, frameContext: frameContext, sceneConstantsBuffer: sceneConstantsBuffer)
        case .depthPrepass:
            renderMeshes(encoder, snapshot: snapshot, pass: .depthPrepass, frameContext: frameContext, sceneConstantsBuffer: sceneConstantsBuffer)
        }
        encoder.popDebugGroup()
    }

    static func renderPreview(encoder: MTLRenderCommandEncoder,
                              snapshot: RenderFrameSnapshot,
                              camera: CameraComponent,
                              worldTransform: TransformComponent,
                              viewportSize: SIMD2<Float>,
                              frameContext: RendererFrameContext) {
        guard viewportSize.x > 1, viewportSize.y > 1 else { return }
        let previousPass = frameContext.currentRenderPass()
        let previousUsePrepass = frameContext.useDepthPrepass()
        let aspect = max(0.01, viewportSize.x / viewportSize.y)
        var previewConstants = snapshot.sceneConstants
        previewConstants.viewMatrix = viewMatrix(from: worldTransform)
        previewConstants.skyViewMatrix = previewConstants.viewMatrix
        previewConstants.skyViewMatrix[3][0] = 0
        previewConstants.skyViewMatrix[3][1] = 0
        previewConstants.skyViewMatrix[3][2] = 0
        previewConstants.projectionMatrix = projectionMatrix(from: camera, aspectRatio: aspect)
        previewConstants.inverseProjectionMatrix = simd_inverse(previewConstants.projectionMatrix)
        previewConstants.cameraPositionAndIBL = SIMD4<Float>(worldTransform.position, snapshot.sceneConstants.cameraPositionAndIBL.w)
        let previewConstantsBuffer = frameContext.makeSceneConstantsBuffer(
            previewConstants,
            label: "SceneConstants.Preview"
        )
        frameContext.setCurrentRenderPass(.main)
        frameContext.setUseDepthPrepass(false)
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: 0,
                                        width: Double(viewportSize.x),
                                        height: Double(viewportSize.y),
                                        znear: 0,
                                        zfar: 1))
        prepareLightingInputs(snapshot: snapshot, frameContext: frameContext)
        syncIBLTextures(snapshot: snapshot, frameContext: frameContext)
        bindRendererSettings(encoder, settings: frameContext.rendererSettings(), frameContext: frameContext)
        bindShadowResources(encoder, frameContext: frameContext)
        bindLightingInputs(encoder, frameContext: frameContext)
        renderSky(encoder, snapshot: snapshot, frameContext: frameContext, sceneConstantsBuffer: previewConstantsBuffer)
        renderMeshes(encoder, snapshot: snapshot, pass: .main, frameContext: frameContext, sceneConstantsBuffer: previewConstantsBuffer)
        frameContext.setUseDepthPrepass(previousUsePrepass)
        frameContext.setCurrentRenderPass(previousPass)
    }

    private static func renderSky(_ encoder: MTLRenderCommandEncoder,
                                  snapshot: RenderFrameSnapshot,
                                  frameContext: RendererFrameContext,
                                  sceneConstantsBuffer: MTLBuffer? = nil) {
        guard let sky = snapshot.activeSkyLight, sky.enabled else { return }
        let engineContext = frameContext.engineContext()
        guard let mesh = engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        bindSceneConstants(encoder, snapshot: snapshot, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        encoder.setTriangleFillMode(engineContext.preferences.isWireframeEnabled ? .lines : .fill)
        encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.Skybox])
        encoder.setDepthStencilState(engineContext.graphics.depthStencilStates[.LessEqualNoWrite])
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        var modelConstants = ModelConstants()
        modelConstants.modelMatrix = matrix_identity_float4x4
        encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
        let envTexture = frameContext.iblTextures().environment
            ?? engineContext.assets.texture(handle: BuiltinAssets.environmentCubemap)
            ?? engineContext.fallbackTextures.blackCubemap
        encoder.setFragmentSamplerState(engineContext.graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
        encoder.setFragmentTexture(envTexture, index: FragmentTextureIndex.skybox)
        mesh.drawPrimitives(encoder, frameContext: frameContext)
    }

    private static func syncIBLTextures(snapshot: RenderFrameSnapshot, frameContext: RendererFrameContext) {
        let engineContext = frameContext.engineContext()
        let fallback = engineContext.fallbackTextures
        let sky = snapshot.activeSkyLight
        let envHandle = sky?.iblEnvironmentHandle ?? BuiltinAssets.environmentCubemap
        let irrHandle = sky?.iblIrradianceHandle ?? BuiltinAssets.irradianceCubemap
        let preHandle = sky?.iblPrefilteredHandle ?? BuiltinAssets.prefilteredCubemap
        let brdfHandle = sky?.iblBrdfHandle ?? BuiltinAssets.brdfLut
        let env = engineContext.assets.texture(handle: envHandle) ?? fallback.blackCubemap
        let irr = engineContext.assets.texture(handle: irrHandle) ?? fallback.blackCubemap
        let pre = engineContext.assets.texture(handle: preHandle) ?? fallback.blackCubemap
        let brdf = engineContext.assets.texture(handle: brdfHandle) ?? fallback.brdfLut
        let needsRebuild = sky?.needsRebuild ?? true
        let hasValidIBL = (sky?.enabled ?? false)
            && !needsRebuild
            && !fallback.isFallbackTexture(irr)
            && !fallback.isFallbackTexture(pre)
            && !fallback.isFallbackTexture(brdf)
        frameContext.updateIBLTextures(
            environment: env,
            irradiance: irr,
            prefiltered: pre,
            brdfLut: brdf
        )
        frameContext.setIBLReady(hasValidIBL)
    }

    private static func renderMeshes(_ encoder: MTLRenderCommandEncoder,
                                     snapshot: RenderFrameSnapshot,
                                     pass: RenderPassType,
                                     frameContext: RendererFrameContext,
                                     sceneConstantsBuffer: MTLBuffer? = nil,
                                     shadowCullVolume: ShadowCullVolume? = nil) {
        let batchResult = currentBatchResult(snapshot: snapshot, frameContext: frameContext)
        guard let instanceBuffer = batchResult.instanceBuffer else { return }
        if let bonePaletteBuffer = batchResult.bonePaletteBuffer {
            encoder.setVertexBuffer(bonePaletteBuffer, offset: 0, index: VertexBufferIndex.bonePalette)
        } else {
            var identityPalette = matrix_identity_float4x4
            encoder.setVertexBytes(&identityPalette,
                                   length: MemoryLayout<matrix_float4x4>.stride,
                                   index: VertexBufferIndex.bonePalette)
        }
        bindSceneConstants(encoder, snapshot: snapshot, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        let instanceStride = InstanceData.stride
        for batch in batchResult.batches {
            let instanceCount = batch.instanceRange.count
            if instanceCount == 0 { continue }
            MC_ASSERT(batch.instanceRange.upperBound <= batchResult.instances.count, "Batch instance range out of bounds.")
            applyPerDrawState(encoder, pass: pass, cullMode: batch.bindings.cullMode, frameContext: frameContext)
            if pass == .shadow, let shadowCullVolume {
                if !batch.bindings.passKey.castsShadows { continue }
                var visibleStart = -1
                for instanceIndex in batch.instanceRange {
                    MC_ASSERT(instanceIndex < batchResult.instanceBounds.count, "Batch bounds range out of bounds.")
                    let bounds = batchResult.instanceBounds[instanceIndex]
                    let isVisible = intersects(bounds: bounds, volume: shadowCullVolume)
                    if isVisible {
                        if visibleStart < 0 {
                            visibleStart = instanceIndex
                        }
                    } else if visibleStart >= 0 {
                        encodeShadowDrawRange(
                            encoder,
                            snapshot: snapshot,
                            batch: batch,
                            batchResult: batchResult,
                            instanceBuffer: instanceBuffer,
                            startIndex: visibleStart,
                            endIndex: instanceIndex,
                            instanceStride: instanceStride,
                            sceneConstantsBuffer: sceneConstantsBuffer,
                            frameContext: frameContext
                        )
                        visibleStart = -1
                    }
                }
                if visibleStart >= 0 {
                    encodeShadowDrawRange(
                        encoder,
                        snapshot: snapshot,
                        batch: batch,
                        batchResult: batchResult,
                        instanceBuffer: instanceBuffer,
                        startIndex: visibleStart,
                        endIndex: batch.instanceRange.upperBound,
                        instanceStride: instanceStride,
                        sceneConstantsBuffer: sceneConstantsBuffer,
                        frameContext: frameContext
                    )
                }
                continue
            }

            let instanceOffset = batch.instanceRange.lowerBound * instanceStride
            switch pass {
            case .depthPrepass:
                encodeDepthPrepass(
                    encoder,
                    snapshot: snapshot,
                    batch: batch,
                    batchResult: batchResult,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount,
                    sceneConstantsBuffer: sceneConstantsBuffer,
                    frameContext: frameContext
                )
            case .shadow:
                if !batch.bindings.passKey.castsShadows { continue }
                encodeShadowPass(
                    encoder,
                    snapshot: snapshot,
                    batch: batch,
                    batchResult: batchResult,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount,
                    sceneConstantsBuffer: sceneConstantsBuffer,
                    frameContext: frameContext
                )
            case .picking:
                encodePicking(
                    encoder,
                    snapshot: snapshot,
                    batch: batch,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount,
                    sceneConstantsBuffer: sceneConstantsBuffer,
                    frameContext: frameContext
                )
            case .main:
                encodeMainPass(
                    encoder,
                    snapshot: snapshot,
                    batch: batch,
                    batchResult: batchResult,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount,
                    sceneConstantsBuffer: sceneConstantsBuffer,
                    frameContext: frameContext
                )
            }
        }
    }

    private static func applyPerDrawState(_ encoder: MTLRenderCommandEncoder,
                                          pass: RenderPassType,
                                          cullMode: MTLCullMode,
                                          frameContext: RendererFrameContext) {
        let engineContext = frameContext.engineContext()
        encoder.setTriangleFillMode(engineContext.preferences.isWireframeEnabled ? .lines : .fill)
        let usePrepass = frameContext.useDepthPrepass() && pass == .main
        if pass == .depthPrepass {
            encoder.setDepthStencilState(engineContext.graphics.depthStencilStates[.LessEqual])
        } else if usePrepass {
            // Shared vertex shader keeps clip-space depth identical, so strict equality is safe.
            encoder.setDepthStencilState(engineContext.graphics.depthStencilStates[.EqualNoWrite])
        } else {
            encoder.setDepthStencilState(engineContext.graphics.depthStencilStates[.Less])
        }
        if pass == .shadow {
            // Default to front-face culling to reduce self-shadowing (acne).
            // Preserve double-sided materials by honoring .none from material bindings.
            let isDoubleSided = (cullMode == .none)
            encoder.setCullMode(isDoubleSided ? .none : .front)
        } else {
            encoder.setCullMode(cullMode)
        }
        encoder.setFrontFacing(.counterClockwise)
        switch pass {
        case .depthPrepass:
            // Depth prepass should match main pass depth without bias.
            encoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        case .shadow:
            // Shadow bias is handled in shader to avoid double-biasing.
            encoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        default:
            encoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        }
    }

    private static func encodeDepthPrepass(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        let pipeline = pipelineState(for: .depthPrepass, key: batch.bindings.passKey, frameContext: frameContext)
        let useAlphaClip = batch.bindings.passKey.alphaMode == .alphaClip
        encodeMeshBatch(
            encoder,
            snapshot: snapshot,
            batch: batch,
            batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: instanceCount,
            pipelineState: pipeline,
            bindings: useAlphaClip ? batch.bindings : nil,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func encodeShadowPass(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        let pipeline = pipelineState(for: .shadow, key: batch.bindings.passKey, frameContext: frameContext)
        let useAlphaClip = batch.bindings.passKey.alphaMode == .alphaClip
        encodeMeshBatch(
            encoder,
            snapshot: snapshot,
            batch: batch,
            batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: instanceCount,
            pipelineState: pipeline,
            bindings: useAlphaClip ? batch.bindings : nil,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func encodePicking(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        let engineContext = frameContext.engineContext()
        encoder.setRenderPipelineState(engineContext.graphics.renderPipelineStates[.PickID])
        bindSceneConstants(encoder, snapshot: snapshot, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        bindInstanceBuffer(encoder, buffer: instanceBuffer, offset: instanceOffset)
        batch.mesh.setInstanceCount(instanceCount)
        drawMesh(encoder, mesh: batch.mesh, bindings: nil, frameContext: frameContext)
    }

    private static func encodeMainPass(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        let pipelineState = pipelineState(for: .main, key: batch.bindings.passKey, frameContext: frameContext)
        encodeMeshBatch(
            encoder,
            snapshot: snapshot,
            batch: batch,
            batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: instanceCount,
            pipelineState: pipelineState,
            bindings: batch.bindings,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func encodeMeshBatch(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        _ batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        pipelineState: MTLRenderPipelineState,
        bindings: MaterialBindings?,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        // Instanced-only pipeline keeps a single vertex path for every draw, preventing PSO + clip-space divergence.
        encoder.setRenderPipelineState(pipelineState)
        bindSceneConstants(encoder, snapshot: snapshot, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        bindInstanceBuffer(encoder, buffer: instanceBuffer, offset: instanceOffset)
        assertInstanceBindings(instanceBuffer: instanceBuffer, instanceOffset: instanceOffset, instanceCount: instanceCount)
        batch.mesh.setInstanceCount(instanceCount)
        drawMesh(encoder, mesh: batch.mesh, bindings: bindings, frameContext: frameContext)
    }

    private static func drawMesh(_ encoder: MTLRenderCommandEncoder, mesh: MCMesh, bindings: MaterialBindings?, frameContext: RendererFrameContext) {
        mesh.drawPrimitives(
            encoder,
            frameContext: frameContext,
            material: bindings?.materialOverride,
            submeshMaterialHandles: bindings?.submeshMaterialHandles,
            albedoMapHandle: bindings?.albedoMapHandle,
            normalMapHandle: bindings?.normalMapHandle,
            metallicMapHandle: bindings?.metallicMapHandle,
            roughnessMapHandle: bindings?.roughnessMapHandle,
            mrMapHandle: bindings?.mrMapHandle,
            ormMapHandle: bindings?.ormMapHandle,
            aoMapHandle: bindings?.aoMapHandle,
            emissiveMapHandle: bindings?.emissiveMapHandle,
            useEmbeddedMaterial: false
        )
    }

    private static func resolvedSceneConstantsBuffer(snapshot: RenderFrameSnapshot, frameContext: RendererFrameContext) -> MTLBuffer {
        var constants = snapshot.sceneConstants
        if !frameContext.iblReady() {
            constants.cameraPositionAndIBL.w = 0.0
        }
        let buffer = frameContext.uploadSceneConstants(constants)
#if DEBUG
        MC_ASSERT(SceneConstants.stride == SceneConstants.expectedMetalStride, "SceneConstants stride mismatch. Keep Swift and Metal layouts in sync.")
#endif
        MC_ASSERT(buffer.length >= SceneConstants.stride, "SceneConstants buffer too small.")
        return buffer
    }

    private static func bindSceneConstants(_ encoder: MTLRenderCommandEncoder,
                                           snapshot: RenderFrameSnapshot,
                                           frameContext: RendererFrameContext,
                                           overrideBuffer: MTLBuffer? = nil) {
        if let overrideBuffer {
            MC_ASSERT(overrideBuffer.length >= SceneConstants.stride, "SceneConstants override buffer too small.")
            encoder.setVertexBuffer(overrideBuffer, offset: 0, index: VertexBufferIndex.sceneConstants)
            return
        }
        let buffer = resolvedSceneConstantsBuffer(snapshot: snapshot, frameContext: frameContext)
        encoder.setVertexBuffer(buffer, offset: 0, index: VertexBufferIndex.sceneConstants)
    }

    private static func bindInstanceBuffer(_ encoder: MTLRenderCommandEncoder, buffer: MTLBuffer, offset: Int) {
        encoder.setVertexBuffer(buffer, offset: offset, index: VertexBufferIndex.instances)
    }

    private static func bindRendererSettings(_ encoder: MTLRenderCommandEncoder, settings: RendererSettings, frameContext: RendererFrameContext) {
        var resolvedSettings = settings
        if !frameContext.iblReady() {
            resolvedSettings.iblEnabled = 0
            resolvedSettings.iblIntensity = 0.0
        }
        if !frameContext.isForwardPlusAllowed() {
            resolvedSettings.setPerfFlag(.forwardPlusEnabled, enabled: false)
        }
        let settingsBuffer = frameContext.uploadRendererSettings(resolvedSettings)
#if DEBUG
        MC_ASSERT(RendererSettings.stride == RendererSettings.expectedMetalStride, "RendererSettings stride mismatch. Keep Swift and Metal layouts in sync.")
        MC_ASSERT(settingsBuffer.buffer.length >= RendererSettings.expectedMetalStride, "RendererSettings buffer too small.")
#endif
        encoder.setFragmentBuffer(settingsBuffer.buffer, offset: settingsBuffer.offset, index: FragmentBufferIndex.rendererSettings)
    }

    private static func bindShadowResources(_ encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        let shadowBuffer = frameContext.shadowConstantsBuffer()
        encoder.setFragmentBuffer(shadowBuffer, offset: 0, index: FragmentBufferIndex.shadowConstants)
        let fallback = frameContext.engineContext().fallbackTextures
        let shadowTexture = frameContext.shadowMapTexture() ?? fallback.shadowMap
        encoder.setFragmentTexture(shadowTexture, index: FragmentTextureIndex.shadowMap)
        encoder.setFragmentTexture(shadowTexture, index: FragmentTextureIndex.shadowMapSample)
        encoder.setFragmentSamplerState(frameContext.engineContext().graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
        encoder.setFragmentSamplerState(frameContext.engineContext().graphics.samplerStates[.ShadowCompare], index: FragmentSamplerIndex.shadowCompare)
        encoder.setFragmentSamplerState(frameContext.engineContext().graphics.samplerStates[.ShadowDepth], index: FragmentSamplerIndex.shadowDepth)

    }

    private static func prepareLightingInputs(snapshot: RenderFrameSnapshot, frameContext: RendererFrameContext) {
        let localLightBuffers = frameContext.uploadLocalLightData(snapshot.localLights)
        let directionalLightBuffers = frameContext.uploadDirectionalLightData(snapshot.directionalLights)
#if DEBUG
        MC_ASSERT(localLightBuffers.countBuffer !== directionalLightBuffers.countBuffer
                    && localLightBuffers.dataBuffer !== directionalLightBuffers.dataBuffer,
                  "Local and directional light streams must not share buffers.")
#endif
        let registry = frameContext.renderResourceRegistry()
        let allowForwardPlus = frameContext.isForwardPlusAllowed()
        let inputs = LightingInputs(
            localLightCountBuffer: localLightBuffers.countBuffer,
            localLightDataBuffer: localLightBuffers.dataBuffer,
            directionalLightCountBuffer: directionalLightBuffers.countBuffer,
            directionalLightDataBuffer: directionalLightBuffers.dataBuffer,
            lightGridBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusLightGrid) : nil,
            lightIndexListBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusLightIndexList) : nil,
            lightIndexCountBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusLightIndexCount) : nil,
            clusterParamsBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusClusterParams) : nil,
            tileLightGridBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusTileLightGrid) : nil,
            tileParamsBuffer: allowForwardPlus ? registry?.buffer(RenderNamedResourceKey.forwardPlusTileParams) : nil
        )
        frameContext.setLightingInputs(inputs)
    }

    private static func bindLightingInputs(_ encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        guard let inputs = frameContext.lightingInputs() else { return }
        encoder.setFragmentBuffer(inputs.localLightCountBuffer, offset: 0, index: FragmentBufferIndex.lightCount)
        encoder.setFragmentBuffer(inputs.localLightDataBuffer, offset: 0, index: FragmentBufferIndex.lightData)
        encoder.setFragmentBuffer(inputs.directionalLightCountBuffer, offset: 0, index: FragmentBufferIndex.directionalLightCount)
        encoder.setFragmentBuffer(inputs.directionalLightDataBuffer, offset: 0, index: FragmentBufferIndex.directionalLightData)
        encoder.setFragmentBuffer(inputs.lightGridBuffer, offset: 0, index: FragmentBufferIndex.lightGrid)
        encoder.setFragmentBuffer(inputs.lightIndexListBuffer, offset: 0, index: FragmentBufferIndex.lightIndexList)
        encoder.setFragmentBuffer(inputs.lightIndexCountBuffer, offset: 0, index: FragmentBufferIndex.lightIndexCount)
        encoder.setFragmentBuffer(inputs.clusterParamsBuffer, offset: 0, index: FragmentBufferIndex.lightClusterParams)
        encoder.setFragmentBuffer(inputs.tileLightGridBuffer, offset: 0, index: FragmentBufferIndex.tileLightGrid)
        encoder.setFragmentBuffer(inputs.tileParamsBuffer, offset: 0, index: FragmentBufferIndex.tileParams)
    }

    private static func pipelineState(for pass: RenderPassType, key: MaterialPassKey, frameContext: RendererFrameContext) -> MTLRenderPipelineState {
        let engineContext = frameContext.engineContext()
        switch pass {
        case .main:
            return engineContext.graphics.renderPipelineStates.hdrInstancedPipeline(settings: frameContext.rendererSettings())
        case .depthPrepass:
            if key.alphaMode == .alphaClip {
                return engineContext.graphics.renderPipelineStates[.DepthPrepassAlphaInstanced]
            }
            return engineContext.graphics.renderPipelineStates[.DepthPrepassInstanced]
        case .shadow:
            if key.alphaMode == .alphaClip {
                return engineContext.graphics.renderPipelineStates[.ShadowAlphaInstanced]
            }
            return engineContext.graphics.renderPipelineStates[.DepthPrepassInstanced]
        case .picking:
            return engineContext.graphics.renderPipelineStates[.PickID]
        }
    }


    static func renderShadowCasters(into encoder: MTLRenderCommandEncoder,
                                    snapshot: RenderFrameSnapshot,
                                    frameContext: RendererFrameContext,
                                    sceneConstantsBuffer: MTLBuffer?,
                                    shadowCullVolume: ShadowCullVolume? = nil) {
        renderMeshes(
            encoder,
            snapshot: snapshot,
            pass: .shadow,
            frameContext: frameContext,
            sceneConstantsBuffer: sceneConstantsBuffer,
            shadowCullVolume: shadowCullVolume
        )
    }

    static func prepareRenderFrameSnapshot(scene: EngineScene, frameContext: RendererFrameContext) {
        let snapshot = scene.makeRenderFrameSnapshot(
            frameToken: frameContext.currentFrameCounter(),
            layerFilterMask: frameContext.layerFilterMask()
        )
        frameContext.setRenderFrameSnapshot(snapshot)
        let key = FrameCacheKey(
            sceneKey: snapshot.sceneKey,
            frameToken: snapshot.frameToken,
            snapshotSignature: snapshot.signature,
            viewSignature: frameContext.viewContext().cacheSignature(),
            cullingConfigSignature: cullingConfigSignature(frameContext: frameContext),
            stateRevision: frameContext.rendererStateRevision(),
            assetStateRevision: frameContext.assetStateRevision()
        )
        if frameCache[key] == nil {
            frameCache[key] = FrameCacheEntry(key: key, snapshot: snapshot, result: nil)
            trimFrameCache(keepingFrameToken: key.frameToken)
        }
        markSnapshotPrepared(
            SnapshotPreparationKey(
                sceneKey: snapshot.sceneKey,
                frameToken: snapshot.frameToken,
                viewSignature: key.viewSignature
            )
        )
    }


    private static func assertInstanceBindings(instanceBuffer: MTLBuffer, instanceOffset: Int, instanceCount: Int) {
        let requiredBytes = InstanceData.stride * instanceCount
        MC_ASSERT(instanceBuffer.length >= instanceOffset + requiredBytes, "Instance buffer too small for draw.")
        MC_ASSERT(instanceOffset % 16 == 0, "Instance buffer offset should be 16-byte aligned.")
    }

    private struct MaterialBindings {
        var materialHandle: AssetHandle?
        var submeshMaterialHandles: [AssetHandle?]?
        var materialOverride: MetalCupMaterial?
        var albedoMapHandle: AssetHandle?
        var normalMapHandle: AssetHandle?
        var metallicMapHandle: AssetHandle?
        var roughnessMapHandle: AssetHandle?
        var mrMapHandle: AssetHandle?
        var ormMapHandle: AssetHandle?
        var aoMapHandle: AssetHandle?
        var emissiveMapHandle: AssetHandle?
        var cullMode: MTLCullMode
        var passKey: MaterialPassKey
    }

    private struct RenderItem {
        let entity: Entity
        let meshHandle: AssetHandle
        let mesh: MCMesh
        let transform: TransformComponent
        let bonePaletteRange: AnimationSnapshotPayload.BonePaletteRange?
        let bindings: MaterialBindings
        let bounds: InstanceBounds
    }

    private struct MaterialBatchKey: Hashable {
        let materialHandle: AssetHandle?
        let overrideHash: Int
    }

    private struct RenderBatchKey: Hashable {
        let meshHandle: AssetHandle
        let materialKey: MaterialBatchKey
        let pipeline: RenderPipelineStateType
        let cullModeKey: Int
        let alphaModeKey: Int32
        let unlitKey: Int32
        let castsShadowsKey: Int32
        let receivesShadowsKey: Int32
    }

    private struct RenderBatchBuilder {
        var mesh: MCMesh
        var bindings: MaterialBindings
        var instances: [InstanceData]
        var bounds: [InstanceBounds]
    }

    private struct RenderBatch {
        let mesh: MCMesh
        let bindings: MaterialBindings
        let instanceRange: Range<Int>
    }

    private struct RenderBatchResult {
        let instances: [InstanceData]
        let instanceBounds: [InstanceBounds]
        let batches: [RenderBatch]
        let instanceBuffer: MTLBuffer?
        let bonePaletteBuffer: MTLBuffer?
    }

    struct ShadowCullVolume {
        let lightView: matrix_float4x4
        let halfExtent: Float
        let nearZ: Float
        let farZ: Float
    }

    private struct InstanceBounds {
        var center: SIMD3<Float>
        var radius: Float
    }

    private static func currentFrameSnapshot(scene: EngineScene, frameContext: RendererFrameContext) -> RenderFrameSnapshot? {
        let viewSignature = frameContext.viewContext().cacheSignature()
        let expectedKey = SnapshotPreparationKey(
            sceneKey: ObjectIdentifier(scene),
            frameToken: frameContext.currentFrameCounter(),
            viewSignature: viewSignature
        )
        guard let resolvedSnapshot = frameContext.renderFrameSnapshot(),
              resolvedSnapshot.sceneKey == expectedKey.sceneKey,
              resolvedSnapshot.frameToken == expectedKey.frameToken
        else {
#if DEBUG
            fatalError("SceneRenderer requires a prebuilt frame snapshot before render. Missing snapshot for viewSignature=\(viewSignature) frameToken=\(frameContext.currentFrameCounter()). Prepare via SceneRenderer.prepareRenderFrameSnapshot(...) before graph execution.")
#else
            logMissingSnapshotIfNeeded(expectedKey)
            return nil
#endif
        }
#if DEBUG
        guard isSnapshotPrepared(expectedKey) else {
            fatalError("SceneRenderer render started without snapshot preparation tracking for viewSignature=\(viewSignature) frameToken=\(frameContext.currentFrameCounter()). Ensure prepareRenderFrameSnapshot(...) is called once per view per frame before rendering.")
        }
#endif

        let key = FrameCacheKey(
            sceneKey: resolvedSnapshot.sceneKey,
            frameToken: resolvedSnapshot.frameToken,
            snapshotSignature: resolvedSnapshot.signature,
            viewSignature: viewSignature,
            cullingConfigSignature: cullingConfigSignature(frameContext: frameContext),
            stateRevision: frameContext.rendererStateRevision(),
            assetStateRevision: frameContext.assetStateRevision()
        )
        if let cached = frameCache[key] {
            return cached.snapshot
        }
        frameCache[key] = FrameCacheEntry(key: key, snapshot: resolvedSnapshot, result: nil)
        trimFrameCache(keepingFrameToken: key.frameToken)
        return resolvedSnapshot
    }

    private static func markSnapshotPrepared(_ key: SnapshotPreparationKey) {
#if DEBUG
        if preparedSnapshotFrameToken != key.frameToken {
            preparedSnapshotFrameToken = key.frameToken
            preparedSnapshotKeys.removeAll(keepingCapacity: true)
        }
        preparedSnapshotKeys.insert(key)
#endif
    }

    private static func isSnapshotPrepared(_ key: SnapshotPreparationKey) -> Bool {
#if DEBUG
        if preparedSnapshotFrameToken != key.frameToken {
            return false
        }
        return preparedSnapshotKeys.contains(key)
#else
        true
#endif
    }

    private static func logMissingSnapshotIfNeeded(_ key: SnapshotPreparationKey) {
#if !DEBUG
        if lastMissingSnapshotFrameToken != key.frameToken {
            lastMissingSnapshotFrameToken = key.frameToken
            missingSnapshotLogKeys.removeAll(keepingCapacity: true)
        }
        guard !missingSnapshotLogKeys.contains(key) else { return }
        missingSnapshotLogKeys.insert(key)
        EngineLoggerContext.log(
            "Skipping render: missing prepared frame snapshot for viewSignature=\(key.viewSignature) frameToken=\(key.frameToken).",
            level: .debug,
            category: .renderer
        )
#endif
    }

    private static func currentBatchResult(snapshot: RenderFrameSnapshot,
                                           frameContext: RendererFrameContext) -> RenderBatchResult {
        let key = FrameCacheKey(
            sceneKey: snapshot.sceneKey,
            frameToken: snapshot.frameToken,
            snapshotSignature: snapshot.signature,
            viewSignature: frameContext.viewContext().cacheSignature(),
            cullingConfigSignature: cullingConfigSignature(frameContext: frameContext),
            stateRevision: frameContext.rendererStateRevision(),
            assetStateRevision: frameContext.assetStateRevision()
        )
        if let cached = frameCache[key], let result = cached.result {
            return result
        }
        let result = buildRenderBatches(snapshot: snapshot, frameContext: frameContext)
        frameCache[key] = FrameCacheEntry(key: key, snapshot: snapshot, result: result)
        trimFrameCache(keepingFrameToken: snapshot.frameToken)
        return result
    }

    private static func trimFrameCache(keepingFrameToken frameToken: UInt64) {
        if frameCache.count <= 64 { return }
        frameCache = frameCache.filter { $0.key.frameToken == frameToken }
    }

    private static func cullingConfigSignature(frameContext: RendererFrameContext) -> UInt64 {
        let viewContext = frameContext.viewContext()
        let viewportWidth = UInt32(max(Int(viewContext.viewportSize.x), 1))
        let viewportHeight = UInt32(max(Int(viewContext.viewportSize.y), 1))
        let tileCountX = max(1, (viewportWidth + ForwardPlusConfig.tileSizeX - 1) / ForwardPlusConfig.tileSizeX)
        let tileCountY = max(1, (viewportHeight + ForwardPlusConfig.tileSizeY - 1) / ForwardPlusConfig.tileSizeY)
        let forwardPlusEnabled = frameContext.rendererSettings().hasPerfFlag(.forwardPlusEnabled)

        var hasher = Hasher()
        hasher.combine(ForwardPlusConfig.configVersion)
        hasher.combine(ForwardPlusConfig.abiVersion)
        hasher.combine(ForwardPlusConfig.tileSizeX)
        hasher.combine(ForwardPlusConfig.tileSizeY)
        hasher.combine(ForwardPlusConfig.zSliceCount)
        hasher.combine(ForwardPlusConfig.maxLightsPerCluster)
        hasher.combine(tileCountX)
        hasher.combine(tileCountY)
        hasher.combine(forwardPlusEnabled)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private static func buildRenderItems(snapshot: RenderFrameSnapshot,
                                         engineContext: EngineContext) -> [RenderItem] {
        var renderItems: [RenderItem] = []
        renderItems.reserveCapacity(snapshot.renderables.count)
        let skinnedEntries: [AnimationSnapshotPayload.SkinnedEntry] = snapshot.animationPayload?.skinnedEntries ?? []
        let paletteRangesByEntity: [Entity: AnimationSnapshotPayload.BonePaletteRange] = Dictionary(uniqueKeysWithValues: skinnedEntries.compactMap { entry in
            guard let range = entry.bonePaletteRange else { return nil }
            return (entry.entity, range)
        })

        for renderable in snapshot.renderables {
            guard let meshHandle = renderable.meshHandle,
                  let mesh = engineContext.assets.mesh(handle: meshHandle) else { continue }
            let transform = renderable.worldTransform
            let bindings = resolveMaterialBindings(renderable: renderable, engineContext: engineContext)
            let worldBounds = worldBounds(for: mesh, transform: transform)
            renderItems.append(RenderItem(
                entity: renderable.entity,
                meshHandle: meshHandle,
                mesh: mesh,
                transform: transform,
                bonePaletteRange: paletteRangesByEntity[renderable.entity],
                bindings: bindings,
                bounds: worldBounds
            ))
        }

        return renderItems
    }

    private static func buildRenderBatches(snapshot: RenderFrameSnapshot, frameContext: RendererFrameContext) -> RenderBatchResult {
        let engineContext = frameContext.engineContext()
        let profiler = engineContext.renderer?.profiler
        let buildStart = CACurrentMediaTime()
        var builders: [RenderBatchKey: RenderBatchBuilder] = [:]
        var uniqueMeshes = Set<AssetHandle>()
        let items = buildRenderItems(snapshot: snapshot, engineContext: engineContext)
        engineContext.pickingSystem.resetMapping()

        for item in items {
            let bindings = item.bindings
            let materialKey = makeMaterialKey(bindings: bindings)
            let key = RenderBatchKey(
                meshHandle: item.meshHandle,
                materialKey: materialKey,
                pipeline: .HDRInstanced,
                cullModeKey: bindings.cullMode == .none ? 0 : 1,
                alphaModeKey: bindings.passKey.alphaMode.rawValue,
                unlitKey: bindings.passKey.isUnlit ? 1 : 0,
                castsShadowsKey: bindings.passKey.castsShadows ? 1 : 0,
                receivesShadowsKey: bindings.passKey.receivesShadows ? 1 : 0
            )
            var builder = builders[key] ?? RenderBatchBuilder(mesh: item.mesh, bindings: bindings, instances: [], bounds: [])
            let pickId = engineContext.pickingSystem.assignPickId(for: item.entity)
            var instance = InstanceData()
            instance.modelMatrix = modelMatrix(for: item.transform)
            instance.entityID = pickId
            if let range = item.bonePaletteRange, range.count > 0 {
                instance.bonePaletteOffset = UInt32(range.startIndex)
                instance.bonePaletteCount = UInt32(range.count)
                instance.skinningFlags = 1
            }
            builder.instances.append(instance)
            builder.bounds.append(item.bounds)
            builders[key] = builder
            uniqueMeshes.insert(item.meshHandle)
        }

        var instances: [InstanceData] = []
        var instanceBounds: [InstanceBounds] = []
        instances.reserveCapacity(items.count)
        instanceBounds.reserveCapacity(items.count)
        var batches: [RenderBatch] = []
        batches.reserveCapacity(builders.count)
        var instancedDrawCalls = 0

        for builder in builders.values {
            let start = instances.count
            instances.append(contentsOf: builder.instances)
            instanceBounds.append(contentsOf: builder.bounds)
            let end = instances.count
            batches.append(RenderBatch(mesh: builder.mesh, bindings: builder.bindings, instanceRange: start..<end))
            instancedDrawCalls += 1
        }

        let instanceBuffer = frameContext.uploadInstanceData(instances)
        let bonePaletteBuffer = frameContext.uploadBonePaletteData(snapshot.animationPayload?.bonePaletteMatrices ?? [])

#if DEBUG
        if !didInstanceSanityCheck, let instanceBuffer, let first = instances.first {
            didInstanceSanityCheck = true
            let raw = instanceBuffer.contents().assumingMemoryBound(to: Float.self)
            let reconstructed = matrix_float4x4(columns: (
                SIMD4<Float>(raw[0], raw[1], raw[2], raw[3]),
                SIMD4<Float>(raw[4], raw[5], raw[6], raw[7]),
                SIMD4<Float>(raw[8], raw[9], raw[10], raw[11]),
                SIMD4<Float>(raw[12], raw[13], raw[14], raw[15])
            ))
            let expected = first.modelMatrix
            var maxDelta: Float = 0.0
            for c in 0..<4 {
                for r in 0..<4 {
                    let delta = abs(reconstructed[c][r] - expected[c][r])
                    if delta > maxDelta { maxDelta = delta }
                }
            }
            MC_ASSERT(maxDelta < 1e-4, "Instance matrix upload mismatch (column-major). Max delta: \(maxDelta).")
        }
#endif

        let stats = RendererBatchStats(
            uniqueMeshes: uniqueMeshes.count,
            batches: batches.count,
            instancedDrawCalls: instancedDrawCalls,
            nonInstancedDrawCalls: 0
        )
        frameContext.updateBatchStats(stats)

        if let profiler {
            profiler.record(.renderBatches, seconds: CACurrentMediaTime() - buildStart)
        }
        return RenderBatchResult(instances: instances,
                                 instanceBounds: instanceBounds,
                                 batches: batches,
                                 instanceBuffer: instanceBuffer,
                                 bonePaletteBuffer: bonePaletteBuffer)
    }

    private static func resolveMaterialBindings(renderable: RenderFrameSnapshot.Renderable,
                                                engineContext: EngineContext) -> MaterialBindings {
        let meshRenderer = renderable.meshRenderer
        let materialHandle = meshRenderer.materialHandle ?? renderable.inheritedMaterialHandle
        let submeshMaterialHandles = meshRenderer.submeshMaterialHandles
        var materialOverride = meshRenderer.material
        var albedoMapHandle = meshRenderer.albedoMapHandle
        var normalMapHandle = meshRenderer.normalMapHandle
        var metallicMapHandle = meshRenderer.metallicMapHandle
        var roughnessMapHandle = meshRenderer.roughnessMapHandle
        var mrMapHandle = meshRenderer.mrMapHandle
        var ormMapHandle = meshRenderer.ormMapHandle
        var aoMapHandle = meshRenderer.aoMapHandle
        var emissiveMapHandle = meshRenderer.emissiveMapHandle
        // Cull mode is derived from material state only (never from entity naming hacks).
        var passKey = MaterialPassKey(
            alphaMode: .opaque,
            doubleSided: false,
            isUnlit: false,
            castsShadows: true,
            receivesShadows: true
        )

        let usesSubmeshMaterials = submeshMaterialHandles?.contains(where: { $0 != nil }) == true
        if !usesSubmeshMaterials,
           let materialHandle,
           let materialAsset = engineContext.assets.material(handle: materialHandle) {
            materialOverride = materialAsset.buildMetalMaterial(database: engineContext.assetDatabase)
            albedoMapHandle = materialAsset.textures.baseColor
            normalMapHandle = materialAsset.textures.normal
            metallicMapHandle = materialAsset.textures.metallic
            roughnessMapHandle = materialAsset.textures.roughness
            mrMapHandle = materialAsset.textures.metalRoughness
            ormMapHandle = materialAsset.textures.orm
            aoMapHandle = materialAsset.textures.ao
            emissiveMapHandle = materialAsset.textures.emissive
            if (materialOverride?.flags ?? 0) & MetalCupMaterialFlags.isDoubleSided.rawValue != 0 {
                passKey.doubleSided = true
            }
            switch materialAsset.alphaMode {
            case .opaque:
                passKey.alphaMode = .opaque
            case .masked:
                passKey.alphaMode = .alphaClip
            case .blended:
                passKey.alphaMode = .alphaBlend
            }
            passKey.isUnlit = materialAsset.unlit
        }
        if let overrideFlags = materialOverride?.flags {
            if (overrideFlags & MetalCupMaterialFlags.alphaMasked.rawValue) != 0 {
                passKey.alphaMode = .alphaClip
            } else if (overrideFlags & MetalCupMaterialFlags.alphaBlended.rawValue) != 0 {
                passKey.alphaMode = .alphaBlend
            }
            if (overrideFlags & MetalCupMaterialFlags.isDoubleSided.rawValue) != 0 {
                passKey.doubleSided = true
            }
            if (overrideFlags & MetalCupMaterialFlags.isUnlit.rawValue) != 0 {
                passKey.isUnlit = true
            }
        }
        if usesSubmeshMaterials, let handles = submeshMaterialHandles {
            for handle in handles {
                guard let handle,
                      let submeshMaterial = engineContext.assets.material(handle: handle) else { continue }
                if submeshMaterial.doubleSided {
                    passKey.doubleSided = true
                }
                if submeshMaterial.alphaMode == .masked {
                    passKey.alphaMode = .alphaClip
                } else if submeshMaterial.alphaMode == .blended, passKey.alphaMode != .alphaClip {
                    passKey.alphaMode = .alphaBlend
                }
                passKey.isUnlit = passKey.isUnlit || submeshMaterial.unlit
            }
        }
        if let normalHandle = normalMapHandle,
           let metadata = engineContext.assetDatabase?.metadata(for: normalHandle) {
            if metadata.importSettings["flipNormalY"] == "true"
                || AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
                var material = materialOverride ?? MetalCupMaterial()
                material.flags |= MetalCupMaterialFlags.normalFlipY.rawValue
                materialOverride = material
            }
        }

        let cullMode: MTLCullMode = passKey.doubleSided ? .none : .back
        return MaterialBindings(
            materialHandle: materialHandle,
            submeshMaterialHandles: submeshMaterialHandles,
            materialOverride: materialOverride,
            albedoMapHandle: albedoMapHandle,
            normalMapHandle: normalMapHandle,
            metallicMapHandle: metallicMapHandle,
            roughnessMapHandle: roughnessMapHandle,
            mrMapHandle: mrMapHandle,
            ormMapHandle: ormMapHandle,
            aoMapHandle: aoMapHandle,
            emissiveMapHandle: emissiveMapHandle,
            cullMode: cullMode,
            passKey: passKey
        )
    }

    private static func makeMaterialKey(bindings: MaterialBindings) -> MaterialBatchKey {
        if let submeshHandles = bindings.submeshMaterialHandles,
           submeshHandles.contains(where: { $0 != nil }) {
            var hasher = Hasher()
            for handle in submeshHandles {
                hasher.combine(handle?.rawValue)
            }
            return MaterialBatchKey(materialHandle: nil, overrideHash: hasher.finalize())
        }
        if let materialHandle = bindings.materialHandle {
            return MaterialBatchKey(materialHandle: materialHandle, overrideHash: 0)
        }
        var material = bindings.materialOverride ?? MetalCupMaterial()
        let materialHash = hashBytes(of: &material)
        var hasher = Hasher()
        hasher.combine(materialHash)
        hasher.combine(bindings.albedoMapHandle?.rawValue)
        hasher.combine(bindings.normalMapHandle?.rawValue)
        hasher.combine(bindings.metallicMapHandle?.rawValue)
        hasher.combine(bindings.roughnessMapHandle?.rawValue)
        hasher.combine(bindings.mrMapHandle?.rawValue)
        hasher.combine(bindings.ormMapHandle?.rawValue)
        hasher.combine(bindings.aoMapHandle?.rawValue)
        hasher.combine(bindings.emissiveMapHandle?.rawValue)
        return MaterialBatchKey(materialHandle: nil, overrideHash: hasher.finalize())
    }

    private static func hashBytes<T>(of value: inout T) -> UInt64 {
        return withUnsafeBytes(of: &value) { bytes in
            var hash: UInt64 = 1469598103934665603
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            return hash
        }
    }

    private static func encodeShadowDrawRange(
        _ encoder: MTLRenderCommandEncoder,
        snapshot: RenderFrameSnapshot,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        startIndex: Int,
        endIndex: Int,
        instanceStride: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        let visibleCount = endIndex - startIndex
        if visibleCount <= 0 { return }
        let instanceOffset = startIndex * instanceStride
        encodeShadowPass(
            encoder,
            snapshot: snapshot,
            batch: batch,
            batchResult: batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: visibleCount,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func worldBounds(for mesh: MCMesh, transform: TransformComponent) -> InstanceBounds {
        let centerWS4 = TransformMath.makeMatrix(
            position: transform.position,
            rotation: transform.rotation,
            scale: transform.scale
        ) * SIMD4<Float>(mesh.boundsCenter, 1.0)
        let center = SIMD3<Float>(centerWS4.x, centerWS4.y, centerWS4.z)
        let absScale = SIMD3<Float>(abs(transform.scale.x), abs(transform.scale.y), abs(transform.scale.z))
        let maxScale = max(absScale.x, max(absScale.y, absScale.z))
        return InstanceBounds(
            center: center,
            radius: max(0.001, mesh.boundsRadius * max(maxScale, 0.001))
        )
    }

    private static func intersects(bounds: InstanceBounds, volume: ShadowCullVolume) -> Bool {
        let centerLS4 = volume.lightView * SIMD4<Float>(bounds.center, 1.0)
        if !isFinite(centerLS4) { return true }
        let center = SIMD3<Float>(centerLS4.x, centerLS4.y, centerLS4.z)
        let r = bounds.radius
        if center.x + r < -volume.halfExtent || center.x - r > volume.halfExtent { return false }
        if center.y + r < -volume.halfExtent || center.y - r > volume.halfExtent { return false }
        if center.z + r < volume.farZ || center.z - r > volume.nearZ { return false }
        return true
    }

    private static func modelMatrix(for transform: TransformComponent) -> matrix_float4x4 {
#if DEBUG
        MC_ASSERT(isFinite(transform.position) && isFinite(transform.rotation) && isFinite(transform.scale),
                  "Transform contains non-finite values (NaN/inf).")
#endif
        return TransformMath.makeMatrix(position: transform.position,
                                        rotation: transform.rotation,
                                        scale: transform.scale)
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    public static func cameraMatrices(scene: EngineScene) -> (view: matrix_float4x4, projection: matrix_float4x4) {
        let constants = scene.getSceneConstants()
        return (view: constants.viewMatrix, projection: constants.projectionMatrix)
    }

    public static func cameraPosition(scene: EngineScene) -> SIMD3<Float> {
        let constants = scene.getSceneConstants()
        return SIMD3<Float>(
            constants.cameraPositionAndIBL.x,
            constants.cameraPositionAndIBL.y,
            constants.cameraPositionAndIBL.z
        )
    }

    public static func gridParams(scene: EngineScene) -> GridParams {
        let constants = scene.getSceneConstants()
        var params = GridParams()
        let viewProjection = constants.projectionMatrix * constants.viewMatrix
        params.inverseViewProjection = simd_inverse(viewProjection)
        params.cameraPosition = SIMD3<Float>(
            constants.cameraPositionAndIBL.x,
            constants.cameraPositionAndIBL.y,
            constants.cameraPositionAndIBL.z
        )
        return params
    }

    static func viewMatrix(from transform: TransformComponent) -> matrix_float4x4 {
        return TransformMath.makeViewMatrix(position: transform.position,
                                            rotation: transform.rotation)
    }

    static func projectionMatrix(from camera: CameraComponent, aspectRatio: Float) -> matrix_float4x4 {
        let nearPlane = max(0.01, camera.nearPlane)
        let farPlane = max(nearPlane + 0.01, camera.farPlane)
        switch camera.projectionType {
        case .perspective:
            return matrix_float4x4.perspective(
                fovDegrees: camera.fovDegrees,
                aspectRatio: aspectRatio,
                near: nearPlane,
                far: farPlane
            )
        case .orthographic:
            let size = max(0.01, camera.orthoSize)
            return matrix_float4x4.orthographic(
                size: size,
                aspectRatio: aspectRatio,
                near: nearPlane,
                far: farPlane
            )
        }
    }
}
    private enum MaterialAlphaModeKey: Int32, Hashable {
        case opaque = 0
        case alphaClip = 1
        case alphaBlend = 2
    }

    private struct MaterialPassKey: Hashable {
        var alphaMode: MaterialAlphaModeKey
        var doubleSided: Bool
        var isUnlit: Bool
        var castsShadows: Bool
        var receivesShadows: Bool
    }
