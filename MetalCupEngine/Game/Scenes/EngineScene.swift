/// EngineScene.swift
/// Scene update and render submission pipeline.
/// Created by Kaden Cringle

import MetalKit
import simd

public class EngineScene {
    public let ecs: SceneECS
    public let runtime = SceneRuntime()
    public var prefabSystem: PrefabSystem?
    public weak var engineContext: EngineContext?

    public let id: UUID
    public private(set) var name: String
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    private let _editorCameraController = EditorCameraController()
    private var _cachedBatchResult: Any?
    private var _cachedBatchFrameToken: UInt64 = UInt64.max
    private var lastFrameContext: FrameContext?

    private var debugFrameCounter: UInt64 = 0

    public var environmentMapHandle: AssetHandle?

    public init(id: UUID = UUID(),
                name: String,
                environmentMapHandle: AssetHandle?,
                prefabSystem: PrefabSystem? = nil,
                engineContext: EngineContext? = nil,
                shouldBuildScene: Bool = true) {
        self.id = id
        self.name = name
        self.environmentMapHandle = environmentMapHandle
        self.ecs = SceneECS()
        self.prefabSystem = prefabSystem
        self.engineContext = engineContext
        if shouldBuildScene {
            buildScene()
        }
    }

    public func onUpdate(frame: FrameContext, isPlaying: Bool = true, isPaused: Bool = false) {
        debugFrameCounter &+= 1
        lastFrameContext = frame
        // Update order: camera -> scene constants -> sky system -> scene update -> light sync.
        ensureCameraEntity()
        updateCamera(isPlaying: isPlaying, frame: frame)
        _sceneConstants.totalGameTime = frame.time.totalTime
        let assetManager = engineContext?.assets
        let hasEnvironment: Bool = {
            guard let (_, sky) = ecs.activeSkyLight(), sky.enabled else { return false }
            switch sky.mode {
            case .hdri:
                return sky.hdriHandle.flatMap { assetManager?.texture(handle: $0) } != nil
            case .procedural:
                return true
            }
        }()
        let settings = engineContext?.rendererSettings ?? RendererSettings()
        let skyIntensity = ecs.activeSkyLight()?.1.intensity ?? 1.0
        let iblIntensity = (hasEnvironment && settings.iblEnabled != 0) ? settings.iblIntensity * skyIntensity : 0.0
        _sceneConstants.cameraPositionAndIBL.w = iblIntensity
        SkySystem.update(scene: ecs)
        if isPlaying && !isPaused {
            updateLightOrbits(totalTime: frame.time.totalTime)
            doUpdate()
        }
        syncLights()
    }

    func runtimeUpdate(isPlaying: Bool, isPaused: Bool, frame: FrameContext) {
        onUpdate(frame: frame, isPlaying: isPlaying, isPaused: isPaused)
    }

    func runtimeFixedUpdate() {
        onFixedUpdate()
    }

    public func onFixedUpdate() {
        doFixedUpdate()
    }

    public func onRender(encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        SceneRenderer.renderScene(into: encoder, scene: self, frameContext: frameContext)
    }

    @discardableResult
    public func render(view: SceneView, context: RenderContext, frameContext: RendererFrameContext) -> RenderOutputs {
        SceneRenderer.render(scene: self, view: view, context: context, frameContext: frameContext)
    }

    @discardableResult
    public func render(view: SceneView, context: RenderContext) -> RenderOutputs {
        guard let engineContext else {
            return RenderOutputs(color: context.colorTarget, depth: context.depthTarget, pickingId: context.idTarget)
        }
        let storage = RendererFrameContextStorage(engineContext: engineContext)
        let frameContext = storage.beginFrame()
        return render(view: view, context: context, frameContext: frameContext)
    }

    public func renderPreview(encoder: MTLRenderCommandEncoder, cameraEntity: Entity, viewportSize: SIMD2<Float>, frameContext: RendererFrameContext) {
        SceneRenderer.renderPreview(
            encoder: encoder,
            scene: self,
            cameraEntity: cameraEntity,
            viewportSize: viewportSize,
            frameContext: frameContext
        )
    }

