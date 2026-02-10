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
    private var lightComponents: [Entity: LightComponent] = [:]
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

    public func destroyEntity(_ e: Entity) {
        aliveEntities.remove(e)
        nameComponents.removeValue(forKey: e)
        transformComponents.removeValue(forKey: e)
        meshRendererComponents.removeValue(forKey: e)
        lightComponents.removeValue(forKey: e)
        skyComponents.removeValue(forKey: e)
        skyLightComponents.removeValue(forKey: e)
        skyLightTags.removeValue(forKey: e)
        skySunTags.removeValue(forKey: e)
    }

    public func add<T>(_ component: T, to entity: Entity) {
        switch component {
        case let value as NameComponent:
            nameComponents[entity] = value
        case let value as TransformComponent:
            transformComponents[entity] = value
        case let value as MeshRendererComponent:
            meshRendererComponents[entity] = value
        case let value as LightComponent:
            lightComponents[entity] = value
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

    public func get<T>(_ type: T.Type, for entity: Entity) -> T? {
        switch type {
        case is NameComponent.Type:
            return nameComponents[entity] as? T
        case is TransformComponent.Type:
            return transformComponents[entity] as? T
        case is MeshRendererComponent.Type:
            return meshRendererComponents[entity] as? T
        case is LightComponent.Type:
            return lightComponents[entity] as? T
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
}
