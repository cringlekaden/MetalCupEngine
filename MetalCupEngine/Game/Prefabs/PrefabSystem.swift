/// PrefabSystem.swift
/// Applies prefab assets to instances by rehydrating non-Transform components.
/// Created by Kaden Cringle.
///
/// Note: The previous prefab flow instantiated entities without any prefab linkage.
/// This system keeps instances linked to prefab assets so changes can be reapplied.

import Foundation

public final class PrefabSystem {
    public static let shared = PrefabSystem()

    private var dirtyPrefabs = Set<AssetHandle>()
    private var prefabCache: [AssetHandle: PrefabDocument] = [:]
    private var loggedMissing = Set<AssetHandle>()

    private init() {}

    public func markAllDirty(handles: [AssetHandle]) {
        dirtyPrefabs.formUnion(handles)
        for handle in handles {
            prefabCache.removeValue(forKey: handle)
        }
    }

    public func markDirty(handle: AssetHandle) {
        dirtyPrefabs.insert(handle)
        prefabCache.removeValue(forKey: handle)
    }

    public func applyIfNeeded(scene: EngineScene) {
        guard !dirtyPrefabs.isEmpty else { return }
        let handles = dirtyPrefabs
        dirtyPrefabs.removeAll()
        applyPrefabs(handles: handles, to: scene)
    }

    public func applyPrefabs(handles: Set<AssetHandle>, to scene: EngineScene) {
        guard let database = Engine.assetDatabase else { return }
        for handle in handles {
            guard let prefab = loadPrefab(handle: handle, database: database) else { continue }
            let updated = apply(prefab: prefab, prefabHandle: handle, to: scene)
            if updated > 0 {
                print("PrefabApply: prefab=\(prefab.name) instances=\(updated) updated=\(updated)")
            }
        }
    }

