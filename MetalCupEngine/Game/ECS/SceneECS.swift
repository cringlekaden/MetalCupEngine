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

public enum SceneECSChangeKind: Int32 {
    case entityCreated = 0
    case entityDestroyed = 1
    case componentAdded = 2
    case componentRemoved = 3
    case componentEnabled = 4
    case componentDisabled = 5
}

public enum SceneECSComponentType: Int32 {
    case name = 0
    case transform = 1
    case layer = 2
    case parent = 3
    case children = 4
    case rigidbody = 5
    case collider = 6
    case prefabInstance = 7
    case prefabOverride = 8
    case meshRenderer = 9
    case material = 10
    case camera = 11
    case script = 12
    case light = 13
    case lightOrbit = 14
    case sky = 15
    case skyLight = 16
    case skyLightTag = 17
    case skySunTag = 18
}

public struct SceneECSChange {
    public let kind: SceneECSChangeKind
    public let entityId: UUID
    public let componentType: SceneECSComponentType?

    public init(kind: SceneECSChangeKind, entityId: UUID, componentType: SceneECSComponentType? = nil) {
        self.kind = kind
        self.entityId = entityId
        self.componentType = componentType
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
    private var scriptComponents: [Entity: ScriptComponent] = [:]
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
    private var stableOrderedEntitiesCache: [Entity] = []
    private var stableOrderedEntitiesDirty = true

    private var worldMatrixCache: [Entity: matrix_float4x4] = [:]
    private var dirtyTransforms: Set<Entity> = []
    private var changeQueue: [SceneECSChange] = []

    public init() {
        changeQueue.reserveCapacity(256)
    }

    public func createEntity(name: String) -> Entity {
        let entity = Entity()
        aliveEntities.insert(entity)
        enqueueChange(.entityCreated, entity: entity)

        nameComponents[entity] = NameComponent(name: name)
        enqueueChange(.componentAdded, entity: entity, componentType: .name)
        transformComponents[entity] = TransformComponent()
        enqueueChange(.componentAdded, entity: entity, componentType: .transform)
        layerComponents[entity] = LayerComponent()
        enqueueChange(.componentAdded, entity: entity, componentType: .layer)
        rootEntities.append(entity)
        orderedEntitiesDirty = true
        markTransformDirty(entity)
        return entity
    }

    public func createEntity(id: UUID, name: String? = nil) -> Entity {
        let entity = Entity(id: id)
        aliveEntities.insert(entity)
        enqueueChange(.entityCreated, entity: entity)
        if let name {
            nameComponents[entity] = NameComponent(name: name)
            enqueueChange(.componentAdded, entity: entity, componentType: .name)
        }
        layerComponents[entity] = LayerComponent()
        enqueueChange(.componentAdded, entity: entity, componentType: .layer)
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
        scriptComponents.removeAll()
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
        stableOrderedEntitiesCache.removeAll()
        stableOrderedEntitiesDirty = true
        worldMatrixCache.removeAll()
        dirtyTransforms.removeAll()
        changeQueue.removeAll(keepingCapacity: true)
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

    public func forEachEntityDeterministic(_ body: (Entity) -> Void) {
        for entity in deterministicOrderedEntities() {
            body(entity)
        }
    }

    public func viewDeterministic<A>(_ a: A.Type, _ body: (Entity, A) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let componentA = get(a, for: entity) else { continue }
            body(entity, componentA)
        }
    }

    public func viewDeterministic<A, B>(_ a: A.Type, _ b: B.Type, _ body: (Entity, A, B) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let componentA = get(a, for: entity),
                  let componentB = get(b, for: entity) else { continue }
            body(entity, componentA, componentB)
        }
    }

