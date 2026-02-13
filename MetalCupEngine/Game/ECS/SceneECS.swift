/// SceneECS.swift
/// Defines the SceneECS types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

public struct Entity: Hashable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

public final class SceneECS {
    private var aliveEntities: Set<Entity> = []

    private var nameComponents: [Entity: NameComponent] = [:]
    private var transformComponents: [Entity: TransformComponent] = [:]
    private var meshRendererComponents: [Entity: MeshRendererComponent] = [:]
    private var materialComponents: [Entity: MaterialComponent] = [:]
    private var cameraComponents: [Entity: CameraComponent] = [:]
    private var lightComponents: [Entity: LightComponent] = [:]
    private var lightOrbitComponents: [Entity: LightOrbitComponent] = [:]
    private var skyComponents: [Entity: SkyComponent] = [:]
    private var skyLightComponents: [Entity: SkyLightComponent] = [:]
    private var skyLightTags: [Entity: SkyLightTag] = [:]
    private var skySunTags: [Entity: SkySunTag] = [:]

    public init() {}

    public func createEntity(name: String) -> Entity {
        let entity = Entity()
        aliveEntities.insert(entity)

        nameComponents[entity] = NameComponent(name: name)
        transformComponents[entity] = TransformComponent()

        return entity
    }

    public func createEntity(id: UUID, name: String? = nil) -> Entity {
        let entity = Entity(id: id)
        aliveEntities.insert(entity)
        if let name {
            nameComponents[entity] = NameComponent(name: name)
        }
        return entity
    }

    public func destroyEntity(_ e: Entity) {
        aliveEntities.remove(e)
        nameComponents.removeValue(forKey: e)
        transformComponents.removeValue(forKey: e)
        meshRendererComponents.removeValue(forKey: e)
        materialComponents.removeValue(forKey: e)
        cameraComponents.removeValue(forKey: e)
        lightComponents.removeValue(forKey: e)
        lightOrbitComponents.removeValue(forKey: e)
        skyComponents.removeValue(forKey: e)
        skyLightComponents.removeValue(forKey: e)
        skyLightTags.removeValue(forKey: e)
        skySunTags.removeValue(forKey: e)
    }

    public func clear() {
        aliveEntities.removeAll()
        nameComponents.removeAll()
        transformComponents.removeAll()
        meshRendererComponents.removeAll()
        materialComponents.removeAll()
        cameraComponents.removeAll()
        lightComponents.removeAll()
        lightOrbitComponents.removeAll()
        skyComponents.removeAll()
        skyLightComponents.removeAll()
        skyLightTags.removeAll()
        skySunTags.removeAll()
    }

    public func allEntities() -> [Entity] {
        return Array(aliveEntities)
    }

    public func add<T>(_ component: T, to entity: Entity) {
        switch component {
        case let value as NameComponent:
            nameComponents[entity] = value
        case let value as TransformComponent:
            transformComponents[entity] = value
        case let value as MeshRendererComponent:
            meshRendererComponents[entity] = value
        case let value as MaterialComponent:
            materialComponents[entity] = value
        case let value as CameraComponent:
            cameraComponents[entity] = value
        case let value as LightComponent:
            lightComponents[entity] = value
        case let value as LightOrbitComponent:
            lightOrbitComponents[entity] = value
        case let value as SkyComponent:
            skyComponents[entity] = value
        case let value as SkyLightComponent:
            skyLightComponents[entity] = value
        case let value as SkyLightTag:
            skyLightTags[entity] = value
        case let value as SkySunTag:
            skySunTags[entity] = value
        default:
            return
        }
    }

    public func remove<T>(_ type: T.Type, from entity: Entity) {
        switch type {
        case is NameComponent.Type:
            nameComponents.removeValue(forKey: entity)
        case is TransformComponent.Type:
            transformComponents.removeValue(forKey: entity)
        case is MeshRendererComponent.Type:
            meshRendererComponents.removeValue(forKey: entity)
        case is MaterialComponent.Type:
            materialComponents.removeValue(forKey: entity)
        case is CameraComponent.Type:
            cameraComponents.removeValue(forKey: entity)
        case is LightComponent.Type:
            lightComponents.removeValue(forKey: entity)
        case is LightOrbitComponent.Type:
            lightOrbitComponents.removeValue(forKey: entity)
        case is SkyComponent.Type:
            skyComponents.removeValue(forKey: entity)
        case is SkyLightComponent.Type:
            skyLightComponents.removeValue(forKey: entity)
        case is SkyLightTag.Type:
            skyLightTags.removeValue(forKey: entity)
        case is SkySunTag.Type:
            skySunTags.removeValue(forKey: entity)
        default:
            return
        }
    }

