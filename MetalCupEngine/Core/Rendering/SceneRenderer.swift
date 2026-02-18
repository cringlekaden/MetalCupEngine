/// SceneRenderer.swift
/// Provides a single render entry point for scene rendering.
/// Created by Kaden Cringle.

import MetalKit
import simd

public enum SceneRenderer {
    @discardableResult
    public static func render(scene: EngineScene, view: SceneView, context: RenderContext, frameContext: RendererFrameContext) -> RenderOutputs {
        if let encoder = context.renderEncoder {
            renderScene(into: encoder, scene: scene, frameContext: frameContext)
        }
        return RenderOutputs(color: context.colorTarget,
                             depth: context.depthTarget,
                             pickingId: context.idTarget)
    }

    @discardableResult
    public static func render(scene: EngineScene, view: SceneView, context: RenderContext) -> RenderOutputs {
        let storage = RendererFrameContextStorage()
        let frameContext = storage.beginFrame()
        return render(scene: scene, view: view, context: context, frameContext: frameContext)
    }

    static func renderScene(into encoder: MTLRenderCommandEncoder, scene: EngineScene, frameContext: RendererFrameContext) {
        encoder.pushDebugGroup("Rendering Scene \(scene.name)...")
        bindSceneConstants(encoder, scene: scene, frameContext: frameContext)
        switch Renderer.currentRenderPass {
        case .main:
            syncIBLTextures(scene: scene, frameContext: frameContext)
            bindRendererSettings(encoder, settings: Renderer.settings, frameContext: frameContext)
            scene.getLightManager().setLightData(encoder, frameContext: frameContext)
            renderSky(encoder, scene: scene, frameContext: frameContext)
            renderMeshes(encoder, scene: scene, pass: .main, frameContext: frameContext)
        case .picking:
            renderMeshes(encoder, scene: scene, pass: .picking, frameContext: frameContext)
        case .depthPrepass:
            renderMeshes(encoder, scene: scene, pass: .depthPrepass, frameContext: frameContext)
        }
        encoder.popDebugGroup()
    }

    static func renderPreview(encoder: MTLRenderCommandEncoder,
                              scene: EngineScene,
                              cameraEntity: Entity,
                              viewportSize: SIMD2<Float>,
                              frameContext: RendererFrameContext) {
        guard let transform = scene.ecs.get(TransformComponent.self, for: cameraEntity),
              let camera = scene.ecs.get(CameraComponent.self, for: cameraEntity),
              viewportSize.x > 1, viewportSize.y > 1 else { return }
        let previousPass = Renderer.currentRenderPass
        let previousUsePrepass = Renderer.useDepthPrepass
        let aspect = max(0.01, viewportSize.x / viewportSize.y)
        let sceneConstants = scene.getSceneConstants()
        var previewConstants = sceneConstants
        previewConstants.viewMatrix = viewMatrix(from: transform)
        previewConstants.skyViewMatrix = previewConstants.viewMatrix
        previewConstants.skyViewMatrix[3][0] = 0
        previewConstants.skyViewMatrix[3][1] = 0
        previewConstants.skyViewMatrix[3][2] = 0
        previewConstants.projectionMatrix = projectionMatrix(from: camera, aspectRatio: aspect)
        previewConstants.cameraPositionAndIBL = SIMD4<Float>(transform.position, sceneConstants.cameraPositionAndIBL.w)
        guard let previewConstantsBuffer = frameContext.makeSceneConstantsBuffer(
            previewConstants,
            label: "SceneConstants.Preview"
        ) else { return }
        Renderer.currentRenderPass = .main
        Renderer.useDepthPrepass = false
        encoder.setViewport(MTLViewport(originX: 0,
                                        originY: 0,
                                        width: Double(viewportSize.x),
                                        height: Double(viewportSize.y),
                                        znear: 0,
                                        zfar: 1))
        syncIBLTextures(scene: scene, frameContext: frameContext)
        bindRendererSettings(encoder, settings: Renderer.settings, frameContext: frameContext)
        scene.getLightManager().setLightData(encoder, frameContext: frameContext)
        renderSky(encoder, scene: scene, frameContext: frameContext, sceneConstantsBuffer: previewConstantsBuffer)
        renderMeshes(encoder, scene: scene, pass: .main, frameContext: frameContext, sceneConstantsBuffer: previewConstantsBuffer)
        Renderer.useDepthPrepass = previousUsePrepass
        Renderer.currentRenderPass = previousPass
    }

