/// SceneSerializationService.swift
/// Owns scene serialization, application, and prefab instantiation.
/// Created by Kaden Cringle.

import Foundation
import simd

public final class SceneSerializationService {
    public init() {}

    public func toDocument(scene: EngineScene,
                           rendererSettingsOverride: RendererSettingsDTO? = nil,
                           physicsSettingsOverride: PhysicsSettingsDTO? = nil,
                           includeEditorEntities: Bool = true) -> SceneDocument {
        func overrideSet(for entity: Entity) -> Set<PrefabOverrideType> {
            return scene.ecs.get(PrefabOverrideComponent.self, for: entity)?.overridden ?? []
        }

        func shouldSerializeOverride(_ type: PrefabOverrideType, for entity: Entity) -> Bool {
            return overrideSet(for: entity).contains(type)
        }

        func transformDTO(for entity: Entity) -> TransformComponentDTO? {
            return scene.ecs.get(TransformComponent.self, for: entity).map { component in
                TransformComponentDTO(
                    position: Vector3DTO(component.position),
                    rotationQuat: Vector4DTO(component.rotation),
                    scale: Vector3DTO(component.scale)
                )
            }
        }

        func shouldSerializeEntity(_ entity: Entity) -> Bool {
            guard !includeEditorEntities else { return true }
            if let camera = scene.ecs.get(CameraComponent.self, for: entity), camera.isEditor {
                return false
            }
            return true
        }

        let entities = scene.ecs.allEntities().filter(shouldSerializeEntity).map { entity -> EntityDocument in
            let prefabLink = scene.ecs.get(PrefabInstanceComponent.self, for: entity)
            let prefabOverrides = scene.ecs.get(PrefabOverrideComponent.self, for: entity)
            let prefabOverridesDTO: PrefabOverrideComponentDTO? = prefabOverrides.map {
                PrefabOverrideComponentDTO(overriddenComponents: $0.overridden.map { $0.rawValue })
            }
            let parentId = scene.ecs.getParent(entity)?.id

            if let prefabLink {
                let components = ComponentsDocument(
                    name: shouldSerializeOverride(.name, for: entity)
                        ? scene.ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) }
                        : nil,
                    transform: transformDTO(for: entity),
                    layer: shouldSerializeOverride(.layer, for: entity)
                        ? scene.ecs.get(LayerComponent.self, for: entity).map { LayerComponentDTO(layerIndex: $0.index) }
                        : nil,
                    prefabLink: PrefabLinkComponentDTO(
                        prefabHandle: prefabLink.prefabHandle,
                        prefabEntityId: prefabLink.prefabEntityId,
                        instanceId: prefabLink.instanceId
                    ),
                    prefabOverrides: prefabOverridesDTO,
                    meshRenderer: shouldSerializeOverride(.meshRenderer, for: entity)
                        ? scene.ecs.get(MeshRendererComponent.self, for: entity).map { component in
                            MeshRendererComponentDTO(
                                meshHandle: component.meshHandle,
                                materialHandle: component.materialHandle,
                                submeshMaterialHandles: component.submeshMaterialHandles,
                                material: component.material.map { MaterialDTO(material: $0) },
                                albedoMapHandle: component.albedoMapHandle,
                                normalMapHandle: component.normalMapHandle,
                                metallicMapHandle: component.metallicMapHandle,
                                roughnessMapHandle: component.roughnessMapHandle,
                                mrMapHandle: component.mrMapHandle,
                                ormMapHandle: component.ormMapHandle,
                                aoMapHandle: component.aoMapHandle,
                                emissiveMapHandle: component.emissiveMapHandle
                            )
                        }
                        : nil,
                    skinnedMesh: shouldSerializeOverride(.skinnedMesh, for: entity)
                        ? scene.ecs.get(SkinnedMeshComponent.self, for: entity).map { SkinnedMeshComponentDTO(component: $0) }
                        : nil,
                    animator: shouldSerializeOverride(.animator, for: entity)
                        ? scene.ecs.get(AnimatorComponent.self, for: entity).map { AnimatorComponentDTO(component: $0) }
                        : nil,
                    materialComponent: shouldSerializeOverride(.material, for: entity)
                        ? scene.ecs.get(MaterialComponent.self, for: entity).map { MaterialComponentDTO(materialHandle: $0.materialHandle) }
                        : nil,
                    rigidbody: shouldSerializeOverride(.rigidbody, for: entity)
                        ? scene.ecs.get(RigidbodyComponent.self, for: entity).map { component in
                            RigidbodyComponentDTO(
                                enabled: component.isEnabled,
                                motionType: component.motionType.rawValue,
                                mass: component.mass,
                                friction: component.friction,
                                restitution: component.restitution,
                                linearDamping: component.linearDamping,
                                angularDamping: component.angularDamping,
                                gravityFactor: component.gravityFactor,
                                allowSleeping: component.allowSleeping,
                                ccdEnabled: component.ccdEnabled,
                                collisionLayer: component.collisionLayer
                            )
                        }
                        : nil,
                    collider: shouldSerializeOverride(.collider, for: entity)
                        ? scene.ecs.get(ColliderComponent.self, for: entity).map { component in
                            ColliderComponentDTO(component: component)
                        }
                        : nil,
                    light: shouldSerializeOverride(.light, for: entity)
                        ? scene.ecs.get(LightComponent.self, for: entity).map { component in
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
                        ? scene.ecs.get(LightOrbitComponent.self, for: entity).map { LightOrbitComponentDTO(component: $0) }
                        : nil,
                    camera: shouldSerializeOverride(.camera, for: entity)
                        ? scene.ecs.get(CameraComponent.self, for: entity).map { CameraComponentDTO(component: $0) }
                        : nil,
                    script: shouldSerializeOverride(.script, for: entity)
                        ? scene.ecs.get(ScriptComponent.self, for: entity).map { ScriptComponentDTO(component: $0) }
                        : nil,
                    characterController: scene.ecs.get(CharacterControllerComponent.self, for: entity).map { CharacterControllerComponentDTO(component: $0) },
                    audioSource: shouldSerializeOverride(.audioSource, for: entity)
                        ? scene.ecs.get(AudioSourceComponent.self, for: entity).map { AudioSourceComponentDTO(component: $0) }
                        : nil,
                    audioListener: shouldSerializeOverride(.audioListener, for: entity)
                        ? scene.ecs.get(AudioListenerComponent.self, for: entity).map { AudioListenerComponentDTO(component: $0) }
                        : nil,
                    sky: shouldSerializeOverride(.sky, for: entity)
                        ? scene.ecs.get(SkyComponent.self, for: entity).map { SkyComponentDTO(environmentMapHandle: $0.environmentMapHandle) }
                        : nil,
                    skyLight: shouldSerializeOverride(.skyLight, for: entity)
                        ? scene.ecs.get(SkyLightComponent.self, for: entity).map { component in
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
                    skyLightTag: shouldSerializeOverride(.skyLightTag, for: entity) && scene.ecs.has(SkyLightTag.self, entity) ? TagComponentDTO() : nil,
                    skySunTag: shouldSerializeOverride(.skySunTag, for: entity) && scene.ecs.has(SkySunTag.self, entity) ? TagComponentDTO() : nil
                )
                return EntityDocument(id: entity.id, parentId: parentId, components: components)
            }

            let components = ComponentsDocument(
                name: scene.ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) },
                transform: transformDTO(for: entity),
                layer: scene.ecs.get(LayerComponent.self, for: entity).map { component in
                    LayerComponentDTO(layerIndex: component.index)
                },
                meshRenderer: scene.ecs.get(MeshRendererComponent.self, for: entity).map { component in
                    MeshRendererComponentDTO(
                        meshHandle: component.meshHandle,
                        materialHandle: component.materialHandle,
                        submeshMaterialHandles: component.submeshMaterialHandles,
                        material: component.material.map { MaterialDTO(material: $0) },
                        albedoMapHandle: component.albedoMapHandle,
                        normalMapHandle: component.normalMapHandle,
                        metallicMapHandle: component.metallicMapHandle,
                        roughnessMapHandle: component.roughnessMapHandle,
                        mrMapHandle: component.mrMapHandle,
                        ormMapHandle: component.ormMapHandle,
                        aoMapHandle: component.aoMapHandle,
                        emissiveMapHandle: component.emissiveMapHandle
                    )
                },
                skinnedMesh: scene.ecs.get(SkinnedMeshComponent.self, for: entity).map { component in
                    SkinnedMeshComponentDTO(component: component)
                },
                animator: scene.ecs.get(AnimatorComponent.self, for: entity).map { component in
                    AnimatorComponentDTO(component: component)
                },
                materialComponent: scene.ecs.get(MaterialComponent.self, for: entity).map { component in
                    MaterialComponentDTO(materialHandle: component.materialHandle)
                },
                rigidbody: scene.ecs.get(RigidbodyComponent.self, for: entity).map { component in
                    RigidbodyComponentDTO(
                        enabled: component.isEnabled,
                        motionType: component.motionType.rawValue,
                        mass: component.mass,
                        friction: component.friction,
                        restitution: component.restitution,
                        linearDamping: component.linearDamping,
                        angularDamping: component.angularDamping,
                        gravityFactor: component.gravityFactor,
                        allowSleeping: component.allowSleeping,
                        ccdEnabled: component.ccdEnabled,
                        collisionLayer: component.collisionLayer
                    )
                },
                collider: scene.ecs.get(ColliderComponent.self, for: entity).map { component in
                    ColliderComponentDTO(component: component)
                },
                light: scene.ecs.get(LightComponent.self, for: entity).map { component in
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
                lightOrbit: scene.ecs.get(LightOrbitComponent.self, for: entity).map { component in
                    LightOrbitComponentDTO(component: component)
                },
                camera: scene.ecs.get(CameraComponent.self, for: entity).map { component in
                    CameraComponentDTO(component: component)
                },
                script: scene.ecs.get(ScriptComponent.self, for: entity).map { component in
                    ScriptComponentDTO(component: component)
                },
                characterController: scene.ecs.get(CharacterControllerComponent.self, for: entity).map { component in
                    CharacterControllerComponentDTO(component: component)
                },
                audioSource: scene.ecs.get(AudioSourceComponent.self, for: entity).map { component in
                    AudioSourceComponentDTO(component: component)
                },
                audioListener: scene.ecs.get(AudioListenerComponent.self, for: entity).map { component in
                    AudioListenerComponentDTO(component: component)
                },
                sky: scene.ecs.get(SkyComponent.self, for: entity).map { component in
                    SkyComponentDTO(environmentMapHandle: component.environmentMapHandle)
                },
                skyLight: scene.ecs.get(SkyLightComponent.self, for: entity).map { component in
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
                skyLightTag: scene.ecs.get(SkyLightTag.self, for: entity).map { _ in TagComponentDTO() },
                skySunTag: scene.ecs.get(SkySunTag.self, for: entity).map { _ in TagComponentDTO() }
            )
            return EntityDocument(id: entity.id, parentId: parentId, components: components)
        }
        return SceneDocument(
            id: scene.id,
            name: scene.sceneName,
            entities: entities,
            rendererSettingsOverride: rendererSettingsOverride,
            physicsSettingsOverride: physicsSettingsOverride
        )
    }

