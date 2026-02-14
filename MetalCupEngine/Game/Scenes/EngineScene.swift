/// EngineScene.swift
/// Scene update and render submission pipeline.
/// Created by Kaden Cringle

import MetalKit
import simd

public class EngineScene {
    public let ecs: SceneECS

    public let id: UUID
    public private(set) var name: String
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    private let _editorCameraController = EditorCameraController()
    private var _cachedBatchResult: RenderBatchResult?
    private var _cachedBatchFrameIndex: Int = -1
    private var _lastPickIdMap: [UInt32: Entity] = [:]

    public var environmentMapHandle: AssetHandle?

    init(id: UUID = UUID(), name: String, environmentMapHandle: AssetHandle?, shouldBuildScene: Bool = true) {
        self.id = id
        self.name = name
        self.environmentMapHandle = environmentMapHandle
        self.ecs = SceneECS()
        if shouldBuildScene {
            buildScene()
        }
    }

    public func onUpdate(isPlaying: Bool = true, isPaused: Bool = false) {
        // Update order: camera -> scene constants -> sky system -> scene update -> light sync.
        ensureCameraEntity()
        updateCamera(isPlaying: isPlaying)
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        let cameraPosition = SIMD3<Float>(
            _sceneConstants.cameraPositionAndIBL.x,
            _sceneConstants.cameraPositionAndIBL.y,
            _sceneConstants.cameraPositionAndIBL.z
        )
        let hasEnvironment: Bool = {
            guard let (_, sky) = ecs.activeSkyLight(), sky.enabled else { return false }
            switch sky.mode {
            case .hdri:
                return sky.hdriHandle.flatMap { AssetManager.texture(handle: $0) } != nil
            case .procedural:
                return true
            }
        }()
        let settings = Renderer.settings
        let skyIntensity = ecs.activeSkyLight()?.1.intensity ?? 1.0
        let iblIntensity = (hasEnvironment && settings.iblEnabled != 0) ? settings.iblIntensity * skyIntensity : 0.0
        _sceneConstants.cameraPositionAndIBL.w = iblIntensity
        SkySystem.update(scene: ecs)
        if isPlaying && !isPaused {
            updateLightOrbits()
            doUpdate()
        }
        syncLights()
    }