    public func viewDeterministic<A, B, C>(_ a: A.Type, _ b: B.Type, _ c: C.Type, _ body: (Entity, A, B, C) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let componentA = get(a, for: entity),
                  let componentB = get(b, for: entity),
                  let componentC = get(c, for: entity) else { continue }
            body(entity, componentA, componentB, componentC)
        }
    }

    public func drainChanges() -> [SceneECSChange] {
        guard !changeQueue.isEmpty else { return [] }
        let drained = changeQueue
        changeQueue.removeAll(keepingCapacity: true)
        return drained
    }

    public func drainChangesDeterministic() -> [SceneECSChange] {
        guard !changeQueue.isEmpty else { return [] }
        var drained = changeQueue
        changeQueue.removeAll(keepingCapacity: true)
        drained.sort { lhs, rhs in
            if lhs.entityId != rhs.entityId {
                return lhs.entityId.uuidString < rhs.entityId.uuidString
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return (lhs.componentType?.rawValue ?? -1) < (rhs.componentType?.rawValue ?? -1)
        }
        return drained
    }

    public func consumeChanges(_ body: (SceneECSChange) -> Void) {
        guard !changeQueue.isEmpty else { return }
        for change in changeQueue {
            body(change)
        }
        changeQueue.removeAll(keepingCapacity: true)
    }

    public func add<T>(_ component: T, to entity: Entity) {
        guard aliveEntities.contains(entity) else { return }
        switch component {
        case let value as NameComponent:
            let existed = nameComponents[entity] != nil
            nameComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .name)
            }
        case let value as TransformComponent:
            let existed = transformComponents[entity] != nil
            transformComponents[entity] = value
            markTransformDirty(entity)
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .transform)
            }
        case let value as LayerComponent:
            let existed = layerComponents[entity] != nil
            layerComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .layer)
            }
        case let value as ParentComponent:
            if let parent = self.entity(with: value.parent) {
                _ = setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = setParent(entity, nil, keepWorldTransform: false)
            }
        case let value as ChildrenComponent:
            setChildrenOrder(from: value, for: entity)
        case let value as RigidbodyComponent:
            let previousEnabled = rigidbodyComponents[entity]?.isEnabled
            let existed = rigidbodyComponents[entity] != nil
            rigidbodyComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .rigidbody)
            }
            enqueueEnabledChangedIfNeeded(previous: previousEnabled, current: value.isEnabled, entity: entity, componentType: .rigidbody)
        case let value as ColliderComponent:
            let previousEnabled = colliderComponents[entity]?.isEnabled
            let existed = colliderComponents[entity] != nil
            colliderComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .collider)
            }
            enqueueEnabledChangedIfNeeded(previous: previousEnabled, current: value.isEnabled, entity: entity, componentType: .collider)
        case let value as PrefabInstanceComponent:
            let existed = prefabInstanceComponents[entity] != nil
            prefabInstanceComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .prefabInstance)
            }
        case let value as PrefabOverrideComponent:
            let existed = prefabOverrideComponents[entity] != nil
            prefabOverrideComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .prefabOverride)
            }
        case let value as MeshRendererComponent:
            let existed = meshRendererComponents[entity] != nil
            meshRendererComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .meshRenderer)
            }
        case let value as MaterialComponent:
            let existed = materialComponents[entity] != nil
            materialComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .material)
            }
        case let value as CameraComponent:
            let existed = cameraComponents[entity] != nil
            cameraComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .camera)
            }
        case let value as ScriptComponent:
            let previousEnabled = scriptComponents[entity]?.enabled
            let existed = scriptComponents[entity] != nil
            scriptComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .script)
            }
            enqueueEnabledChangedIfNeeded(previous: previousEnabled, current: value.enabled, entity: entity, componentType: .script)
        case let value as LightComponent:
            let existed = lightComponents[entity] != nil
            lightComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .light)
            }
        case let value as LightOrbitComponent:
            let existed = lightOrbitComponents[entity] != nil
            lightOrbitComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .lightOrbit)
            }
        case let value as SkyComponent:
            let existed = skyComponents[entity] != nil
            skyComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .sky)
            }
        case let value as SkyLightComponent:
            let previousEnabled = skyLightComponents[entity]?.enabled
            let existed = skyLightComponents[entity] != nil
            skyLightComponents[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .skyLight)
            }
            enqueueEnabledChangedIfNeeded(previous: previousEnabled, current: value.enabled, entity: entity, componentType: .skyLight)
        case let value as SkyLightTag:
            let existed = skyLightTags[entity] != nil
            skyLightTags[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .skyLightTag)
            }
        case let value as SkySunTag:
            let existed = skySunTags[entity] != nil
            skySunTags[entity] = value
            if !existed {
                enqueueChange(.componentAdded, entity: entity, componentType: .skySunTag)
            }
        default:
            return
        }
    }

    public func remove<T>(_ type: T.Type, from entity: Entity) {
        guard aliveEntities.contains(entity) else { return }
        switch type {
        case is NameComponent.Type:
            if nameComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .name)
            }
        case is TransformComponent.Type:
            if transformComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .transform)
            }
            markTransformDirty(entity)
        case is LayerComponent.Type:
            if layerComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .layer)
            }
        case is ParentComponent.Type:
            _ = setParent(entity, nil, keepWorldTransform: false)
        case is ChildrenComponent.Type:
            for child in getChildren(entity) {
                _ = setParent(child, nil, keepWorldTransform: false)
            }
        case is RigidbodyComponent.Type:
            if rigidbodyComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .rigidbody)
            }
        case is ColliderComponent.Type:
            if colliderComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .collider)
            }
        case is PrefabInstanceComponent.Type:
            if prefabInstanceComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .prefabInstance)
            }
        case is PrefabOverrideComponent.Type:
            if prefabOverrideComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .prefabOverride)
            }
        case is MeshRendererComponent.Type:
            if meshRendererComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .meshRenderer)
            }
        case is MaterialComponent.Type:
            if materialComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .material)
            }
        case is CameraComponent.Type:
            if cameraComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .camera)
            }
        case is ScriptComponent.Type:
            if scriptComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .script)
            }
        case is LightComponent.Type:
            if lightComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .light)
            }
        case is LightOrbitComponent.Type:
            if lightOrbitComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .lightOrbit)
            }
        case is SkyComponent.Type:
            if skyComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .sky)
            }
        case is SkyLightComponent.Type:
            if skyLightComponents.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .skyLight)
            }
        case is SkyLightTag.Type:
            if skyLightTags.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .skyLightTag)
            }
        case is SkySunTag.Type:
            if skySunTags.removeValue(forKey: entity) != nil {
                enqueueChange(.componentRemoved, entity: entity, componentType: .skySunTag)
            }
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
        case is ScriptComponent.Type:
            return scriptComponents[entity] as? T
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
        viewDeterministic(TransformComponent.self, MeshRendererComponent.self, body)
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
        for entity in deterministicOrderedEntities() {
            guard let light = lightComponents[entity] else { continue }
            let transform = transformComponents[entity]
            body(entity, transform, light)
        }
    }

    public func viewLightOrbits(_ body: (Entity, TransformComponent?, LightOrbitComponent) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let orbit = lightOrbitComponents[entity] else { continue }
            let transform = transformComponents[entity]
            body(entity, transform, orbit)
        }
    }

    public func viewCameras(_ body: (Entity, TransformComponent?, CameraComponent) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let camera = cameraComponents[entity] else { continue }
            let transform = transformComponents[entity]
            body(entity, transform, camera)
        }
    }

    public func activeCamera(allowEditor: Bool = true, preferEditor: Bool = false) -> (Entity, TransformComponent, CameraComponent)? {
        var candidates: [(Entity, CameraComponent)] = []
        candidates.reserveCapacity(cameraComponents.count)
        for entity in deterministicOrderedEntities() {
            guard let camera = cameraComponents[entity] else { continue }
            if !allowEditor && camera.isEditor { continue }
            candidates.append((entity, camera))
        }
        if preferEditor {
            if let primaryEditor = candidates.first(where: { $0.1.isEditor && $0.1.isPrimary }),
               let transform = transformComponents[primaryEditor.0] {
                return (primaryEditor.0, transform, primaryEditor.1)
            }
            if let editor = candidates.first(where: { $0.1.isEditor }),
               let transform = transformComponents[editor.0] {
                return (editor.0, transform, editor.1)
            }
        }
        if let primary = candidates.first(where: { $0.1.isPrimary }),
           let transform = transformComponents[primary.0] {
            return (primary.0, transform, primary.1)
        }
        if let entry = candidates.first, let transform = transformComponents[entry.0] {
            return (entry.0, transform, entry.1)
        }
        return nil
    }

    public func viewSky(_ body: (Entity, SkyComponent) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let sky = skyComponents[entity] else { continue }
            body(entity, sky)
        }
    }

    public func viewSkyLights(_ body: (Entity, SkyLightComponent) -> Void) {
        for entity in deterministicOrderedEntities() {
            guard let sky = skyLightComponents[entity] else { continue }
            body(entity, sky)
        }
    }

    public func firstEntity(with type: SkySunTag.Type) -> Entity? {
        return deterministicOrderedEntities().first { skySunTags[$0] != nil }
    }

    public func activeSkyLight() -> (Entity, SkyLightComponent)? {
        for entity in deterministicOrderedEntities() {
            if skyLightTags[entity] != nil, let sky = skyLightComponents[entity] {
                return (entity, sky)
            }
        }
        for entity in deterministicOrderedEntities() {
            if let sky = skyLightComponents[entity] {
                return (entity, sky)
            }
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
        removeAllComponents(for: e)
        enqueueChange(.entityDestroyed, entity: e)
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
            var unrooted: [Entity] = []
            unrooted.reserveCapacity(aliveEntities.count - ordered.count)
            for entity in aliveEntities where !ordered.contains(entity) {
                unrooted.append(entity)
            }
            unrooted.sort(by: stableEntityCompare)
            for entity in unrooted {
                ordered.append(entity)
            }
        }
        orderedEntitiesCache = ordered
        orderedEntitiesDirty = false
    }

    private func deterministicOrderedEntities() -> [Entity] {
        guard stableOrderedEntitiesDirty else { return stableOrderedEntitiesCache }
        var ordered = Array(aliveEntities)
        ordered.sort(by: stableEntityCompare)
        stableOrderedEntitiesCache = ordered
        stableOrderedEntitiesDirty = false
        return ordered
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

    private func removeAllComponents(for entity: Entity) {
        if nameComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .name)
        }
        if transformComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .transform)
        }
        if layerComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .layer)
        }
        if rigidbodyComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .rigidbody)
        }
        if colliderComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .collider)
        }
        if prefabInstanceComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .prefabInstance)
        }
        if prefabOverrideComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .prefabOverride)
        }
        if meshRendererComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .meshRenderer)
        }
        if materialComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .material)
        }
        if cameraComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .camera)
        }
        if scriptComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .script)
        }
        if lightComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .light)
        }
        if lightOrbitComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .lightOrbit)
        }
        if skyComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .sky)
        }
        if skyLightComponents.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .skyLight)
        }
        if skyLightTags.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .skyLightTag)
        }
        if skySunTags.removeValue(forKey: entity) != nil {
            enqueueChange(.componentRemoved, entity: entity, componentType: .skySunTag)
        }
    }

    private func enqueueEnabledChangedIfNeeded(previous: Bool?, current: Bool, entity: Entity, componentType: SceneECSComponentType) {
        guard let previous else { return }
        if previous == current { return }
        enqueueChange(current ? .componentEnabled : .componentDisabled, entity: entity, componentType: componentType)
    }

    private func enqueueChange(_ kind: SceneECSChangeKind, entity: Entity, componentType: SceneECSComponentType? = nil) {
        stableOrderedEntitiesDirty = true
        changeQueue.append(SceneECSChange(kind: kind, entityId: entity.id, componentType: componentType))
    }

    private func stableEntityCompare(_ lhs: Entity, _ rhs: Entity) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