    private func loadPrefab(handle: AssetHandle, database: AssetDatabase) -> PrefabDocument? {
        guard let url = database.assetURL(for: handle) else {
            logMissing(handle: handle)
            return nil
        }
        if let cached = prefabCache[handle] {
            return cached
        }
        do {
            let prefab = try PrefabSerializer.load(from: url)
            prefabCache[handle] = prefab
            return prefab
        } catch {
            print("WARN::PREFAB::Load failed \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func logMissing(handle: AssetHandle) {
        if loggedMissing.contains(handle) { return }
        loggedMissing.insert(handle)
        print("WARN::PREFAB::Missing asset for handle \(handle.rawValue.uuidString)")
    }

    private func apply(prefab: PrefabDocument, prefabHandle: AssetHandle, to scene: EngineScene) -> Int {
        let ecs = scene.ecs
        let prefabEntities = Dictionary(uniqueKeysWithValues: prefab.entities.map { ($0.localId, $0) })
        if prefabEntities.isEmpty { return 0 }

        var instanceMap: [UUID: [Entity]] = [:]
        for entity in ecs.allEntities() {
            guard let link = ecs.get(PrefabInstanceComponent.self, for: entity), link.prefabHandle == prefabHandle else { continue }
            instanceMap[link.instanceId, default: []].append(entity)
        }

        var updatedInstances = 0
        for (instanceId, entities) in instanceMap {
            var entityByLocalId: [UUID: Entity] = [:]
            for entity in entities {
                if let link = ecs.get(PrefabInstanceComponent.self, for: entity) {
                    entityByLocalId[link.prefabEntityId] = entity
                }
            }

            for (localId, prefabEntity) in prefabEntities where entityByLocalId[localId] == nil {
                let entityName = prefabEntity.components.name?.name ?? "Entity"
                let entity = ecs.createEntity(name: entityName)
                entityByLocalId[localId] = entity
                if let transform = prefabEntity.components.transform {
                    ecs.add(TransformComponent(
                        position: transform.position.toSIMD(),
                        rotation: transform.rotation.toSIMD(),
                        scale: transform.scale.toSIMD()
                    ), to: entity)
                } else {
                    ecs.add(TransformComponent(), to: entity)
                }
                ecs.add(PrefabInstanceComponent(prefabHandle: prefabHandle, prefabEntityId: localId, instanceId: instanceId), to: entity)
            }

            for (localId, entity) in entityByLocalId where prefabEntities[localId] == nil {
                ecs.destroyEntity(entity)
            }

            for (localId, prefabEntity) in prefabEntities {
                guard let entity = entityByLocalId[localId] else { continue }
                applyPrefabEntity(prefabEntity, to: entity, ecs: ecs)
            }
            updatedInstances += 1
        }
        return updatedInstances
    }

    private func applyPrefabEntity(_ prefabEntity: PrefabEntityDocument, to entity: Entity, ecs: SceneECS) {
        let overrides = ecs.get(PrefabOverrideComponent.self, for: entity)

        func isOverridden(_ type: PrefabOverrideType) -> Bool {
            return overrides?.contains(type) ?? false
        }

        if ecs.get(TransformComponent.self, for: entity) == nil {
            if let transform = prefabEntity.components.transform {
                ecs.add(TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotation.toSIMD(),
                    scale: transform.scale.toSIMD()
                ), to: entity)
            } else {
                ecs.add(TransformComponent(), to: entity)
            }
        }

        if !isOverridden(.name) {
            if let name = prefabEntity.components.name?.name {
                ecs.add(NameComponent(name: name), to: entity)
            }
        }

        if !isOverridden(.layer), let layer = prefabEntity.components.layer {
            ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
        }

        if !isOverridden(.meshRenderer) {
            if let meshRenderer = prefabEntity.components.meshRenderer {
                ecs.add(MeshRendererComponent(
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
                ), to: entity)
            } else {
                ecs.remove(MeshRendererComponent.self, from: entity)
            }
        }

        if !isOverridden(.material) {
            if let materialComponent = prefabEntity.components.materialComponent {
                ecs.add(MaterialComponent(materialHandle: materialComponent.materialHandle), to: entity)
            } else {
                ecs.remove(MaterialComponent.self, from: entity)
            }
        }

        if !isOverridden(.light) {
            if let light = prefabEntity.components.light {
                ecs.add(LightComponent(
                    type: light.type.toLightType(),
                    data: light.data.toLightData(),
                    direction: light.direction.toSIMD(),
                    range: light.range,
                    innerConeCos: light.innerConeCos,
                    outerConeCos: light.outerConeCos
                ), to: entity)
            } else {
                ecs.remove(LightComponent.self, from: entity)
            }
        }

        if !isOverridden(.lightOrbit) {
            if let lightOrbit = prefabEntity.components.lightOrbit {
                ecs.add(lightOrbit.toComponent(), to: entity)
            } else {
                ecs.remove(LightOrbitComponent.self, from: entity)
            }
        }

        if !isOverridden(.camera) {
            if let camera = prefabEntity.components.camera {
                ecs.add(camera.toComponent(), to: entity)
            } else {
                ecs.remove(CameraComponent.self, from: entity)
            }
        }

        if !isOverridden(.sky) {
            if let sky = prefabEntity.components.sky {
                ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
            } else {
                ecs.remove(SkyComponent.self, from: entity)
            }
        }

        if !isOverridden(.skyLight) {
            if let skyLight = prefabEntity.components.skyLight {
                ecs.add(SkyLightComponent(
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
                ), to: entity)
            } else {
                ecs.remove(SkyLightComponent.self, from: entity)
            }
        }

        if !isOverridden(.skyLightTag) {
            if prefabEntity.components.skyLightTag != nil {
                ecs.add(SkyLightTag(), to: entity)
            } else {
                ecs.remove(SkyLightTag.self, from: entity)
            }
        }

        if !isOverridden(.skySunTag) {
            if prefabEntity.components.skySunTag != nil {
                ecs.add(SkySunTag(), to: entity)
            } else {
                ecs.remove(SkySunTag.self, from: entity)
            }
        }
    }
}