    static func renderPreview(encoder: MTLRenderCommandEncoder,
                              scene: EngineScene,
                              cameraEntity: Entity,
                              viewportSize: SIMD2<Float>) {
        let storage = RendererFrameContextStorage()
        let frameContext = storage.beginFrame()
        renderPreview(
            encoder: encoder,
            scene: scene,
            cameraEntity: cameraEntity,
            viewportSize: viewportSize,
            frameContext: frameContext
        )
    }

    private static func renderSky(_ encoder: MTLRenderCommandEncoder,
                                  scene: EngineScene,
                                  frameContext: RendererFrameContext,
                                  sceneConstantsBuffer: MTLBuffer? = nil) {
        var renderedSky = false
        scene.ecs.viewSkyLights { _, sky in
            if renderedSky { return }
            if !sky.enabled { return }
            renderedSky = true
            guard let mesh = AssetManager.mesh(handle: BuiltinAssets.skyboxMesh) else { return }
            bindSceneConstants(encoder, scene: scene, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
            encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            encoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var modelConstants = ModelConstants()
            modelConstants.modelMatrix = matrix_identity_float4x4
            encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
            let envTexture = frameContext.iblTextures().environment
                ?? AssetManager.texture(handle: BuiltinAssets.environmentCubemap)
            encoder.setFragmentTexture(envTexture, index: FragmentTextureIndex.skybox)
            mesh.drawPrimitives(encoder, frameContext: frameContext)
        }
    }

    private static func syncIBLTextures(scene: EngineScene, frameContext: RendererFrameContext) {
        let sky = scene.ecs.activeSkyLight()?.1
        let envHandle = sky?.iblEnvironmentHandle ?? BuiltinAssets.environmentCubemap
        let irrHandle = sky?.iblIrradianceHandle ?? BuiltinAssets.irradianceCubemap
        let preHandle = sky?.iblPrefilteredHandle ?? BuiltinAssets.prefilteredCubemap
        let brdfHandle = sky?.iblBrdfHandle ?? BuiltinAssets.brdfLut
        let env = AssetManager.texture(handle: envHandle)
        let irr = AssetManager.texture(handle: irrHandle)
        let pre = AssetManager.texture(handle: preHandle)
        let brdf = AssetManager.texture(handle: brdfHandle)
        frameContext.updateIBLTextures(
            environment: env,
            irradiance: irr,
            prefiltered: pre,
            brdfLut: brdf
        )
    }

    private static func renderMeshes(_ encoder: MTLRenderCommandEncoder,
                                     scene: EngineScene,
                                     pass: RenderPassType,
                                     frameContext: RendererFrameContext,
                                     sceneConstantsBuffer: MTLBuffer? = nil) {
        let batchResult = currentBatchResult(scene: scene, frameContext: frameContext)
        guard let instanceBuffer = batchResult.instanceBuffer else { return }
        bindSceneConstants(encoder, scene: scene, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        let instanceStride = InstanceData.stride
        for batch in batchResult.batches {
            let instanceCount = batch.instanceRange.count
            if instanceCount == 0 { continue }
            MC_ASSERT(batch.instanceRange.upperBound <= batchResult.instances.count, "Batch instance range out of bounds.")
            let instanceOffset = batch.instanceRange.lowerBound * instanceStride
            applyPerDrawState(encoder, pass: pass, cullMode: batch.bindings.cullMode)
            switch pass {
            case .depthPrepass:
                encodeDepthPrepass(
                    encoder,
                    scene: scene,
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
                    scene: scene,
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
                    scene: scene,
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

    private static func applyPerDrawState(_ encoder: MTLRenderCommandEncoder, pass: RenderPassType, cullMode: MTLCullMode) {
        encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        let usePrepass = Renderer.useDepthPrepass && pass == .main
        encoder.setDepthStencilState(Graphics.DepthStencilStates[usePrepass ? .LessEqualNoWrite : .Less])
        encoder.setCullMode(cullMode)
        encoder.setFrontFacing(.counterClockwise)
        if pass == .depthPrepass {
            encoder.setDepthBias(0.0005, slopeScale: 1.0, clamp: 0.0)
        } else {
            encoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        }
    }

    private static func encodeDepthPrepass(
        _ encoder: MTLRenderCommandEncoder,
        scene: EngineScene,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        encodeMeshBatch(
            encoder,
            scene: scene,
            batch: batch,
            batchResult: batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: instanceCount,
            instancedPipeline: .DepthPrepassInstanced,
            singlePipeline: .DepthPrepass,
            bindings: nil,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func encodePicking(
        _ encoder: MTLRenderCommandEncoder,
        scene: EngineScene,
        batch: RenderBatch,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.PickID])
        bindSceneConstants(encoder, scene: scene, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        bindInstanceBuffer(encoder, buffer: instanceBuffer, offset: instanceOffset)
        batch.mesh.setInstanceCount(instanceCount)
        drawMesh(encoder, mesh: batch.mesh, bindings: nil, frameContext: frameContext)
    }

    private static func encodeMainPass(
        _ encoder: MTLRenderCommandEncoder,
        scene: EngineScene,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        encodeMeshBatch(
            encoder,
            scene: scene,
            batch: batch,
            batchResult: batchResult,
            instanceBuffer: instanceBuffer,
            instanceOffset: instanceOffset,
            instanceCount: instanceCount,
            instancedPipeline: .HDRInstanced,
            singlePipeline: .HDRBasic,
            bindings: batch.bindings,
            sceneConstantsBuffer: sceneConstantsBuffer,
            frameContext: frameContext
        )
    }

    private static func encodeMeshBatch(
        _ encoder: MTLRenderCommandEncoder,
        scene: EngineScene,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int,
        instancedPipeline: RenderPipelineStateType,
        singlePipeline: RenderPipelineStateType,
        bindings: MaterialBindings?,
        sceneConstantsBuffer: MTLBuffer?,
        frameContext: RendererFrameContext
    ) {
        if instanceCount > 1 {
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[instancedPipeline])
            bindSceneConstants(encoder, scene: scene, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
            bindInstanceBuffer(encoder, buffer: instanceBuffer, offset: instanceOffset)
            assertInstanceBindings(instanceBuffer: instanceBuffer, instanceOffset: instanceOffset, instanceCount: instanceCount)
            batch.mesh.setInstanceCount(instanceCount)
            drawMesh(encoder, mesh: batch.mesh, bindings: bindings, frameContext: frameContext)
            return
        }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[singlePipeline])
        let instanceIndex = batch.instanceRange.lowerBound
        guard instanceIndex < batchResult.instances.count else { return }
        bindSceneConstants(encoder, scene: scene, frameContext: frameContext, overrideBuffer: sceneConstantsBuffer)
        bindModelConstants(encoder, modelMatrix: batchResult.instances[instanceIndex].modelMatrix)
        batch.mesh.setInstanceCount(1)
        drawMesh(encoder, mesh: batch.mesh, bindings: bindings, frameContext: frameContext)
    }

    private static func drawMesh(_ encoder: MTLRenderCommandEncoder, mesh: MCMesh, bindings: MaterialBindings?, frameContext: RendererFrameContext) {
        mesh.drawPrimitives(
            encoder,
            frameContext: frameContext,
            material: bindings?.materialOverride,
            albedoMapHandle: bindings?.albedoMapHandle,
            normalMapHandle: bindings?.normalMapHandle,
            metallicMapHandle: bindings?.metallicMapHandle,
            roughnessMapHandle: bindings?.roughnessMapHandle,
            mrMapHandle: bindings?.mrMapHandle,
            aoMapHandle: bindings?.aoMapHandle,
            emissiveMapHandle: bindings?.emissiveMapHandle,
            useEmbeddedMaterial: false
        )
    }

    private static func bindSceneConstants(_ encoder: MTLRenderCommandEncoder,
                                           scene: EngineScene,
                                           frameContext: RendererFrameContext,
                                           overrideBuffer: MTLBuffer? = nil) {
        if let overrideBuffer {
            MC_ASSERT(overrideBuffer.length >= SceneConstants.stride, "SceneConstants override buffer too small.")
            encoder.setVertexBuffer(overrideBuffer, offset: 0, index: VertexBufferIndex.sceneConstants)
            return
        }
        let constants = scene.getSceneConstants()
        guard let buffer = frameContext.uploadSceneConstants(constants) else { return }
        MC_ASSERT(buffer.length >= SceneConstants.stride, "SceneConstants buffer too small.")
        encoder.setVertexBuffer(buffer, offset: 0, index: VertexBufferIndex.sceneConstants)
    }

    private static func bindModelConstants(_ encoder: MTLRenderCommandEncoder, modelMatrix: simd_float4x4) {
        var modelConstants = ModelConstants()
        modelConstants.modelMatrix = modelMatrix
        encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
    }

    private static func bindInstanceBuffer(_ encoder: MTLRenderCommandEncoder, buffer: MTLBuffer, offset: Int) {
        encoder.setVertexBuffer(buffer, offset: offset, index: VertexBufferIndex.instances)
    }

    private static func bindRendererSettings(_ encoder: MTLRenderCommandEncoder, settings: RendererSettings, frameContext: RendererFrameContext) {
        guard let buffer = frameContext.uploadRendererSettings(settings) else { return }
        encoder.setFragmentBuffer(buffer, offset: 0, index: FragmentBufferIndex.rendererSettings)
    }


    private static func assertInstanceBindings(instanceBuffer: MTLBuffer, instanceOffset: Int, instanceCount: Int) {
        let requiredBytes = InstanceData.stride * instanceCount
        MC_ASSERT(instanceBuffer.length >= instanceOffset + requiredBytes, "Instance buffer too small for draw.")
        MC_ASSERT(instanceOffset % 16 == 0, "Instance buffer offset should be 16-byte aligned.")
    }

    private struct MaterialBindings {
        var materialHandle: AssetHandle?
        var materialOverride: MetalCupMaterial?
        var albedoMapHandle: AssetHandle?
        var normalMapHandle: AssetHandle?
        var metallicMapHandle: AssetHandle?
        var roughnessMapHandle: AssetHandle?
        var mrMapHandle: AssetHandle?
        var aoMapHandle: AssetHandle?
        var emissiveMapHandle: AssetHandle?
        var cullMode: MTLCullMode
    }

    private struct RenderItem {
        let entity: Entity
        let meshHandle: AssetHandle
        let mesh: MCMesh
        let transform: TransformComponent
        let bindings: MaterialBindings
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
    }

    private struct RenderBatchBuilder {
        var mesh: MCMesh
        var bindings: MaterialBindings
        var instances: [InstanceData]
    }

    private struct RenderBatch {
        let mesh: MCMesh
        let bindings: MaterialBindings
        let instanceRange: Range<Int>
    }

    private struct RenderBatchResult {
        let instances: [InstanceData]
        let batches: [RenderBatch]
        let instanceBuffer: MTLBuffer?
    }

    private static func currentBatchResult(scene: EngineScene, frameContext: RendererFrameContext) -> RenderBatchResult {
        let frameToken = frameContext.currentFrameCounter()
        if scene.getCachedBatchFrameToken() == frameToken,
           let cached = scene.getCachedBatchResult() as? RenderBatchResult {
            return cached
        }
        let result = buildRenderBatches(scene: scene, frameContext: frameContext)
        scene.setCachedBatchFrameToken(frameToken)
        scene.setCachedBatchResult(result)
        return result
    }

    private static func buildRenderItems(scene: EngineScene) -> [RenderItem] {
        let items = scene.ecs.viewTransformMeshRendererArray()
        var renderItems: [RenderItem] = []
        renderItems.reserveCapacity(items.count)

        for (entity, transform, meshRenderer) in items {
            guard let meshHandle = meshRenderer.meshHandle,
                  let mesh = AssetManager.mesh(handle: meshHandle) else { continue }
            let layer = scene.ecs.get(LayerComponent.self, for: entity)?.index ?? LayerCatalog.defaultLayerIndex
            if !Renderer.layerFilterMask.contains(layerIndex: layer) {
                continue
            }
            let bindings = resolveMaterialBindings(scene: scene, entity: entity, meshRenderer: meshRenderer)
            renderItems.append(RenderItem(
                entity: entity,
                meshHandle: meshHandle,
                mesh: mesh,
                transform: transform,
                bindings: bindings
            ))
        }

        return renderItems
    }

    private static func buildRenderBatches(scene: EngineScene, frameContext: RendererFrameContext) -> RenderBatchResult {
        var builders: [RenderBatchKey: RenderBatchBuilder] = [:]
        var uniqueMeshes = Set<AssetHandle>()
        let items = buildRenderItems(scene: scene)
        PickingSystem.resetMapping()

        for item in items {
            let bindings = item.bindings
            let materialKey = makeMaterialKey(bindings: bindings)
            let key = RenderBatchKey(
                meshHandle: item.meshHandle,
                materialKey: materialKey,
                pipeline: .HDRBasic,
                cullModeKey: bindings.cullMode == .none ? 0 : 1
            )
            var builder = builders[key] ?? RenderBatchBuilder(mesh: item.mesh, bindings: bindings, instances: [])
            let pickId = PickingSystem.assignPickId(for: item.entity)
            var instance = InstanceData()
            instance.modelMatrix = modelMatrix(for: item.transform)
            instance.entityID = pickId
            builder.instances.append(instance)
            builders[key] = builder
            uniqueMeshes.insert(item.meshHandle)
        }

        var instances: [InstanceData] = []
        instances.reserveCapacity(items.count)
        var batches: [RenderBatch] = []
        batches.reserveCapacity(builders.count)
        var instancedDrawCalls = 0
        var nonInstancedDrawCalls = 0

        for builder in builders.values {
            let start = instances.count
            instances.append(contentsOf: builder.instances)
            let end = instances.count
            batches.append(RenderBatch(mesh: builder.mesh, bindings: builder.bindings, instanceRange: start..<end))
            if builder.instances.count > 1 {
                instancedDrawCalls += 1
            } else {
                nonInstancedDrawCalls += 1
            }
        }

        let instanceBuffer = frameContext.uploadInstanceData(instances)

        let stats = RendererBatchStats(
            uniqueMeshes: uniqueMeshes.count,
            batches: batches.count,
            instancedDrawCalls: instancedDrawCalls,
            nonInstancedDrawCalls: nonInstancedDrawCalls
        )
        frameContext.updateBatchStats(stats)

        return RenderBatchResult(instances: instances, batches: batches, instanceBuffer: instanceBuffer)
    }

    private static func resolveMaterialBindings(scene: EngineScene, entity: Entity, meshRenderer: MeshRendererComponent) -> MaterialBindings {
        let materialHandle = meshRenderer.materialHandle ?? scene.ecs.get(MaterialComponent.self, for: entity)?.materialHandle
        var materialOverride = meshRenderer.material
        var albedoMapHandle = meshRenderer.albedoMapHandle
        var normalMapHandle = meshRenderer.normalMapHandle
        var metallicMapHandle = meshRenderer.metallicMapHandle
        var roughnessMapHandle = meshRenderer.roughnessMapHandle
        var mrMapHandle = meshRenderer.mrMapHandle
        var aoMapHandle = meshRenderer.aoMapHandle
        var emissiveMapHandle = meshRenderer.emissiveMapHandle
        var cullMode: MTLCullMode = .back

        if let materialHandle,
           let materialAsset = AssetManager.material(handle: materialHandle) {
            materialOverride = materialAsset.buildMetalMaterial(database: Engine.assetDatabase)
            albedoMapHandle = materialAsset.textures.baseColor
            normalMapHandle = materialAsset.textures.normal
            metallicMapHandle = materialAsset.textures.metallic
            roughnessMapHandle = materialAsset.textures.roughness
            mrMapHandle = materialAsset.textures.metalRoughness
            aoMapHandle = materialAsset.textures.ao
            emissiveMapHandle = materialAsset.textures.emissive
            if (materialOverride?.flags ?? 0) & MetalCupMaterialFlags.isDoubleSided.rawValue != 0 {
                cullMode = .none
            }
        }
        if let name = scene.ecs.get(NameComponent.self, for: entity), name.name == "Ground" {
            cullMode = .none
        }
        if let normalHandle = normalMapHandle,
           let metadata = Engine.assetDatabase?.metadata(for: normalHandle) {
            if AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
                var material = materialOverride ?? MetalCupMaterial()
                material.flags |= MetalCupMaterialFlags.normalFlipY.rawValue
                materialOverride = material
            }
        }

        return MaterialBindings(
            materialHandle: materialHandle,
            materialOverride: materialOverride,
            albedoMapHandle: albedoMapHandle,
            normalMapHandle: normalMapHandle,
            metallicMapHandle: metallicMapHandle,
            roughnessMapHandle: roughnessMapHandle,
            mrMapHandle: mrMapHandle,
            aoMapHandle: aoMapHandle,
            emissiveMapHandle: emissiveMapHandle,
            cullMode: cullMode
        )
    }

    private static func makeMaterialKey(bindings: MaterialBindings) -> MaterialBatchKey {
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

    private static func modelMatrix(for transform: TransformComponent) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.translate(direction: transform.position)
        matrix.rotate(angle: transform.rotation.x, axis: xAxis)
        matrix.rotate(angle: transform.rotation.y, axis: yAxis)
        matrix.rotate(angle: transform.rotation.z, axis: zAxis)
        matrix.scale(axis: transform.scale)
        return matrix
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
        var matrix = matrix_identity_float4x4
        matrix.rotate(angle: transform.rotation.x, axis: xAxis)
        matrix.rotate(angle: transform.rotation.y, axis: yAxis)
        matrix.rotate(angle: transform.rotation.z, axis: zAxis)
        matrix.translate(direction: -transform.position)
        return matrix
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
