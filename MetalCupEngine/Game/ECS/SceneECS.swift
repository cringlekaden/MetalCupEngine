/// SceneECS.swift
/// Defines the SceneECS types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

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
    private var layerComponents: [Entity: LayerComponent] = [:]
    private var rigidbodyComponents: [Entity: RigidbodyComponent] = [:]
    private var colliderComponents: [Entity: ColliderComponent] = [:]
    private var prefabInstanceComponents: [Entity: PrefabInstanceComponent] = [:]
    private var prefabOverrideComponents: [Entity: PrefabOverrideComponent] = [:]
    private var meshRendererComponents: [Entity: MeshRendererComponent] = [:]
    private var materialComponents: [Entity: MaterialComponent] = [:]
    private var cameraComponents: [Entity: CameraComponent] = [:]
    private var lightComponents: [Entity: LightComponent] = [:]
    private var lightOrbitComponents: [Entity: LightOrbitComponent] = [:]
    private var skyComponents: [Entity: SkyComponent] = [:]
    private var skyLightComponents: [Entity: SkyLightComponent] = [:]
    private var skyLightTags: [Entity: SkyLightTag] = [:]
    private var skySunTags: [Entity: SkySunTag] = [:]

    private var parentByEntity: [Entity: Entity] = [:]
    private var childrenByEntity: [Entity: [Entity]] = [:]
    private var rootEntities: [Entity] = []
    private var orderedEntitiesCache: [Entity] = []
    private var orderedEntitiesDirty = true

    private var worldMatrixCache: [Entity: matrix_float4x4] = [:]
    private var dirtyTransforms: Set<Entity> = []

    public init() {}

    public func createEntity(name: String) -> Entity {
        let entity = Entity()
        aliveEntities.insert(entity)

        nameComponents[entity] = NameComponent(name: name)
        transformComponents[entity] = TransformComponent()
        layerComponents[entity] = LayerComponent()
        rootEntities.append(entity)
        orderedEntitiesDirty = true
        markTransformDirty(entity)
        return entity
    }

    public func createEntity(id: UUID, name: String? = nil) -> Entity {
        let entity = Entity(id: id)
        aliveEntities.insert(entity)
        if let name {
            nameComponents[entity] = NameComponent(name: name)
        }
        layerComponents[entity] = LayerComponent()
        rootEntities.append(entity)
        orderedEntitiesDirty = true
        markTransformDirty(entity)
        return entity
    }

    public func destroyEntity(_ e: Entity) {
        guard aliveEntities.contains(e) else { return }
        let descendants = gatherDescendants(of: e)
        for descendant in descendants.reversed() {
            destroySingleEntity(descendant)
        }
        destroySingleEntity(e)
        orderedEntitiesDirty = true
    }

    public func clear() {
        aliveEntities.removeAll()
        nameComponents.removeAll()
        transformComponents.removeAll()
        layerComponents.removeAll()
        rigidbodyComponents.removeAll()
        colliderComponents.removeAll()
        prefabInstanceComponents.removeAll()
        prefabOverrideComponents.removeAll()
        meshRendererComponents.removeAll()
        materialComponents.removeAll()
        cameraComponents.removeAll()
        lightComponents.removeAll()
        lightOrbitComponents.removeAll()
        skyComponents.removeAll()
        skyLightComponents.removeAll()
        skyLightTags.removeAll()
        skySunTags.removeAll()
        parentByEntity.removeAll()
        childrenByEntity.removeAll()
        rootEntities.removeAll()
        orderedEntitiesCache.removeAll()
        orderedEntitiesDirty = true
        worldMatrixCache.removeAll()
        dirtyTransforms.removeAll()
    }

    public func allEntities() -> [Entity] {
        refreshEntityOrderIfNeeded()
        return orderedEntitiesCache
    }

    public func rootLevelEntities() -> [Entity] {
        return rootEntities.filter { aliveEntities.contains($0) }
    }

    public func forEachEntity(_ body: (Entity) -> Void) {
        for entity in allEntities() {
            body(entity)
        }
    }

    public func add<T>(_ component: T, to entity: Entity) {
        switch component {
        case let value as NameComponent:
            nameComponents[entity] = value
        case let value as TransformComponent:
            transformComponents[entity] = value
            markTransformDirty(entity)
        case let value as LayerComponent:
            layerComponents[entity] = value
        case let value as ParentComponent:
            if let parent = self.entity(with: value.parent) {
                _ = setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = setParent(entity, nil, keepWorldTransform: false)
            }
        case let value as ChildrenComponent:
            setChildrenOrder(from: value, for: entity)
        case let value as RigidbodyComponent:
            rigidbodyComponents[entity] = value
        case let value as ColliderComponent:
            colliderComponents[entity] = value
        case let value as PrefabInstanceComponent:
            prefabInstanceComponents[entity] = value
        case let value as PrefabOverrideComponent:
            prefabOverrideComponents[entity] = value
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
            markTransformDirty(entity)
        case is LayerComponent.Type:
            layerComponents.removeValue(forKey: entity)
        case is ParentComponent.Type:
            _ = setParent(entity, nil, keepWorldTransform: false)
        case is ChildrenComponent.Type:
            for child in getChildren(entity) {
                _ = setParent(child, nil, keepWorldTransform: false)
            }
        case is RigidbodyComponent.Type:
            rigidbodyComponents.removeValue(forKey: entity)
        case is ColliderComponent.Type:
            colliderComponents.removeValue(forKey: entity)
        case is PrefabInstanceComponent.Type:
            prefabInstanceComponents.removeValue(forKey: entity)
        case is PrefabOverrideComponent.Type:
            prefabOverrideComponents.removeValue(forKey: entity)
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
        case is LayerComponent.Type:
            return layerComponents[entity] as? T
        case is ParentComponent.Type:
            return parentByEntity[entity].map { ParentComponent(parent: $0.id) } as? T
        case is ChildrenComponent.Type:
            let children = childrenByEntity[entity]?.map { $0.id } ?? []
            return ChildrenComponent(children: children) as? T
        case is RigidbodyComponent.Type:
            return rigidbodyComponents[entity] as? T
        case is ColliderComponent.Type:
            return colliderComponents[entity] as? T
        case is PrefabInstanceComponent.Type:
            return prefabInstanceComponents[entity] as? T
        case is PrefabOverrideComponent.Type:
            return prefabOverrideComponents[entity] as? T
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

    public func getParent(_ entity: Entity) -> Entity? {
        return parentByEntity[entity]
    }

    public func getChildren(_ parent: Entity) -> [Entity] {
        return (childrenByEntity[parent] ?? []).filter { aliveEntities.contains($0) }
    }

    public func isDescendant(_ candidate: Entity, of ancestor: Entity) -> Bool {
        var current = getParent(candidate)
        while let value = current {
            if value == ancestor { return true }
            current = getParent(value)
        }
        return false
    }

    @discardableResult
    public func setParent(_ child: Entity, _ newParent: Entity?, keepWorldTransform: Bool = true) -> Bool {
        guard aliveEntities.contains(child) else { return false }
        if let newParent {
            guard aliveEntities.contains(newParent), child != newParent else { return false }
            if isDescendant(newParent, of: child) { return false }
        }

        let worldBefore = keepWorldTransform ? worldMatrix(for: child) : matrix_identity_float4x4
        let oldParent = parentByEntity[child]
        if oldParent == newParent {
            return true
        }

        if let oldParent {
            removeChild(child, from: oldParent)
        } else {
            rootEntities.removeAll { $0 == child }
        }

        if let newParent {
            parentByEntity[child] = newParent
            appendChild(child, to: newParent)
        } else {
            parentByEntity.removeValue(forKey: child)
            rootEntities.append(child)
        }

        orderedEntitiesDirty = true
        markTransformDirty(child)

        if keepWorldTransform {
            let parentWorld = newParent.map { worldMatrix(for: $0) } ?? matrix_identity_float4x4
            let localMatrix = simd_inverse(parentWorld) * worldBefore
            let decomposed = TransformMath.decomposeMatrix(localMatrix)
            transformComponents[child] = TransformComponent(
                position: decomposed.position,
                rotation: decomposed.rotation,
                scale: decomposed.scale
            )
            markTransformDirty(child)
        }

        return true
    }

    @discardableResult
    public func unparent(_ child: Entity, keepWorldTransform: Bool = true) -> Bool {
        return setParent(child, nil, keepWorldTransform: keepWorldTransform)
    }

    @discardableResult
    public func reorderChild(parent: Entity?, child: Entity, newIndex: Int) -> Bool {
        guard aliveEntities.contains(child) else { return false }
        if let parent {
            guard parentByEntity[child] == parent else { return false }
            guard var children = childrenByEntity[parent] else { return false }
            guard let currentIndex = children.firstIndex(of: child) else { return false }
            let clamped = max(0, min(newIndex, max(0, children.count - 1)))
            if currentIndex == clamped { return true }
            children.remove(at: currentIndex)
            children.insert(child, at: clamped)
            childrenByEntity[parent] = children
        } else {
            guard parentByEntity[child] == nil else { return false }
            guard let currentIndex = rootEntities.firstIndex(of: child) else { return false }
            let clamped = max(0, min(newIndex, max(0, rootEntities.count - 1)))
            if currentIndex == clamped { return true }
            rootEntities.remove(at: currentIndex)
            rootEntities.insert(child, at: clamped)
        }
        orderedEntitiesDirty = true
        return true
    }

    public func worldMatrix(for entity: Entity) -> matrix_float4x4 {
        if !dirtyTransforms.contains(entity), let cached = worldMatrixCache[entity] {
            return cached
        }

        let localTransform = transformComponents[entity] ?? TransformComponent()
        let localMatrix = TransformMath.makeMatrix(
            position: localTransform.position,
            rotation: localTransform.rotation,
            scale: localTransform.scale
        )

        let resolvedWorldMatrix: matrix_float4x4
        if let parent = parentByEntity[entity] {
            resolvedWorldMatrix = worldMatrix(for: parent) * localMatrix
        } else {
            resolvedWorldMatrix = localMatrix
        }

        worldMatrixCache[entity] = resolvedWorldMatrix
        dirtyTransforms.remove(entity)
        return resolvedWorldMatrix
    }

    public func worldTransform(for entity: Entity) -> TransformComponent {
        let decomposed = TransformMath.decomposeMatrix(worldMatrix(for: entity))
        return TransformComponent(
            position: decomposed.position,
            rotation: decomposed.rotation,
            scale: decomposed.scale
        )
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

    public func activeCamera(allowEditor: Bool = true, preferEditor: Bool = false) -> (Entity, TransformComponent, CameraComponent)? {
        let candidates = cameraComponents.filter { allowEditor || !$0.value.isEditor }
        if preferEditor {
            if let primaryEditor = candidates.first(where: { $0.value.isEditor && $0.value.isPrimary }),
               let transform = transformComponents[primaryEditor.key] {
                return (primaryEditor.key, transform, primaryEditor.value)
            }
            if let editor = candidates.first(where: { $0.value.isEditor }),
               let transform = transformComponents[editor.key] {
                return (editor.key, transform, editor.value)
            }
        }
        if let primary = candidates.first(where: { $0.value.isPrimary }),
           let transform = transformComponents[primary.key] {
            return (primary.key, transform, primary.value)
        }
        if let entry = candidates.first, let transform = transformComponents[entry.key] {
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

    private func gatherDescendants(of entity: Entity) -> [Entity] {
        var output: [Entity] = []
        for child in childrenByEntity[entity] ?? [] {
            output.append(child)
            output.append(contentsOf: gatherDescendants(of: child))
        }
        return output
    }

    private func destroySingleEntity(_ e: Entity) {
        if let parent = parentByEntity[e] {
            removeChild(e, from: parent)
            parentByEntity.removeValue(forKey: e)
        } else {
            rootEntities.removeAll { $0 == e }
        }

        if let children = childrenByEntity[e] {
            for child in children {
                parentByEntity.removeValue(forKey: child)
                rootEntities.append(child)
            }
        }
        childrenByEntity.removeValue(forKey: e)

        aliveEntities.remove(e)
        nameComponents.removeValue(forKey: e)
        transformComponents.removeValue(forKey: e)
        layerComponents.removeValue(forKey: e)
        rigidbodyComponents.removeValue(forKey: e)
        colliderComponents.removeValue(forKey: e)
        prefabInstanceComponents.removeValue(forKey: e)
        prefabOverrideComponents.removeValue(forKey: e)
        meshRendererComponents.removeValue(forKey: e)
        materialComponents.removeValue(forKey: e)
        cameraComponents.removeValue(forKey: e)
        lightComponents.removeValue(forKey: e)
        lightOrbitComponents.removeValue(forKey: e)
        skyComponents.removeValue(forKey: e)
        skyLightComponents.removeValue(forKey: e)
        skyLightTags.removeValue(forKey: e)
        skySunTags.removeValue(forKey: e)
        worldMatrixCache.removeValue(forKey: e)
        dirtyTransforms.remove(e)
    }

    private func appendChild(_ child: Entity, to parent: Entity) {
        var children = childrenByEntity[parent] ?? []
        children.removeAll { $0 == child }
        children.append(child)
        childrenByEntity[parent] = children
    }

    private func removeChild(_ child: Entity, from parent: Entity) {
        guard var children = childrenByEntity[parent] else { return }
        children.removeAll { $0 == child }
        childrenByEntity[parent] = children
    }

    private func refreshEntityOrderIfNeeded() {
        guard orderedEntitiesDirty else { return }
        var ordered: [Entity] = []
        ordered.reserveCapacity(aliveEntities.count)
        for root in rootEntities where aliveEntities.contains(root) {
            appendSubtree(root, to: &ordered)
        }
        // Fallback for older/invalid data where an alive entity isn't rooted.
        if ordered.count != aliveEntities.count {
            for entity in aliveEntities where !ordered.contains(entity) {
                ordered.append(entity)
            }
        }
        orderedEntitiesCache = ordered
        orderedEntitiesDirty = false
    }

    private func appendSubtree(_ entity: Entity, to list: inout [Entity]) {
        guard aliveEntities.contains(entity) else { return }
        list.append(entity)
        for child in childrenByEntity[entity] ?? [] {
            appendSubtree(child, to: &list)
        }
    }

    private func markTransformDirty(_ entity: Entity) {
        dirtyTransforms.insert(entity)
        worldMatrixCache.removeValue(forKey: entity)
        for child in childrenByEntity[entity] ?? [] {
            markTransformDirty(child)
        }
    }

    private func setChildrenOrder(from component: ChildrenComponent, for parent: Entity) {
        guard aliveEntities.contains(parent) else { return }
        var reordered: [Entity] = []
        reordered.reserveCapacity(component.children.count)
        for id in component.children {
            guard let child = entity(with: id), parentByEntity[child] == parent else { continue }
            reordered.append(child)
        }
        if let existing = childrenByEntity[parent] {
            for child in existing where !reordered.contains(child) {
                reordered.append(child)
            }
        }
        childrenByEntity[parent] = reordered
        orderedEntitiesDirty = true
    }
}