    public func onRender(encoder: MTLRenderCommandEncoder) {
        encoder.pushDebugGroup("Rendering Scene \(name)...")
        encoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride, index: VertexBufferIndex.sceneConstants)
        switch Renderer.currentRenderPass {
        case .main:
            var settings = Renderer.settings
            encoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: FragmentBufferIndex.rendererSettings)
            _lightManager.setLightData(encoder)
            renderSky(encoder)
            renderMeshes(encoder, pass: .main)
            renderSelectionHighlight(encoder)
        case .picking:
            renderMeshes(encoder, pass: .picking)
        case .depthPrepass:
            renderMeshes(encoder, pass: .depthPrepass)
        }
        encoder.popDebugGroup()
    }

    public func entity(forPickID id: UInt32) -> Entity? {
        return _lastPickIdMap[id]
    }

    func updateCameras() {
        updateCamera(isPlaying: false)
    }

    func updateAspectRatio() {
        updateCamera(isPlaying: false)
    }

    func buildScene() {}

    func doUpdate() {}

    public func toDocument(rendererSettingsOverride: RendererSettingsDTO? = nil) -> SceneDocument {
        let entities = ecs.allEntities().map { entity -> EntityDocument in
            let components = ComponentsDocument(
                name: ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) },
                transform: ecs.get(TransformComponent.self, for: entity).map { component in
                    TransformComponentDTO(
                        position: Vector3DTO(component.position),
                        rotation: Vector3DTO(component.rotation),
                        scale: Vector3DTO(component.scale)
                    )
                },
                meshRenderer: ecs.get(MeshRendererComponent.self, for: entity).map { component in
                    MeshRendererComponentDTO(
                        meshHandle: component.meshHandle,
                        materialHandle: component.materialHandle,
                        material: component.material.map { MaterialDTO(material: $0) },
                        albedoMapHandle: component.albedoMapHandle,
                        normalMapHandle: component.normalMapHandle,
                        metallicMapHandle: component.metallicMapHandle,
                        roughnessMapHandle: component.roughnessMapHandle,
                        mrMapHandle: component.mrMapHandle,
                        aoMapHandle: component.aoMapHandle,
                        emissiveMapHandle: component.emissiveMapHandle
                    )
                },
                materialComponent: ecs.get(MaterialComponent.self, for: entity).map { component in
                    MaterialComponentDTO(materialHandle: component.materialHandle)
                },
                light: ecs.get(LightComponent.self, for: entity).map { component in
                    LightComponentDTO(
                        type: LightTypeDTO(from: component.type),
                        data: LightDataDTO(from: component.data),
                        direction: Vector3DTO(component.direction),
                        range: component.range,
                        innerConeCos: component.innerConeCos,
                        outerConeCos: component.outerConeCos
                    )
                },
                lightOrbit: ecs.get(LightOrbitComponent.self, for: entity).map { component in
                    LightOrbitComponentDTO(component: component)
                },
                camera: ecs.get(CameraComponent.self, for: entity).map { component in
                    CameraComponentDTO(component: component)
                },
                sky: ecs.get(SkyComponent.self, for: entity).map { component in
                    SkyComponentDTO(environmentMapHandle: component.environmentMapHandle)
                },
                skyLight: ecs.get(SkyLightComponent.self, for: entity).map { component in
                    SkyLightComponentDTO(
                        mode: component.mode.rawValue,
                        enabled: component.enabled,
                        intensity: component.intensity,
                        skyTint: Vector3DTO(component.skyTint),
                        turbidity: component.turbidity,
                        azimuthDegrees: component.azimuthDegrees,
                        elevationDegrees: component.elevationDegrees,
                        hdriHandle: component.hdriHandle,
                        realtimeUpdate: component.realtimeUpdate
                    )
                },
                skyLightTag: ecs.get(SkyLightTag.self, for: entity).map { _ in TagComponentDTO() },
                skySunTag: ecs.get(SkySunTag.self, for: entity).map { _ in TagComponentDTO() }
            )
            return EntityDocument(id: entity.id, components: components)
        }
        return SceneDocument(id: id, name: name, entities: entities, rendererSettingsOverride: rendererSettingsOverride)
    }

    public func apply(document: SceneDocument) {
        ecs.clear()
        name = document.name
        for entityDoc in document.entities {
            let entity = ecs.createEntity(id: entityDoc.id, name: entityDoc.components.name?.name)
            if let transform = entityDoc.components.transform {
                let component = TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotation.toSIMD(),
                    scale: transform.scale.toSIMD()
                )
                ecs.add(component, to: entity)
            } else {
                ecs.add(TransformComponent(), to: entity)
            }
            if let meshRenderer = entityDoc.components.meshRenderer {
                let component = MeshRendererComponent(
                    meshHandle: meshRenderer.meshHandle,
                    materialHandle: meshRenderer.materialHandle,
                    material: meshRenderer.material?.toMaterial(),
                    albedoMapHandle: meshRenderer.albedoMapHandle,
                    normalMapHandle: meshRenderer.normalMapHandle,
                    metallicMapHandle: meshRenderer.metallicMapHandle,
                    roughnessMapHandle: meshRenderer.roughnessMapHandle,
                    mrMapHandle: meshRenderer.mrMapHandle,
                    aoMapHandle: meshRenderer.aoMapHandle,
                    emissiveMapHandle: meshRenderer.emissiveMapHandle
                )
                ecs.add(component, to: entity)
            }
            if let materialComponent = entityDoc.components.materialComponent {
                let component = MaterialComponent(materialHandle: materialComponent.materialHandle)
                ecs.add(component, to: entity)
            }
            if let light = entityDoc.components.light {
                let component = LightComponent(
                    type: light.type.toLightType(),
                    data: light.data.toLightData(),
                    direction: light.direction.toSIMD(),
                    range: light.range,
                    innerConeCos: light.innerConeCos,
                    outerConeCos: light.outerConeCos
                )
                ecs.add(component, to: entity)
            }
            if let lightOrbit = entityDoc.components.lightOrbit {
                ecs.add(lightOrbit.toComponent(), to: entity)
            }
            if let camera = entityDoc.components.camera {
                ecs.add(camera.toComponent(), to: entity)
            }
            if let sky = entityDoc.components.sky {
                ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
            }
            if let skyLight = entityDoc.components.skyLight {
                let component = SkyLightComponent(
                    mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
                    enabled: skyLight.enabled,
                    intensity: skyLight.intensity,
                    skyTint: skyLight.skyTint.toSIMD(),
                    turbidity: skyLight.turbidity,
                    azimuthDegrees: skyLight.azimuthDegrees,
                    elevationDegrees: skyLight.elevationDegrees,
                    hdriHandle: skyLight.hdriHandle,
                    needsRegenerate: true,
                    realtimeUpdate: skyLight.realtimeUpdate,
                    lastRegenerateTime: 0.0
                )
                ecs.add(component, to: entity)
            }
            if entityDoc.components.skyLightTag != nil {
                ecs.add(SkyLightTag(), to: entity)
            }
            if entityDoc.components.skySunTag != nil {
                ecs.add(SkySunTag(), to: entity)
            }
        }
        ensureCameraEntity()
    }

    private func ensureCameraEntity() {
        if ecs.activeCamera() != nil { return }
        let entity = ecs.createEntity(name: "Editor Camera")
        ecs.add(TransformComponent(position: SIMD3<Float>(0, 3, 10)), to: entity)
        ecs.add(CameraComponent(isPrimary: true, isEditor: true), to: entity)
    }

    private func updateCamera(isPlaying: Bool) {
        guard var active = ecs.activeCamera() else { return }
        var transform = active.1
        let camera = active.2
        if !isPlaying && camera.isEditor {
            _editorCameraController.update(transform: &transform)
            ecs.add(transform, to: active.0)
        }
        _sceneConstants.viewMatrix = viewMatrix(from: transform)
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0
        _sceneConstants.skyViewMatrix[3][1] = 0
        _sceneConstants.skyViewMatrix[3][2] = 0
        _sceneConstants.projectionMatrix = projectionMatrix(from: camera)
        _sceneConstants.cameraPositionAndIBL = SIMD4<Float>(transform.position, 1.0)
    }

    private func viewMatrix(from transform: TransformComponent) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.rotate(angle: transform.rotation.x, axis: xAxis)
        matrix.rotate(angle: transform.rotation.y, axis: yAxis)
        matrix.rotate(angle: transform.rotation.z, axis: zAxis)
        matrix.translate(direction: -transform.position)
        return matrix
    }

    private func projectionMatrix(from camera: CameraComponent) -> matrix_float4x4 {
        let nearPlane = max(0.01, camera.nearPlane)
        let farPlane = max(nearPlane + 0.01, camera.farPlane)
        return matrix_float4x4.perspective(
            fovDegrees: camera.fovDegrees,
            aspectRatio: Renderer.AspectRatio,
            near: nearPlane,
            far: farPlane
        )
    }

    public func onEvent(_ event: Event) {}

    private func updateLightOrbits() {
        let t = GameTime.TotalGameTime
        ecs.viewLightOrbits { entity, transform, orbit in
            let angle = t * orbit.speed + orbit.phase
            let centerPosition: SIMD3<Float> = {
                guard let centerId = orbit.centerEntityId,
                      let centerEntity = ecs.entity(with: centerId),
                      let centerTransform = ecs.get(TransformComponent.self, for: centerEntity) else {
                    return .zero
                }
                return centerTransform.position
            }()

            if var light = ecs.get(LightComponent.self, for: entity), light.type == .directional {
                if ecs.get(SkySunTag.self, for: entity) != nil {
                    return
                }
                if orbit.affectsDirection {
                    let direction = SIMD3<Float>(
                        cos(angle) * orbit.radius,
                        orbit.height,
                        sin(angle) * orbit.radius
                    )
                    if simd_length_squared(direction) > 0 {
                        light.direction = simd_normalize(direction)
                        ecs.add(light, to: entity)
                    }
                }
                return
            }

            guard var transform else { return }
            transform.position = SIMD3<Float>(
                centerPosition.x + cos(angle) * orbit.radius,
                centerPosition.y + orbit.height,
                centerPosition.z + sin(angle) * orbit.radius
            )
            ecs.add(transform, to: entity)

            if orbit.affectsDirection,
               var light = ecs.get(LightComponent.self, for: entity),
               light.type == .spot {
                let direction = centerPosition - transform.position
                if simd_length_squared(direction) > 0 {
                    light.direction = simd_normalize(direction)
                    ecs.add(light, to: entity)
                }
            }
        }
    }

    private func syncLights() {
        var lightData: [LightData] = []
        ecs.viewLights { _, transform, light in
            var data = light.data
            switch light.type {
            case .point:
                data.type = 0
            case .spot:
                data.type = 1
            case .directional:
                data.type = 2
            }
            if let transform {
                data.position = transform.position
            }
            data.direction = light.direction
            data.range = light.range
            data.innerConeCos = light.innerConeCos
            data.outerConeCos = light.outerConeCos
            lightData.append(data)
        }
        _lightManager.setLights(lightData)
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

    private func renderSky(_ encoder: MTLRenderCommandEncoder) {
        var renderedSky = false
        ecs.viewSkyLights { _, sky in
            if renderedSky { return }
            if !sky.enabled { return }
            renderedSky = true
            guard let mesh = AssetManager.mesh(handle: BuiltinAssets.skyboxMesh) else { return }
            encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            encoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.clockwise)
            var modelConstants = ModelConstants()
            modelConstants.modelMatrix = matrix_identity_float4x4
            encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
            encoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.environmentCubemap), index: FragmentTextureIndex.skybox)
            mesh.drawPrimitives(encoder)
        }
    }

    private func renderMeshes(_ encoder: MTLRenderCommandEncoder, pass: RenderPassType) {
        let batchResult = currentBatchResult()
        guard let instanceBuffer = batchResult.instanceBuffer else { return }
        let instanceStride = InstanceData.stride

        for batch in batchResult.batches {
            let instanceCount = batch.instanceRange.count
            if instanceCount == 0 { continue }
            let instanceOffset = batch.instanceRange.lowerBound * instanceStride
            applyPerDrawState(encoder, pass: pass, cullMode: batch.bindings.cullMode)

            switch pass {
            case .depthPrepass:
                encodeDepthPrepass(
                    encoder,
                    batch: batch,
                    batchResult: batchResult,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount
                )
            case .picking:
                encodePicking(
                    encoder,
                    batch: batch,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount
                )
            case .main:
                encodeMainPass(
                    encoder,
                    batch: batch,
                    batchResult: batchResult,
                    instanceBuffer: instanceBuffer,
                    instanceOffset: instanceOffset,
                    instanceCount: instanceCount
                )
            }
        }
    }

    private func applyPerDrawState(_ encoder: MTLRenderCommandEncoder, pass: RenderPassType, cullMode: MTLCullMode) {
        encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        let useEqual = Renderer.useDepthPrepass && pass == .main
        encoder.setDepthStencilState(Graphics.DepthStencilStates[useEqual ? .EqualNoWrite : .Less])
        encoder.setCullMode(cullMode)
        encoder.setFrontFacing(.counterClockwise)
    }

    private func encodeDepthPrepass(
        _ encoder: MTLRenderCommandEncoder,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int
    ) {
        if instanceCount > 1 {
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.DepthPrepassInstanced])
            encoder.setVertexBuffer(instanceBuffer, offset: instanceOffset, index: VertexBufferIndex.instances)
            batch.mesh.setInstanceCount(instanceCount)
            drawMesh(encoder, mesh: batch.mesh, bindings: nil)
            return
        }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.DepthPrepass])
        let instanceIndex = batch.instanceRange.lowerBound
        guard instanceIndex < batchResult.instances.count else { return }
        var modelConstants = ModelConstants()
        modelConstants.modelMatrix = batchResult.instances[instanceIndex].modelMatrix
        encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
        batch.mesh.setInstanceCount(1)
        drawMesh(encoder, mesh: batch.mesh, bindings: nil)
    }

    private func encodePicking(
        _ encoder: MTLRenderCommandEncoder,
        batch: RenderBatch,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int
    ) {
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.PickID])
        encoder.setVertexBuffer(instanceBuffer, offset: instanceOffset, index: VertexBufferIndex.instances)
        batch.mesh.setInstanceCount(instanceCount)
        drawMesh(encoder, mesh: batch.mesh, bindings: nil)
    }

    private func encodeMainPass(
        _ encoder: MTLRenderCommandEncoder,
        batch: RenderBatch,
        batchResult: RenderBatchResult,
        instanceBuffer: MTLBuffer,
        instanceOffset: Int,
        instanceCount: Int
    ) {
        if instanceCount > 1 {
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRInstanced])
            encoder.setVertexBuffer(instanceBuffer, offset: instanceOffset, index: VertexBufferIndex.instances)
            batch.mesh.setInstanceCount(instanceCount)
            drawMesh(encoder, mesh: batch.mesh, bindings: batch.bindings)
            return
        }
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRBasic])
        let instanceIndex = batch.instanceRange.lowerBound
        guard instanceIndex < batchResult.instances.count else { return }
        var modelConstants = ModelConstants()
        modelConstants.modelMatrix = batchResult.instances[instanceIndex].modelMatrix
        encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
        batch.mesh.setInstanceCount(1)
        drawMesh(encoder, mesh: batch.mesh, bindings: batch.bindings)
    }

    private func drawMesh(_ encoder: MTLRenderCommandEncoder, mesh: MCMesh, bindings: MaterialBindings?) {
        mesh.drawPrimitives(
            encoder,
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

    private func renderSelectionHighlight(_ encoder: MTLRenderCommandEncoder) {
        guard !SceneManager.isPlaying,
              let selectedId = SceneManager.selectedEntityUUID(),
              let entity = ecs.entity(with: selectedId),
              let transform = ecs.get(TransformComponent.self, for: entity),
              let meshRenderer = ecs.get(MeshRendererComponent.self, for: entity),
              let meshHandle = meshRenderer.meshHandle,
              let mesh = AssetManager.mesh(handle: meshHandle) else { return }

        encoder.setTriangleFillMode(.lines)
        encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRBasic])
        encoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)

        var modelConstants = ModelConstants()
        modelConstants.modelMatrix = modelMatrix(for: transform)
        encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)

        var highlightMaterial = MetalCupMaterial()
        highlightMaterial.baseColor = SIMD3<Float>(1.0, 0.82, 0.2)
        highlightMaterial.emissiveColor = SIMD3<Float>(1.0, 0.75, 0.1)
        highlightMaterial.emissiveScalar = 2.5
        highlightMaterial.flags = MetalCupMaterialFlags.isUnlit.rawValue

        mesh.setInstanceCount(1)
        mesh.drawPrimitives(
            encoder,
            material: highlightMaterial,
            albedoMapHandle: nil,
            normalMapHandle: nil,
            metallicMapHandle: nil,
            roughnessMapHandle: nil,
            mrMapHandle: nil,
            aoMapHandle: nil,
            emissiveMapHandle: nil,
            useEmbeddedMaterial: false
        )
    }

    private func currentBatchResult() -> RenderBatchResult {
        let frameIndex = RendererFrameContext.shared.currentFrameIndex()
        if _cachedBatchFrameIndex == frameIndex, let cached = _cachedBatchResult {
            return cached
        }
        let result = buildRenderBatches()
        _cachedBatchFrameIndex = frameIndex
        _cachedBatchResult = result
        return result
    }

    // Gather -> group -> encode pipeline for meshes.
    private func buildRenderItems() -> [RenderItem] {
        let items = ecs.viewTransformMeshRendererArray()
        var renderItems: [RenderItem] = []
        renderItems.reserveCapacity(items.count)

        for (entity, transform, meshRenderer) in items {
            guard let meshHandle = meshRenderer.meshHandle,
                  let mesh = AssetManager.mesh(handle: meshHandle) else { continue }
            let bindings = resolveMaterialBindings(entity: entity, meshRenderer: meshRenderer)
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

    private func buildRenderBatches() -> RenderBatchResult {
        var builders: [RenderBatchKey: RenderBatchBuilder] = [:]
        var pickMap: [UInt32: Entity] = [:]
        var uniqueMeshes = Set<AssetHandle>()
        var nextPickId: UInt32 = 1

        let items = buildRenderItems()
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
            let pickId = nextPickId
            nextPickId &+= 1
            pickMap[pickId] = item.entity
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

        _lastPickIdMap = pickMap
        let instanceBuffer = RendererFrameContext.shared.uploadInstanceData(instances)

        let stats = RendererBatchStats(
            uniqueMeshes: uniqueMeshes.count,
            batches: batches.count,
            instancedDrawCalls: instancedDrawCalls,
            nonInstancedDrawCalls: nonInstancedDrawCalls
        )
        RendererFrameContext.shared.updateBatchStats(stats)

        return RenderBatchResult(instances: instances, batches: batches, instanceBuffer: instanceBuffer)
    }

    private func resolveMaterialBindings(entity: Entity, meshRenderer: MeshRendererComponent) -> MaterialBindings {
        let materialHandle = meshRenderer.materialHandle ?? ecs.get(MaterialComponent.self, for: entity)?.materialHandle
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
        if let name = ecs.get(NameComponent.self, for: entity), name.name == "Ground" {
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

    private func makeMaterialKey(bindings: MaterialBindings) -> MaterialBatchKey {
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

    private func hashBytes<T>(of value: inout T) -> UInt64 {
        return withUnsafeBytes(of: &value) { bytes in
            var hash: UInt64 = 1469598103934665603
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            return hash
        }
    }

    private func modelMatrix(for transform: TransformComponent) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.translate(direction: transform.position)
        matrix.rotate(angle: transform.rotation.x, axis: xAxis)
        matrix.rotate(angle: transform.rotation.y, axis: yAxis)
        matrix.rotate(angle: transform.rotation.z, axis: zAxis)
        matrix.scale(axis: transform.scale)
        return matrix
    }
}