    public func get<T>(_ type: T.Type, for entity: Entity) -> T? {
        switch type {
        case is NameComponent.Type:
            return nameComponents[entity] as? T
        case is TransformComponent.Type:
            return transformComponents[entity] as? T
        case is MeshRendererComponent.Type:
            return meshRendererComponents[entity] as? T
        case is MaterialComponent.Type:
            return materialComponents[entity] as? T
        case is CameraComponent.Type:
            return cameraComponents[entity] as? T
        case is LightComponent.Type:
            return lightComponents[entity] as? T
        case is LightOrbitComponent.Type:
            return lightOrbitComponents[entity] as? T
        case is SkyComponent.Type:
            return skyComponents[entity] as? T
        case is SkyLightComponent.Type:
            return skyLightComponents[entity] as? T
        case is SkyLightTag.Type:
            return skyLightTags[entity] as? T
        case is SkySunTag.Type:
            return skySunTags[entity] as? T
        default:
            return nil
        }
    }

    public func has<T>(_ type: T.Type, _ entity: Entity) -> Bool {
        return get(type, for: entity) != nil
    }

    public func viewTransformMeshRenderer(_ body: (Entity, TransformComponent, MeshRendererComponent) -> Void) {
        for (entity, transform) in transformComponents {
            guard let meshRenderer = meshRendererComponents[entity] else { continue }
            body(entity, transform, meshRenderer)
        }
    }

    public func viewTransformMeshRendererArray() -> [(Entity, TransformComponent, MeshRendererComponent)] {
        var results: [(Entity, TransformComponent, MeshRendererComponent)] = []
        results.reserveCapacity(meshRendererComponents.count)

        for (entity, meshRenderer) in meshRendererComponents {
            guard let transform = transformComponents[entity] else { continue }
            results.append((entity, transform, meshRenderer))
        }

        return results
    }

    public func viewLights(_ body: (Entity, TransformComponent?, LightComponent) -> Void) {
        for (entity, light) in lightComponents {
            let transform = transformComponents[entity]
            body(entity, transform, light)
        }
    }

    public func viewLightOrbits(_ body: (Entity, TransformComponent?, LightOrbitComponent) -> Void) {
        for (entity, orbit) in lightOrbitComponents {
            let transform = transformComponents[entity]
            body(entity, transform, orbit)
        }
    }

    public func viewCameras(_ body: (Entity, TransformComponent?, CameraComponent) -> Void) {
        for (entity, camera) in cameraComponents {
            let transform = transformComponents[entity]
            body(entity, transform, camera)
        }
    }

    public func activeCamera() -> (Entity, TransformComponent, CameraComponent)? {
        if let primary = cameraComponents.first(where: { $0.value.isPrimary }) {
            if let transform = transformComponents[primary.key] {
                return (primary.key, transform, primary.value)
            }
        }
        if let entry = cameraComponents.first, let transform = transformComponents[entry.key] {
            return (entry.key, transform, entry.value)
        }
        return nil
    }

    public func viewSky(_ body: (Entity, SkyComponent) -> Void) {
        for (entity, sky) in skyComponents {
            body(entity, sky)
        }
    }

    public func viewSkyLights(_ body: (Entity, SkyLightComponent) -> Void) {
        for (entity, sky) in skyLightComponents {
            body(entity, sky)
        }
    }

    public func firstEntity(with type: SkySunTag.Type) -> Entity? {
        return skySunTags.first { _ in true }?.key
    }

    public func activeSkyLight() -> (Entity, SkyLightComponent)? {
        if let tagged = skyLightTags.first?.key, let sky = skyLightComponents[tagged] {
            return (tagged, sky)
        }
        if let entry = skyLightComponents.first {
            return (entry.key, entry.value)
        }
        return nil
    }

    public func entity(with id: UUID) -> Entity? {
        return aliveEntities.first { $0.id == id }
    }
}
