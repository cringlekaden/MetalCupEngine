/// EngineScene.swift
/// Defines the EngineScene types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit
import simd

public class EngineScene {
    public let ecs: SceneECS

    public let id: UUID
    public private(set) var name: String
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    private let _editorCameraController = EditorCameraController()

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
        var settings = Renderer.settings
        encoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: FragmentBufferIndex.rendererSettings)
        _lightManager.setLightData(encoder)
        renderSky(encoder)
        renderMeshes(encoder)
        encoder.popDebugGroup()
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

    private func renderMeshes(_ encoder: MTLRenderCommandEncoder) {
        ecs.viewTransformMeshRenderer { entity, transform, meshRenderer in
            guard let meshHandle = meshRenderer.meshHandle,
                  let mesh = AssetManager.mesh(handle: meshHandle) else { return }
            encoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRBasic])
            encoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.counterClockwise)

            let materialHandle = meshRenderer.materialHandle ?? ecs.get(MaterialComponent.self, for: entity)?.materialHandle
            var materialOverride = meshRenderer.material
            var albedoMapHandle = meshRenderer.albedoMapHandle
            var normalMapHandle = meshRenderer.normalMapHandle
            var metallicMapHandle = meshRenderer.metallicMapHandle
            var roughnessMapHandle = meshRenderer.roughnessMapHandle
            var mrMapHandle = meshRenderer.mrMapHandle
            var aoMapHandle = meshRenderer.aoMapHandle
            var emissiveMapHandle = meshRenderer.emissiveMapHandle

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
                    encoder.setCullMode(.none)
                }
            }
            if let name = ecs.get(NameComponent.self, for: entity), name.name == "Ground" {
                encoder.setCullMode(.none)
            }
            if let normalHandle = normalMapHandle,
               let metadata = Engine.assetDatabase?.metadata(for: normalHandle) {
                if AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
                    var material = materialOverride ?? MetalCupMaterial()
                    material.flags |= MetalCupMaterialFlags.normalFlipY.rawValue
                    materialOverride = material
                }
            }

            var modelConstants = ModelConstants()
            modelConstants.modelMatrix = modelMatrix(for: transform)
            encoder.setVertexBytes(&modelConstants, length: ModelConstants.stride, index: VertexBufferIndex.modelConstants)
            mesh.drawPrimitives(
                encoder,
                material: materialOverride,
                albedoMapHandle: albedoMapHandle,
                normalMapHandle: normalMapHandle,
                metallicMapHandle: metallicMapHandle,
                roughnessMapHandle: roughnessMapHandle,
                mrMapHandle: mrMapHandle,
                aoMapHandle: aoMapHandle,
                emissiveMapHandle: emissiveMapHandle,
                useEmbeddedMaterial: false
            )
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