    public func renderPreview(encoder: MTLRenderCommandEncoder, cameraEntity: Entity, viewportSize: SIMD2<Float>) {
        guard let engineContext else { return }
        let storage = RendererFrameContextStorage(engineContext: engineContext)
        let frameContext = storage.beginFrame()
        renderPreview(encoder: encoder, cameraEntity: cameraEntity, viewportSize: viewportSize, frameContext: frameContext)
    }

    public func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, mask: LayerMask = .all) -> Entity? {
        return nil
    }

    public func raycast(hitEntity: Entity?, mask: LayerMask = .all) -> Entity? {
        guard let entity = hitEntity else { return nil }
        let layer = layerIndex(for: entity)
        return mask.contains(layerIndex: layer) ? entity : nil
    }

    func updateCameras() {
        updateCamera(isPlaying: false, frame: currentFrameForUpdates())
    }

    public func updateAspectRatio() {
        updateCamera(isPlaying: false, frame: currentFrameForUpdates())
    }

    func buildScene() {}

    func doUpdate() {}

    func doFixedUpdate() {}

    public func toDocument(rendererSettingsOverride: RendererSettingsDTO? = nil) -> SceneDocument {
        func overrideSet(for entity: Entity) -> Set<PrefabOverrideType> {
            return ecs.get(PrefabOverrideComponent.self, for: entity)?.overridden ?? []
        }

        func shouldSerializeOverride(_ type: PrefabOverrideType, for entity: Entity) -> Bool {
            return overrideSet(for: entity).contains(type)
        }

        func transformDTO(for entity: Entity) -> TransformComponentDTO? {
            return ecs.get(TransformComponent.self, for: entity).map { component in
                TransformComponentDTO(
                    position: Vector3DTO(component.position),
                    rotation: Vector3DTO(component.rotation),
                    scale: Vector3DTO(component.scale)
                )
            }
        }

        let entities = ecs.allEntities().map { entity -> EntityDocument in
            let prefabLink = ecs.get(PrefabInstanceComponent.self, for: entity)
            let prefabOverrides = ecs.get(PrefabOverrideComponent.self, for: entity)
            let prefabOverridesDTO: PrefabOverrideComponentDTO? = prefabOverrides.map {
                PrefabOverrideComponentDTO(overriddenComponents: $0.overridden.map { $0.rawValue })
            }

            if let prefabLink {
                let components = ComponentsDocument(
                    name: shouldSerializeOverride(.name, for: entity)
                        ? ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) }
                        : nil,
                    transform: transformDTO(for: entity),
                    layer: shouldSerializeOverride(.layer, for: entity)
                        ? ecs.get(LayerComponent.self, for: entity).map { LayerComponentDTO(layerIndex: $0.index) }
                        : nil,
                    prefabLink: PrefabLinkComponentDTO(
                        prefabHandle: prefabLink.prefabHandle,
                        prefabEntityId: prefabLink.prefabEntityId,
                        instanceId: prefabLink.instanceId
                    ),
                    prefabOverrides: prefabOverridesDTO,
                    meshRenderer: shouldSerializeOverride(.meshRenderer, for: entity)
                        ? ecs.get(MeshRendererComponent.self, for: entity).map { component in
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
                        }
                        : nil,
                    materialComponent: shouldSerializeOverride(.material, for: entity)
                        ? ecs.get(MaterialComponent.self, for: entity).map { MaterialComponentDTO(materialHandle: $0.materialHandle) }
                        : nil,
                    light: shouldSerializeOverride(.light, for: entity)
                        ? ecs.get(LightComponent.self, for: entity).map { component in
                            LightComponentDTO(
                                type: LightTypeDTO(from: component.type),
                                data: LightDataDTO(from: component.data),
                                direction: Vector3DTO(component.direction),
                                range: component.range,
                                innerConeCos: component.innerConeCos,
                                outerConeCos: component.outerConeCos,
                                castsShadows: component.castsShadows
                            )
                        }
                        : nil,
                    lightOrbit: shouldSerializeOverride(.lightOrbit, for: entity)
                        ? ecs.get(LightOrbitComponent.self, for: entity).map { LightOrbitComponentDTO(component: $0) }
                        : nil,
                    camera: shouldSerializeOverride(.camera, for: entity)
                        ? ecs.get(CameraComponent.self, for: entity).map { CameraComponentDTO(component: $0) }
                        : nil,
                    sky: shouldSerializeOverride(.sky, for: entity)
                        ? ecs.get(SkyComponent.self, for: entity).map { SkyComponentDTO(environmentMapHandle: $0.environmentMapHandle) }
                        : nil,
                    skyLight: shouldSerializeOverride(.skyLight, for: entity)
                        ? ecs.get(SkyLightComponent.self, for: entity).map { component in
                            SkyLightComponentDTO(
                                mode: component.mode.rawValue,
                                enabled: component.enabled,
                                intensity: component.intensity,
                                skyTint: Vector3DTO(component.skyTint),
                                turbidity: component.turbidity,
                                azimuthDegrees: component.azimuthDegrees,
                                elevationDegrees: component.elevationDegrees,
                                sunSizeDegrees: component.sunSizeDegrees,
                                zenithTint: Vector3DTO(component.zenithTint),
                                horizonTint: Vector3DTO(component.horizonTint),
                                gradientStrength: component.gradientStrength,
                                hazeDensity: component.hazeDensity,
                                hazeFalloff: component.hazeFalloff,
                                hazeHeight: component.hazeHeight,
                                ozoneStrength: component.ozoneStrength,
                                ozoneTint: Vector3DTO(component.ozoneTint),
                                sunHaloSize: component.sunHaloSize,
                                sunHaloIntensity: component.sunHaloIntensity,
                                sunHaloSoftness: component.sunHaloSoftness,
                                cloudsEnabled: component.cloudsEnabled,
                                cloudsCoverage: component.cloudsCoverage,
                                cloudsSoftness: component.cloudsSoftness,
                                cloudsScale: component.cloudsScale,
                                cloudsSpeed: component.cloudsSpeed,
                                cloudsWindX: component.cloudsWindDirection.x,
                                cloudsWindY: component.cloudsWindDirection.y,
                                cloudsHeight: component.cloudsHeight,
                                cloudsThickness: component.cloudsThickness,
                                cloudsBrightness: component.cloudsBrightness,
                                cloudsSunInfluence: component.cloudsSunInfluence,
                                hdriHandle: component.hdriHandle,
                                realtimeUpdate: component.realtimeUpdate
                            )
                        }
                        : nil,
                    skyLightTag: shouldSerializeOverride(.skyLightTag, for: entity) && ecs.has(SkyLightTag.self, entity) ? TagComponentDTO() : nil,
                    skySunTag: shouldSerializeOverride(.skySunTag, for: entity) && ecs.has(SkySunTag.self, entity) ? TagComponentDTO() : nil
                )
                return EntityDocument(id: entity.id, components: components)
            }

            let components = ComponentsDocument(
                name: ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) },
                transform: transformDTO(for: entity),
                layer: ecs.get(LayerComponent.self, for: entity).map { component in
                    LayerComponentDTO(layerIndex: component.index)
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
                        outerConeCos: component.outerConeCos,
                        castsShadows: component.castsShadows
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
                        sunSizeDegrees: component.sunSizeDegrees,
                        zenithTint: Vector3DTO(component.zenithTint),
                        horizonTint: Vector3DTO(component.horizonTint),
                        gradientStrength: component.gradientStrength,
                        hazeDensity: component.hazeDensity,
                        hazeFalloff: component.hazeFalloff,
                        hazeHeight: component.hazeHeight,
                        ozoneStrength: component.ozoneStrength,
                        ozoneTint: Vector3DTO(component.ozoneTint),
                        sunHaloSize: component.sunHaloSize,
                        sunHaloIntensity: component.sunHaloIntensity,
                        sunHaloSoftness: component.sunHaloSoftness,
                        cloudsEnabled: component.cloudsEnabled,
                        cloudsCoverage: component.cloudsCoverage,
                        cloudsSoftness: component.cloudsSoftness,
                        cloudsScale: component.cloudsScale,
                        cloudsSpeed: component.cloudsSpeed,
                        cloudsWindX: component.cloudsWindDirection.x,
                        cloudsWindY: component.cloudsWindDirection.y,
                        cloudsHeight: component.cloudsHeight,
                        cloudsThickness: component.cloudsThickness,
                        cloudsBrightness: component.cloudsBrightness,
                        cloudsSunInfluence: component.cloudsSunInfluence,
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
        var prefabHandles = Set<AssetHandle>()
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

            if let prefabLink = entityDoc.components.prefabLink {
                let component = PrefabInstanceComponent(
                    prefabHandle: prefabLink.prefabHandle,
                    prefabEntityId: prefabLink.prefabEntityId,
                    instanceId: prefabLink.instanceId
                )
                ecs.add(component, to: entity)
                prefabHandles.insert(prefabLink.prefabHandle)
                if let overrides = entityDoc.components.prefabOverrides {
                    let overrideSet = Set(overrides.overriddenComponents.compactMap { PrefabOverrideType(rawValue: $0) })
                    ecs.add(PrefabOverrideComponent(overridden: overrideSet), to: entity)
                }
                if let layer = entityDoc.components.layer {
                    ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
                }
                if let name = entityDoc.components.name {
                    ecs.add(NameComponent(name: name.name), to: entity)
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
                    ecs.add(MaterialComponent(materialHandle: materialComponent.materialHandle), to: entity)
                }
                if let light = entityDoc.components.light {
                    let component = LightComponent(
                        type: light.type.toLightType(),
                        data: light.data.toLightData(),
                        direction: light.direction.toSIMD(),
                        range: light.range,
                        innerConeCos: light.innerConeCos,
                        outerConeCos: light.outerConeCos,
                        castsShadows: light.castsShadows
                    )
                    ecs.add(component, to: entity)
#if DEBUG
                    MC_ASSERT(component.castsShadows == light.castsShadows, "Light castsShadows mismatch after load.")
#endif
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
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                        needsRebuild: true,
                        rebuildRequested: false,
                        realtimeUpdate: skyLight.realtimeUpdate,
                        lastRebuildTime: 0.0
                    )
                    ecs.add(component, to: entity)
                }
                if entityDoc.components.skyLightTag != nil {
                    ecs.add(SkyLightTag(), to: entity)
                }
                if entityDoc.components.skySunTag != nil {
                    ecs.add(SkySunTag(), to: entity)
                }
                continue
            }

            if let layer = entityDoc.components.layer {
                ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                ecs.add(LayerComponent(), to: entity)
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
                    outerConeCos: light.outerConeCos,
                    castsShadows: light.castsShadows
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
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                    needsRebuild: true,
                    rebuildRequested: false,
                    realtimeUpdate: skyLight.realtimeUpdate,
                    lastRebuildTime: 0.0
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
        if !prefabHandles.isEmpty {
            prefabSystem?.applyPrefabs(handles: prefabHandles, to: self)
        }
        ensureCameraEntity()
    }

    @discardableResult
    public func instantiate(prefab: PrefabDocument, prefabHandle: AssetHandle?) -> [Entity] {
        var created: [Entity] = []
        created.reserveCapacity(prefab.entities.count)
        let instanceId = UUID()

        for entityDoc in prefab.entities {
            let entityName = entityDoc.components.name?.name ?? "Entity"
            let entity = ecs.createEntity(name: entityName)
            created.append(entity)

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
            if let layer = entityDoc.components.layer {
                ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                ecs.add(LayerComponent(), to: entity)
            }
            if let prefabHandle {
                let link = PrefabInstanceComponent(prefabHandle: prefabHandle, prefabEntityId: entityDoc.localId, instanceId: instanceId)
                ecs.add(link, to: entity)
            } else {
                EngineLoggerContext.log(
                    "Prefab instantiate missing handle for \(prefab.name)",
                    level: .warning,
                    category: .scene
                )
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
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                    needsRebuild: true,
                    rebuildRequested: false,
                    realtimeUpdate: skyLight.realtimeUpdate,
                    lastRebuildTime: 0.0
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
        return created
    }

    private func ensureCameraEntity() {
        if ecs.activeCamera() != nil { return }
        let entity = ecs.createEntity(name: "Editor Camera")
        ecs.add(TransformComponent(position: SIMD3<Float>(0, 3, 10)), to: entity)
        ecs.add(CameraComponent(isPrimary: true, isEditor: true), to: entity)
    }

    private func updateCamera(isPlaying: Bool, frame: FrameContext) {
        guard var active = resolveActiveCamera(isPlaying: isPlaying) else { return }
        if active.shouldUpdateEditorCamera {
            _editorCameraController.update(transform: &active.transform, frame: frame)
            ecs.add(active.transform, to: active.entity)
        }
        let viewportSize = frame.input.viewportSize
        let aspectRatio: Float = {
            let width = max(1.0, viewportSize.x)
            let height = max(1.0, viewportSize.y)
            return height == 0 ? 1.0 : width / height
        }()
        applyCameraConstants(transform: active.transform, camera: active.camera, aspectRatio: aspectRatio)
    }

    private func resolveActiveCamera(isPlaying: Bool) -> (entity: Entity, transform: TransformComponent, camera: CameraComponent, shouldUpdateEditorCamera: Bool)? {
        let selected: (Entity, TransformComponent, CameraComponent)? = {
            if !isPlaying {
                if let editorCamera = findEditorCamera() {
                    return editorCamera
                }
                return ecs.activeCamera(allowEditor: true, preferEditor: true)
            }
            return ecs.activeCamera(allowEditor: false) ?? ecs.activeCamera(allowEditor: true)
        }()
        guard let selected else { return nil }
        let shouldUpdateEditorCamera = !isPlaying && selected.2.isEditor
        return (selected.0, selected.1, selected.2, shouldUpdateEditorCamera)
    }

    private func findEditorCamera() -> (Entity, TransformComponent, CameraComponent)? {
        var result: (Entity, TransformComponent, CameraComponent)?
        ecs.viewCameras { entity, transform, camera in
            if result != nil { return }
            guard camera.isEditor, let transform else { return }
            result = (entity, transform, camera)
        }
        return result
    }

    private func applyCameraConstants(transform: TransformComponent, camera: CameraComponent, aspectRatio: Float) {
        _sceneConstants.viewMatrix = SceneRenderer.viewMatrix(from: transform)
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0
        _sceneConstants.skyViewMatrix[3][1] = 0
        _sceneConstants.skyViewMatrix[3][2] = 0
        _sceneConstants.projectionMatrix = SceneRenderer.projectionMatrix(from: camera, aspectRatio: aspectRatio)
        _sceneConstants.cameraPositionAndIBL = SIMD4<Float>(transform.position, 1.0)
    }

    public func onEvent(_ event: Event) {}

    private func updateLightOrbits(totalTime: Float) {
        let t = totalTime
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

    private func currentFrameForUpdates() -> FrameContext {
        if let lastFrameContext { return lastFrameContext }
        let frameTime = FrameTime(
            deltaTime: 0.0,
            unscaledDeltaTime: 0.0,
            timeScale: 1.0,
            fixedDeltaTime: 1.0 / 60.0,
            frameCount: 0,
            totalTime: 0.0,
            unscaledTotalTime: 0.0
        )
        let inputState = InputState(
            mousePosition: .zero,
            mouseDelta: .zero,
            scrollDelta: 0,
            mouseButtons: [],
            keys: [],
            viewportOrigin: .zero,
            viewportSize: .zero,
            textInput: ""
        )
        return FrameContext(time: frameTime, input: inputState)
    }

    private func layerIndex(for entity: Entity) -> Int32 {
        return ecs.get(LayerComponent.self, for: entity)?.index ?? LayerCatalog.defaultLayerIndex
    }

    func getSceneConstants() -> SceneConstants {
        _sceneConstants
    }

    func setSceneConstants(_ value: SceneConstants) {
        _sceneConstants = value
    }

    func getLightManager() -> LightManager {
        _lightManager
    }

    func getCachedBatchResult() -> Any? {
        _cachedBatchResult
    }

    func setCachedBatchResult(_ result: Any?) {
        _cachedBatchResult = result
    }

    func getCachedBatchFrameToken() -> UInt64 {
        _cachedBatchFrameToken
    }

    func setCachedBatchFrameToken(_ token: UInt64) {
        _cachedBatchFrameToken = token
    }

}