    public func apply(document: SceneDocument, to scene: EngineScene) {
        scene.prepareForSceneDocumentApply()
        scene.ecs.clear()
        scene.setSceneName(document.name)
        let physicsDefaults = scene.engineContext?.physicsSettings ?? PhysicsSettings()
        var prefabHandles = Set<AssetHandle>()
        var entitiesById: [UUID: Entity] = [:]
        for entityDoc in document.entities {
            let entity = scene.ecs.createEntity(id: entityDoc.id, name: entityDoc.components.name?.name)
            entitiesById[entity.id] = entity
            if let transform = entityDoc.components.transform {
                let component = TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotationQuat.toSIMD(),
                    scale: transform.scale.toSIMD()
                )
                _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                                  default: component,
                                                                  source: .serialization)
            } else {
                _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                                  default: TransformComponent(),
                                                                  source: .serialization)
            }

            if let prefabLink = entityDoc.components.prefabLink {
                let component = PrefabInstanceComponent(
                    prefabHandle: prefabLink.prefabHandle,
                    prefabEntityId: prefabLink.prefabEntityId,
                    instanceId: prefabLink.instanceId
                )
                scene.ecs.add(component, to: entity)
                prefabHandles.insert(prefabLink.prefabHandle)
                if let overrides = entityDoc.components.prefabOverrides {
                    let overrideSet = Set(overrides.overriddenComponents.compactMap { PrefabOverrideType(rawValue: $0) })
                    scene.ecs.add(PrefabOverrideComponent(overridden: overrideSet), to: entity)
                }
                if let layer = entityDoc.components.layer {
                    scene.ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
                }
                if let name = entityDoc.components.name {
                    scene.ecs.add(NameComponent(name: name.name), to: entity)
                }
                if let meshRenderer = entityDoc.components.meshRenderer {
                    let component = MeshRendererComponent(
                        meshHandle: meshRenderer.meshHandle,
                        materialHandle: meshRenderer.materialHandle,
                        submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                        material: meshRenderer.material?.toMaterial(),
                        albedoMapHandle: meshRenderer.albedoMapHandle,
                        normalMapHandle: meshRenderer.normalMapHandle,
                        metallicMapHandle: meshRenderer.metallicMapHandle,
                        roughnessMapHandle: meshRenderer.roughnessMapHandle,
                        mrMapHandle: meshRenderer.mrMapHandle,
                        ormMapHandle: meshRenderer.ormMapHandle,
                        aoMapHandle: meshRenderer.aoMapHandle,
                        emissiveMapHandle: meshRenderer.emissiveMapHandle
                    )
                    scene.ecs.add(component, to: entity)
                }
                if let skinnedMesh = entityDoc.components.skinnedMesh {
                    scene.ecs.add(skinnedMesh.toComponent(), to: entity)
                }
                if let animator = entityDoc.components.animator {
                    scene.ecs.add(animator.toComponent(), to: entity)
                }
                if let materialComponent = entityDoc.components.materialComponent {
                    scene.ecs.add(MaterialComponent(materialHandle: materialComponent.materialHandle), to: entity)
                }
                if let rigidbody = entityDoc.components.rigidbody {
                    scene.ecs.add(rigidbody.toComponent(defaults: physicsDefaults), to: entity)
                }
                if let collider = entityDoc.components.collider {
                    scene.ecs.add(collider.toComponent(), to: entity)
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
                    scene.ecs.add(component, to: entity)
#if DEBUG
                    MC_ASSERT(component.castsShadows == light.castsShadows, "Light castsShadows mismatch after load.")
#endif
                }
                if let lightOrbit = entityDoc.components.lightOrbit {
                    scene.ecs.add(lightOrbit.toComponent(), to: entity)
                }
                if let camera = entityDoc.components.camera {
                    scene.ecs.add(camera.toComponent(), to: entity)
                }
                if let script = entityDoc.components.script {
                    scene.ecs.add(script.toComponent(), to: entity)
                }
                if let controller = entityDoc.components.characterController {
                    scene.ecs.add(controller.toComponent(), to: entity)
                }
                if let audioSource = entityDoc.components.audioSource {
                    scene.ecs.add(audioSource.toComponent(), to: entity)
                }
                if let audioListener = entityDoc.components.audioListener {
                    scene.ecs.add(audioListener.toComponent(), to: entity)
                }
                if let sky = entityDoc.components.sky {
                    scene.ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
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
                    scene.ecs.add(component, to: entity)
                }
                if entityDoc.components.skyLightTag != nil {
                    scene.ecs.add(SkyLightTag(), to: entity)
                }
                if entityDoc.components.skySunTag != nil {
                    scene.ecs.add(SkySunTag(), to: entity)
                }
                continue
            }

            if let layer = entityDoc.components.layer {
                scene.ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                scene.ecs.add(LayerComponent(), to: entity)
            }
            if let meshRenderer = entityDoc.components.meshRenderer {
                let component = MeshRendererComponent(
                    meshHandle: meshRenderer.meshHandle,
                    materialHandle: meshRenderer.materialHandle,
                    submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                    material: meshRenderer.material?.toMaterial(),
                    albedoMapHandle: meshRenderer.albedoMapHandle,
                    normalMapHandle: meshRenderer.normalMapHandle,
                    metallicMapHandle: meshRenderer.metallicMapHandle,
                    roughnessMapHandle: meshRenderer.roughnessMapHandle,
                    mrMapHandle: meshRenderer.mrMapHandle,
                    ormMapHandle: meshRenderer.ormMapHandle,
                    aoMapHandle: meshRenderer.aoMapHandle,
                    emissiveMapHandle: meshRenderer.emissiveMapHandle
                )
                scene.ecs.add(component, to: entity)
            }
            if let skinnedMesh = entityDoc.components.skinnedMesh {
                scene.ecs.add(skinnedMesh.toComponent(), to: entity)
            }
            if let animator = entityDoc.components.animator {
                scene.ecs.add(animator.toComponent(), to: entity)
            }
            if let materialComponent = entityDoc.components.materialComponent {
                let component = MaterialComponent(materialHandle: materialComponent.materialHandle)
                scene.ecs.add(component, to: entity)
            }
            if let rigidbody = entityDoc.components.rigidbody {
                scene.ecs.add(rigidbody.toComponent(defaults: physicsDefaults), to: entity)
            }
            if let collider = entityDoc.components.collider {
                scene.ecs.add(collider.toComponent(), to: entity)
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
                scene.ecs.add(component, to: entity)
            }
            if let lightOrbit = entityDoc.components.lightOrbit {
                scene.ecs.add(lightOrbit.toComponent(), to: entity)
            }
            if let camera = entityDoc.components.camera {
                scene.ecs.add(camera.toComponent(), to: entity)
            }
            if let rigidbody = entityDoc.components.rigidbody {
                scene.ecs.add(rigidbody.toComponent(), to: entity)
            }
            if let collider = entityDoc.components.collider {
                scene.ecs.add(collider.toComponent(), to: entity)
            }
            if let script = entityDoc.components.script {
                scene.ecs.add(script.toComponent(), to: entity)
            }
            if let controller = entityDoc.components.characterController {
                scene.ecs.add(controller.toComponent(), to: entity)
            }
            if let audioSource = entityDoc.components.audioSource {
                scene.ecs.add(audioSource.toComponent(), to: entity)
            }
            if let audioListener = entityDoc.components.audioListener {
                scene.ecs.add(audioListener.toComponent(), to: entity)
            }
            if let sky = entityDoc.components.sky {
                scene.ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
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
                scene.ecs.add(component, to: entity)
            }
            if entityDoc.components.skyLightTag != nil {
                scene.ecs.add(SkyLightTag(), to: entity)
            }
            if entityDoc.components.skySunTag != nil {
                scene.ecs.add(SkySunTag(), to: entity)
            }
        }

        for entityDoc in document.entities {
            guard let entity = entitiesById[entityDoc.id] else { continue }
            if let parentId = entityDoc.parentId, let parent = entitiesById[parentId] {
                _ = scene.ecs.setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = scene.ecs.unparent(entity, keepWorldTransform: false)
            }
        }
        if !prefabHandles.isEmpty {
            scene.prefabSystem?.applyPrefabs(handles: prefabHandles, to: scene)
        }
        scene.ensureSceneCameraEntity()
        scene.resetSceneEditorCameraController()
    }

    @discardableResult
    public func instantiate(prefab: PrefabDocument,
                            prefabHandle: AssetHandle?,
                            into scene: EngineScene) -> [Entity] {
        var created: [Entity] = []
        created.reserveCapacity(prefab.entities.count)
        let instanceId = UUID()
        var entityByLocalId: [UUID: Entity] = [:]

        for entityDoc in prefab.entities {
            let entityName = entityDoc.components.name?.name ?? "Entity"
            let entity = scene.ecs.createEntity(name: entityName)
            created.append(entity)
            entityByLocalId[entityDoc.localId] = entity

            if let transform = entityDoc.components.transform {
                let component = TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotationQuat.toSIMD(),
                    scale: transform.scale.toSIMD()
                )
                _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                                  default: component,
                                                                  source: .prefab)
            } else {
                _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                                  default: TransformComponent(),
                                                                  source: .prefab)
            }
            if let layer = entityDoc.components.layer {
                scene.ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                scene.ecs.add(LayerComponent(), to: entity)
            }
            if let prefabHandle {
                let link = PrefabInstanceComponent(prefabHandle: prefabHandle, prefabEntityId: entityDoc.localId, instanceId: instanceId)
                scene.ecs.add(link, to: entity)
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
                    submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                    material: meshRenderer.material?.toMaterial(),
                    albedoMapHandle: meshRenderer.albedoMapHandle,
                    normalMapHandle: meshRenderer.normalMapHandle,
                    metallicMapHandle: meshRenderer.metallicMapHandle,
                    roughnessMapHandle: meshRenderer.roughnessMapHandle,
                    mrMapHandle: meshRenderer.mrMapHandle,
                    ormMapHandle: meshRenderer.ormMapHandle,
                    aoMapHandle: meshRenderer.aoMapHandle,
                    emissiveMapHandle: meshRenderer.emissiveMapHandle
                )
                scene.ecs.add(component, to: entity)
            }
            if let skinnedMesh = entityDoc.components.skinnedMesh {
                scene.ecs.add(skinnedMesh.toComponent(), to: entity)
            }
            if let animator = entityDoc.components.animator {
                scene.ecs.add(animator.toComponent(), to: entity)
            }
            if let materialComponent = entityDoc.components.materialComponent {
                let component = MaterialComponent(materialHandle: materialComponent.materialHandle)
                scene.ecs.add(component, to: entity)
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
                scene.ecs.add(component, to: entity)
            }
            if let lightOrbit = entityDoc.components.lightOrbit {
                scene.ecs.add(lightOrbit.toComponent(), to: entity)
            }
            if let camera = entityDoc.components.camera {
                scene.ecs.add(camera.toComponent(), to: entity)
            }
            if let script = entityDoc.components.script {
                scene.ecs.add(script.toComponent(), to: entity)
            }
            if let audioSource = entityDoc.components.audioSource {
                scene.ecs.add(audioSource.toComponent(), to: entity)
            }
            if let audioListener = entityDoc.components.audioListener {
                scene.ecs.add(audioListener.toComponent(), to: entity)
            }
            if let sky = entityDoc.components.sky {
                scene.ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
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
                scene.ecs.add(component, to: entity)
            }
            if entityDoc.components.skyLightTag != nil {
                scene.ecs.add(SkyLightTag(), to: entity)
            }
            if entityDoc.components.skySunTag != nil {
                scene.ecs.add(SkySunTag(), to: entity)
            }
        }

        for entityDoc in prefab.entities {
            guard let entity = entityByLocalId[entityDoc.localId] else { continue }
            if let parentLocalId = entityDoc.parentLocalId,
               let parent = entityByLocalId[parentLocalId] {
                _ = scene.ecs.setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = scene.ecs.unparent(entity, keepWorldTransform: false)
            }
        }

        scene.ensureSceneCameraEntity()
        return created
    }
}
