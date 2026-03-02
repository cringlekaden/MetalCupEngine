/// PhysicsSystem.swift
/// Defines PhysicsSystem to sync ECS with Jolt.
/// Created by Codex.
/// Euler rotation order is XYZ (rotate X, then Y, then Z) across the engine.

import Foundation
import simd

public final class PhysicsSystem {
    private static let positionWritebackEpsilon: Float = 1e-4
    private static let rotationWritebackEpsilon: Float = 1e-4
    private static let minimumScaleEpsilon: Float = 1e-4
    private var world: PhysicsWorld
    private var settings: PhysicsSettings
    private var lastAppliedSettingsHash: Int
    private var lastAppliedSettingsVersion: UInt64?
    private var warnedEntities: Set<UUID> = []
    private var warnedZeroScaleEntities: Set<UUID> = []
    private var warnedMirroredScaleEntities: Set<UUID> = []
    private var overlapEvents: [PhysicsOverlapEvent] = []
    private var activeOverlaps: Set<OverlapKey> = []
    private var collisionEvents: [PhysicsCollisionEvent] = []
    private var activeCollisionPairs: Set<OverlapKey> = []
    private var scriptEvents: [PhysicsScriptEvent] = []
    private var sensorBodyIdsByEntity: [UUID: [UInt64]] = [:]
    private var runtimeSignatureByEntity: [UUID: Int] = [:]
    private var runtimeWorldScaleByEntity: [UUID: SIMD3<Float>] = [:]
#if DEBUG
    private var warnedScaleEntities: Set<UUID> = []
    private var hasSteppedOnce: Bool = false
    private var debugLoggedPostStep: Bool = false
    private var debugEntityId: UUID?
#else
    private var hasSteppedOnce: Bool = false
#endif

    public init?(settings: PhysicsSettings) {
        guard let world = PhysicsWorld(settings: settings) else { return nil }
        self.world = world
        self.settings = settings
        self.lastAppliedSettingsHash = settings.runtimeHash()
        self.lastAppliedSettingsVersion = nil
    }

    public func syncSettingsIfNeeded(scene: EngineScene) {
        let latest: PhysicsSettings
        let newHash: Int
        if let context = scene.engineContext {
            let version = context.physicsSettingsVersion
            if lastAppliedSettingsVersion == version { return }
            latest = context.physicsSettings
            lastAppliedSettingsVersion = version
            newHash = latest.runtimeHash()
        } else {
            latest = settings
            newHash = latest.runtimeHash()
            if newHash == lastAppliedSettingsHash { return }
        }

        let previous = settings
        settings = latest
        lastAppliedSettingsHash = newHash

        let requiresWorldRebuild =
            previous.deterministic != latest.deterministic ||
            previous.maxBodies != latest.maxBodies ||
            previous.maxBodyPairs != latest.maxBodyPairs ||
            previous.maxContactConstraints != latest.maxContactConstraints ||
            previous.collisionMatrix != latest.collisionMatrix

        if requiresWorldRebuild {
            rebuildWorldAndBodies(scene: scene)
            return
        }

        world.applySettings(latest)
        if previous.isEnabled && !latest.isEnabled {
            overlapEvents.removeAll(keepingCapacity: true)
            activeOverlaps.removeAll(keepingCapacity: true)
            collisionEvents.removeAll(keepingCapacity: true)
            activeCollisionPairs.removeAll(keepingCapacity: true)
            scriptEvents.removeAll(keepingCapacity: true)
        }
        if previous.ccdEnabled != latest.ccdEnabled {
            rebuildAllBodiesPreservingMotion(scene: scene)
        }
    }

    public func pullTransformsFromPhysics(scene: EngineScene) {
        pullDynamicTransforms(ecs: scene.ecs)
    }

    public func buildBodies(scene: EngineScene) {
        let ecs = scene.ecs
        overlapEvents.removeAll(keepingCapacity: true)
        activeOverlaps.removeAll(keepingCapacity: true)
        activeCollisionPairs.removeAll(keepingCapacity: true)
        collisionEvents.removeAll(keepingCapacity: true)
        scriptEvents.removeAll(keepingCapacity: true)
        sensorBodyIdsByEntity.removeAll(keepingCapacity: true)
        runtimeSignatureByEntity.removeAll(keepingCapacity: true)
        runtimeWorldScaleByEntity.removeAll(keepingCapacity: true)
        ecs.forEachEntity { entity in
            guard ecs.get(TransformComponent.self, for: entity) != nil else { return }
            guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity) else {
                if ecs.has(ColliderComponent.self, entity) {
                    logWarningOnce(entityId: entity.id, message: "Collider present without Rigidbody. Add a Rigidbody to enable physics.")
                }
                return
            }
            guard let collider = ecs.get(ColliderComponent.self, for: entity) else {
                logWarningOnce(entityId: entity.id, message: "Rigidbody present without Collider. Add a Collider to enable physics.")
                return
            }
            guard rigidbody.isEnabled, collider.isEnabled else { return }
            _ = rebuildEntityBodies(entity: entity, rigidbody: &rigidbody, collider: collider, ecs: ecs)
            let worldScale = ecs.worldTransform(for: entity).scale
            runtimeSignatureByEntity[entity.id] = runtimeSignature(rigidbody: rigidbody, collider: collider)
            runtimeWorldScaleByEntity[entity.id] = worldScale
        }
    }

    public func destroyBodies(scene: EngineScene) {
        let ecs = scene.ecs
        ecs.forEachEntity { entity in
            guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity) else { return }
            if let bodyId = rigidbody.bodyId {
                world.destroyBody(bodyId: bodyId)
            }
            if let sensorBodies = sensorBodyIdsByEntity[entity.id] {
                for sensorBody in sensorBodies {
                    world.destroyBody(bodyId: sensorBody)
                }
            }
            rigidbody.bodyId = nil
            ecs.add(rigidbody, to: entity)
        }
        sensorBodyIdsByEntity.removeAll(keepingCapacity: true)
        runtimeSignatureByEntity.removeAll(keepingCapacity: true)
        runtimeWorldScaleByEntity.removeAll(keepingCapacity: true)
        overlapEvents.removeAll(keepingCapacity: true)
        activeOverlaps.removeAll(keepingCapacity: true)
        activeCollisionPairs.removeAll(keepingCapacity: true)
        collisionEvents.removeAll(keepingCapacity: true)
        scriptEvents.removeAll(keepingCapacity: true)
    }

    public func fixedUpdate(scene: EngineScene, fixedDeltaTime: Float) {
        syncSettingsIfNeeded(scene: scene)
        guard settings.isEnabled else { return }
        let ecs = scene.ecs
        syncRuntimeBindings(scene: scene)
        syncSensorBodiesToParents(ecs: ecs)
        pushKinematicTransforms(ecs: ecs)
        world.step(dt: fixedDeltaTime)
        updateOverlapEvents()
#if DEBUG
        if let debugEntityId, !debugLoggedPostStep, let entity = ecs.entity(with: debugEntityId),
           let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
           let bodyId = rigidbody.bodyId,
           let transform = ecs.get(TransformComponent.self, for: entity),
           let fetched = world.getBodyTransform(bodyId: bodyId) {
            let ecsRotation = transform.rotation
            let posDelta = simd_length(fetched.position - transform.position)
            let angDelta = PhysicsSystem.angularDeltaDegrees(ecsRotation, fetched.rotation)
            EngineLoggerContext.log(
                String(format: "Physics Debug Body '%@': post-step delta pos=%.6f, ang=%.4f°",
                       entity.id.uuidString, posDelta, angDelta),
                level: .debug,
                category: .scene
            )
            debugLoggedPostStep = true
        }
#endif
        pullDynamicTransforms(ecs: ecs)
        hasSteppedOnce = true
    }

    public func rebuildBody(entity: Entity, scene: EngineScene) -> Bool {
        let ecs = scene.ecs
        guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
              let collider = ecs.get(ColliderComponent.self, for: entity),
              ecs.get(TransformComponent.self, for: entity) != nil else {
            return false
        }
        let preservedState = preserveMotionStateIfPossible(rigidbody: rigidbody)
        let rebuilt = rebuildEntityBodies(entity: entity, rigidbody: &rigidbody, collider: collider, ecs: ecs)
        if rebuilt, let bodyId = rigidbody.bodyId {
            restoreMotionStateIfPossible(preservedState, to: bodyId)
        }
        let worldScale = ecs.worldTransform(for: entity).scale
        runtimeSignatureByEntity[entity.id] = runtimeSignature(rigidbody: rigidbody, collider: collider)
        runtimeWorldScaleByEntity[entity.id] = worldScale
        return rebuilt
    }

    public static func submitDebugDraw(scene: EngineScene, debugDraw: DebugDraw, selectionId: UUID?) {
        let ecs = scene.ecs
        let settings = scene.engineContext?.physicsSettings ?? PhysicsSettings()
        let drawColliders = settings.showColliders
        let drawCOMAxes = settings.showCOMAxes
        let drawContacts = settings.showContacts
        let drawSleeping = settings.showSleeping
        let drawOverlaps = settings.showOverlaps
        var bodyState: [UInt64: (motionType: RigidbodyMotionType, isTrigger: Bool)] = [:]
        bodyState.reserveCapacity(64)
        for entity in ecs.allEntities() {
            guard let collider = ecs.get(ColliderComponent.self, for: entity),
                  collider.isEnabled,
                  ecs.get(TransformComponent.self, for: entity) != nil else { continue }
            let worldTransform = ecs.worldTransform(for: entity)
            let rigidbody = ecs.get(RigidbodyComponent.self, for: entity)
            if let bodyId = rigidbody?.bodyId {
                bodyState[bodyId] = (motionType: rigidbody?.motionType ?? .staticBody, isTrigger: false)
            }
            let worldMatrix = PhysicsMath.transformMatrix(position: worldTransform.position, rotation: worldTransform.rotation)
            for shape in collider.allShapes() where shape.isEnabled {
                let baseColor = debugColor(rigidbody: rigidbody, isTrigger: shape.isTrigger, isSelected: selectionId == entity.id)
                var color = baseColor
                if drawSleeping,
                   let rigidbody,
                   rigidbody.isEnabled,
                   rigidbody.motionType == .dynamic,
                   let bodyId = rigidbody.bodyId,
                   let physicsSystem = scene.physicsSystem,
                   physicsSystem.isBodySleeping(bodyId: bodyId) {
                    color = SIMD4<Float>(0.55, 0.55, 0.55, 0.9)
                }
                let scaled = PhysicsMath.scaledShape(from: shape, scale: worldTransform.scale)
                let offsetRotation = TransformMath.quaternionFromEulerXYZ(shape.rotationOffset)
                let offsetMatrix = PhysicsMath.transformMatrix(position: scaled.offset, rotation: offsetRotation)
                let colliderMatrix = matrix_multiply(worldMatrix, offsetMatrix)
                if drawColliders {
                    switch shape.shapeType {
                    case .box:
                        debugDraw.submitWireBox(transform: colliderMatrix, halfExtents: scaled.boxHalfExtents, color: color)
                    case .sphere:
                        debugDraw.submitWireSphere(transform: colliderMatrix, radius: scaled.sphereRadius, color: color)
                    case .capsule:
                        debugDraw.submitWireCapsule(transform: colliderMatrix, radius: scaled.capsuleRadius, halfHeight: scaled.capsuleHalfHeight, color: color)
                    }
                }
            }

            if drawCOMAxes,
               let rigidbody,
               rigidbody.isEnabled,
               let bodyId = rigidbody.bodyId,
               let physicsSystem = scene.physicsSystem,
               let bodyTransform = physicsSystem.bodyTransform(bodyId: bodyId) {
                let axisLength = max(0.05, debugDraw.lineThickness * 4.0)
                let basis = PhysicsMath.transformMatrix(position: bodyTransform.position,
                                                       rotation: TransformMath.normalizedQuaternion(bodyTransform.rotation))
                let origin = bodyTransform.position
                let xAxis = SIMD3<Float>(basis.columns.0.x, basis.columns.0.y, basis.columns.0.z) * axisLength
                let yAxis = SIMD3<Float>(basis.columns.1.x, basis.columns.1.y, basis.columns.1.z) * axisLength
                let zAxis = SIMD3<Float>(basis.columns.2.x, basis.columns.2.y, basis.columns.2.z) * axisLength
                debugDraw.submitLine(origin, origin + xAxis, color: SIMD4<Float>(1.0, 0.2, 0.2, 1.0))
                debugDraw.submitLine(origin, origin + yAxis, color: SIMD4<Float>(0.2, 1.0, 0.2, 1.0))
                debugDraw.submitLine(origin, origin + zAxis, color: SIMD4<Float>(0.2, 0.4, 1.0, 1.0))
            }
        }

        if drawContacts,
           let physicsSystem = scene.physicsSystem {
            let contacts = physicsSystem.lastContacts()
            if !contacts.isEmpty {
                let pointSize = max(0.02, debugDraw.lineThickness * 2.0)
                let normalLength: Float = 0.25
                for contact in contacts {
                    let state = bodyState[contact.bodyId]
                    let isTrigger = state?.isTrigger == true
                    let isDynamic = state?.motionType == .dynamic
                    let color: SIMD4<Float> = isTrigger
                        ? SIMD4<Float>(0.2, 0.45, 1.0, 1.0)
                        : (isDynamic ? SIMD4<Float>(1.0, 0.2, 0.2, 1.0) : SIMD4<Float>(1.0, 0.6, 0.2, 1.0))
                    let offsetX = SIMD3<Float>(pointSize, 0.0, 0.0)
                    let offsetZ = SIMD3<Float>(0.0, 0.0, pointSize)
                    debugDraw.submitLine(contact.position - offsetX, contact.position + offsetX, color: color)
                    debugDraw.submitLine(contact.position - offsetZ, contact.position + offsetZ, color: color)
                    debugDraw.submitLine(contact.position, contact.position + contact.normal * normalLength, color: color)
                }
            }
        }

        if drawOverlaps,
           let physicsSystem = scene.physicsSystem {
            let overlaps = physicsSystem.activeOverlapPairs()
            if !overlaps.isEmpty {
                for pair in overlaps {
                    guard let entityA = ecs.entity(with: pair.a),
                          let entityB = ecs.entity(with: pair.b),
                          ecs.get(TransformComponent.self, for: entityA) != nil,
                          ecs.get(TransformComponent.self, for: entityB) != nil else { continue }
                    let worldA = ecs.worldTransform(for: entityA)
                    let worldB = ecs.worldTransform(for: entityB)
                    debugDraw.submitLine(worldA.position, worldB.position,
                                         color: SIMD4<Float>(0.85, 0.4, 1.0, 0.9))
                }
            }
        }
    }

    private func pushKinematicTransforms(ecs: SceneECS) {
        ecs.forEachEntity { entity in
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  rigidbody.motionType == .kinematic,
                  let bodyId = rigidbody.bodyId,
                  ecs.get(TransformComponent.self, for: entity) != nil else {
                return
            }
            let worldTransform = ecs.worldTransform(for: entity)
            let rotation = worldTransform.rotation
            world.setBodyTransform(bodyId: bodyId, position: worldTransform.position, rotation: rotation)
        }
    }

    func bodyTransform(bodyId: UInt64) -> (position: SIMD3<Float>, rotation: SIMD4<Float>)? {
        world.getBodyTransform(bodyId: bodyId)
    }

    func lastContacts() -> [PhysicsContact] {
        world.lastContacts()
    }

    public func recentOverlapEvents() -> [PhysicsOverlapEvent] {
        overlapEvents
    }

    public func recentCollisionEvents() -> [PhysicsCollisionEvent] {
        collisionEvents
    }

    public func drainEvents() -> [PhysicsScriptEvent] {
        guard !scriptEvents.isEmpty else { return [] }
        let drained = scriptEvents
        scriptEvents.removeAll(keepingCapacity: true)
        return drained
    }

    public func activeOverlapPairs() -> [OverlapPair] {
        activeOverlaps.map { OverlapPair(a: $0.a, b: $0.b) }
    }

    public func isBodySleeping(bodyId: UInt64) -> Bool {
        world.isBodySleeping(bodyId: bodyId)
    }

    @discardableResult
    public func setBodyTransform(entity: Entity,
                                 scene: EngineScene,
                                 position: SIMD3<Float>,
                                 rotation: SIMD4<Float>,
                                 activate: Bool = true) -> Bool {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              let bodyId = rigidbody.bodyId else { return false }
        world.setBodyTransform(bodyId: bodyId,
                               position: position,
                               rotation: rotation,
                               activate: activate)
        return true
    }

    @discardableResult
    public func setBodyLinearVelocity(entity: Entity, scene: EngineScene, velocity: SIMD3<Float>) -> Bool {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              let bodyId = rigidbody.bodyId else { return false }
        let angular = world.getBodyVelocity(bodyId: bodyId)?.angular ?? SIMD3<Float>(repeating: 0.0)
        world.setBodyVelocity(bodyId: bodyId, linear: velocity, angular: angular)
        return true
    }

    public func bodyVelocity(entity: Entity, scene: EngineScene) -> SIMD3<Float>? {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              let bodyId = rigidbody.bodyId else { return nil }
        return world.getBodyVelocity(bodyId: bodyId)?.linear
    }

    public func isGrounded(entity: Entity, scene: EngineScene, probeDistance: Float = 0.2) -> Bool {
        guard scene.ecs.get(TransformComponent.self, for: entity) != nil else { return false }
        let worldTransform = scene.ecs.worldTransform(for: entity)
        let origin = worldTransform.position + SIMD3<Float>(0.0, max(0.05, probeDistance), 0.0)
        let hit = world.sphereCastClosest(origin: origin,
                                          direction: SIMD3<Float>(0.0, -1.0, 0.0),
                                          radius: 0.2,
                                          maxDistance: max(0.05, probeDistance * 2.0))
        guard let hit else { return false }
        guard let entityId = hit.entityId else { return true }
        return entityId != entity.id
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        maxDistance: Float,
                        layerMask: LayerMask,
                        includeTriggers: Bool) -> PhysicsRaycastHit? {
        world.raycast(origin: origin,
                      direction: direction,
                      maxDistance: maxDistance,
                      layerMask: layerMask,
                      includeTriggers: includeTriggers)
    }

    public func raycastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> PhysicsRaycastHit? {
        raycast(origin: origin,
                direction: direction,
                maxDistance: maxDistance,
                layerMask: .all,
                includeTriggers: true)
    }

    public func raycastForEditorPicking(origin: SIMD3<Float>,
                                        direction: SIMD3<Float>,
                                        maxDistance: Float,
                                        layerMask: LayerMask = .all) -> PhysicsRaycastHit? {
        raycast(origin: origin,
                direction: direction,
                maxDistance: maxDistance,
                layerMask: layerMask,
                includeTriggers: false)
    }

    public func sphereCastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, radius: Float, maxDistance: Float) -> PhysicsRaycastHit? {
        world.sphereCastClosest(origin: origin, direction: direction, radius: radius, maxDistance: maxDistance)
    }

    private func pullDynamicTransforms(ecs: SceneECS) {
        ecs.forEachEntity { entity in
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  rigidbody.motionType == .dynamic,
                  let bodyId = rigidbody.bodyId,
                  var localTransform = ecs.get(TransformComponent.self, for: entity) else {
                return
            }
            guard let result = world.getBodyTransform(bodyId: bodyId) else { return }
            let worldTransform = ecs.worldTransform(for: entity)
            let positionDelta = simd_length(result.position - worldTransform.position)
            let currentQuat = worldTransform.rotation
            let rotationDelta = PhysicsSystem.quaternionAngleDelta(currentQuat, result.rotation)
            if positionDelta <= Self.positionWritebackEpsilon,
               rotationDelta <= Self.rotationWritebackEpsilon {
                return
            }
            let resultRotation = TransformMath.normalizedQuaternion(result.rotation)
            if let parent = ecs.getParent(entity) {
                let parentWorldMatrix = ecs.worldMatrix(for: parent)
                let desiredWorldMatrix = TransformMath.makeMatrix(
                    position: result.position,
                    rotation: resultRotation,
                    scale: worldTransform.scale
                )
                let desiredLocalMatrix = simd_inverse(parentWorldMatrix) * desiredWorldMatrix
                let decomposedLocal = TransformMath.decomposeMatrix(desiredLocalMatrix)
                localTransform.position = decomposedLocal.position
                localTransform.rotation = decomposedLocal.rotation
            } else {
                localTransform.position = result.position
                localTransform.rotation = resultRotation
            }
            ecs.add(localTransform, to: entity)
        }
    }

    private static func buildBodyCreation(rigidbody: RigidbodyComponent,
                                          transform: TransformComponent,
                                          settings: PhysicsSettings,
                                          userData: UInt64,
                                          isTrigger: Bool,
                                          collisionLayer: Int32,
                                          shapes: [PhysicsShapeCreation]) -> PhysicsBodyCreation {
        let friction = rigidbody.friction.isFinite ? rigidbody.friction : settings.defaultFriction
        let restitution = rigidbody.restitution.isFinite ? rigidbody.restitution : settings.defaultRestitution
        let linearDamping = rigidbody.linearDamping.isFinite ? rigidbody.linearDamping : settings.defaultLinearDamping
        let angularDamping = rigidbody.angularDamping.isFinite ? rigidbody.angularDamping : settings.defaultAngularDamping
        let resolvedLayer = max(0, min(collisionLayer, Int32(PhysicsSettings.maxCollisionLayers - 1)))
        return PhysicsBodyCreation(
            motionType: rigidbody.motionType,
            position: transform.position,
            rotation: transform.rotation,
            shapes: shapes,
            friction: friction,
            restitution: restitution,
            linearDamping: linearDamping,
            angularDamping: angularDamping,
            gravityFactor: rigidbody.gravityFactor,
            mass: rigidbody.mass,
            userData: userData,
            ccdEnabled: settings.ccdEnabled || rigidbody.ccdEnabled,
            isTrigger: isTrigger,
            allowSleeping: rigidbody.allowSleeping,
            collisionLayer: resolvedLayer
        )
    }

    private func rebuildEntityBodies(entity: Entity,
                                     rigidbody: inout RigidbodyComponent,
                                     collider: ColliderComponent,
                                     ecs: SceneECS) -> Bool {
        if let bodyId = rigidbody.bodyId {
            world.destroyBody(bodyId: bodyId)
            rigidbody.bodyId = nil
        }
        if let sensorBodies = sensorBodyIdsByEntity[entity.id] {
            for sensorBody in sensorBodies {
                world.destroyBody(bodyId: sensorBody)
            }
            sensorBodyIdsByEntity.removeValue(forKey: entity.id)
        }

        guard rigidbody.isEnabled, collider.isEnabled else {
            ecs.add(rigidbody, to: entity)
            return false
        }

        let worldTransform = ecs.worldTransform(for: entity)
        guard validateWorldScale(entityId: entity.id, scale: worldTransform.scale) else {
            ecs.add(rigidbody, to: entity)
            return false
        }

        let allShapes = collider.allShapes().filter { $0.isEnabled }
        guard !allShapes.isEmpty else {
            ecs.add(rigidbody, to: entity)
            return false
        }
        for shape in allShapes where !validateShape(entityId: entity.id, shape: shape) {
            ecs.add(rigidbody, to: entity)
            return false
        }

        let userData = world.userData(for: entity.id)
        let solidShapes = allShapes.filter { !$0.isTrigger }
        let triggerShapes = allShapes.filter { $0.isTrigger }

        var createdMainBody = false
        if !solidShapes.isEmpty {
            let physicsShapes = solidShapes.map { shape in
                buildShapeCreation(shape: shape, worldScale: worldTransform.scale)
            }
            let layer = rigidbody.collisionLayer
            let creation = Self.buildBodyCreation(rigidbody: rigidbody,
                                                  transform: worldTransform,
                                                  settings: settings,
                                                  userData: userData,
                                                  isTrigger: false,
                                                  collisionLayer: layer,
                                                  shapes: physicsShapes)
            let bodyId = world.createBody(desc: creation)
            if bodyId != 0 {
                rigidbody.bodyId = bodyId
                createdMainBody = true
            }
        }

        if !triggerShapes.isEmpty {
            let physicsShapes = triggerShapes.map { shape in
                buildShapeCreation(shape: shape, worldScale: worldTransform.scale)
            }
            let layer = triggerShapes.compactMap { $0.collisionLayerOverride }.first ?? rigidbody.collisionLayer
            let triggerMotionType: RigidbodyMotionType = .kinematic
            var triggerRigidbody = rigidbody
            triggerRigidbody.motionType = triggerMotionType
            triggerRigidbody.gravityFactor = 0.0
            triggerRigidbody.allowSleeping = false
            let creation = Self.buildBodyCreation(rigidbody: triggerRigidbody,
                                                  transform: worldTransform,
                                                  settings: settings,
                                                  userData: userData,
                                                  isTrigger: true,
                                                  collisionLayer: layer,
                                                  shapes: physicsShapes)
            let sensorBodyId = world.createBody(desc: creation)
            if sensorBodyId != 0 {
                sensorBodyIdsByEntity[entity.id] = [sensorBodyId]
                if !createdMainBody {
                    rigidbody.bodyId = sensorBodyId
                    createdMainBody = true
                }
            }
        }

        ecs.add(rigidbody, to: entity)
        return createdMainBody
    }

    private func buildShapeCreation(shape: ColliderShape, worldScale: SIMD3<Float>) -> PhysicsShapeCreation {
        let scaled = PhysicsMath.scaledShape(from: shape, scale: worldScale)
        return PhysicsShapeCreation(shapeType: shape.shapeType,
                                    boxHalfExtents: scaled.boxHalfExtents,
                                    sphereRadius: scaled.sphereRadius,
                                    capsuleHalfHeight: scaled.capsuleHalfHeight,
                                    capsuleRadius: scaled.capsuleRadius,
                                    offset: scaled.offset,
                                    rotationOffset: PhysicsMath.quaternionFromEuler(shape.rotationOffset),
                                    collisionLayerOverride: shape.collisionLayerOverride,
                                    physicsMaterial: shape.physicsMaterial)
    }

    private func runtimeSignature(rigidbody: RigidbodyComponent,
                                  collider: ColliderComponent) -> Int {
        var hasher = Hasher()
        hasher.combine(rigidbody.isEnabled)
        hasher.combine(rigidbody.motionType.rawValue)
        hasher.combine(rigidbody.mass.bitPattern)
        hasher.combine(rigidbody.friction.bitPattern)
        hasher.combine(rigidbody.restitution.bitPattern)
        hasher.combine(rigidbody.linearDamping.bitPattern)
        hasher.combine(rigidbody.angularDamping.bitPattern)
        hasher.combine(rigidbody.gravityFactor.bitPattern)
        hasher.combine(rigidbody.allowSleeping)
        hasher.combine(rigidbody.ccdEnabled)
        hasher.combine(rigidbody.collisionLayer)
        for shape in collider.allShapes() {
            hasher.combine(shape.isEnabled)
            hasher.combine(shape.shapeType.rawValue)
            hasher.combine(shape.boxHalfExtents.x.bitPattern)
            hasher.combine(shape.boxHalfExtents.y.bitPattern)
            hasher.combine(shape.boxHalfExtents.z.bitPattern)
            hasher.combine(shape.sphereRadius.bitPattern)
            hasher.combine(shape.capsuleHalfHeight.bitPattern)
            hasher.combine(shape.capsuleRadius.bitPattern)
            hasher.combine(shape.offset.x.bitPattern)
            hasher.combine(shape.offset.y.bitPattern)
            hasher.combine(shape.offset.z.bitPattern)
            hasher.combine(shape.rotationOffset.x.bitPattern)
            hasher.combine(shape.rotationOffset.y.bitPattern)
            hasher.combine(shape.rotationOffset.z.bitPattern)
            hasher.combine(shape.isTrigger)
            hasher.combine(shape.collisionLayerOverride ?? -1)
            if let handle = shape.physicsMaterial {
                hasher.combine(handle.rawValue.uuidString)
            } else {
                hasher.combine("nil")
            }
        }
        return hasher.finalize()
    }

    private func syncRuntimeBindings(scene: EngineScene) {
        let ecs = scene.ecs
        var liveEntities: Set<UUID> = []
        liveEntities.reserveCapacity(runtimeSignatureByEntity.count + 16)
        ecs.forEachEntity { entity in
            liveEntities.insert(entity.id)
            guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  let collider = ecs.get(ColliderComponent.self, for: entity),
                  ecs.get(TransformComponent.self, for: entity) != nil else {
                if var staleRigidbody = ecs.get(RigidbodyComponent.self, for: entity), staleRigidbody.bodyId != nil {
                    _ = rebuildEntityBodies(entity: entity, rigidbody: &staleRigidbody, collider: ColliderComponent(isEnabled: false), ecs: ecs)
                }
                runtimeSignatureByEntity.removeValue(forKey: entity.id)
                runtimeWorldScaleByEntity.removeValue(forKey: entity.id)
                return
            }

            let worldScale = ecs.worldTransform(for: entity).scale
            let signature = runtimeSignature(rigidbody: rigidbody, collider: collider)
            let lastScale = runtimeWorldScaleByEntity[entity.id] ?? worldScale
            let scaleChanged = simd_length(worldScale - lastScale) > 1e-4
            if runtimeSignatureByEntity[entity.id] != signature || scaleChanged {
                _ = rebuildEntityBodies(entity: entity, rigidbody: &rigidbody, collider: collider, ecs: ecs)
                let rebuiltWorldScale = ecs.worldTransform(for: entity).scale
                runtimeSignatureByEntity[entity.id] = runtimeSignature(rigidbody: rigidbody, collider: collider)
                runtimeWorldScaleByEntity[entity.id] = rebuiltWorldScale
            }
        }

        for entityId in runtimeSignatureByEntity.keys where !liveEntities.contains(entityId) {
            runtimeSignatureByEntity.removeValue(forKey: entityId)
            sensorBodyIdsByEntity.removeValue(forKey: entityId)
            runtimeWorldScaleByEntity.removeValue(forKey: entityId)
        }
    }

    private func syncSensorBodiesToParents(ecs: SceneECS) {
        guard !sensorBodyIdsByEntity.isEmpty else { return }
        ecs.forEachEntity { entity in
            guard let sensorBodyIds = sensorBodyIdsByEntity[entity.id], !sensorBodyIds.isEmpty else { return }
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  let bodyId = rigidbody.bodyId,
                  let bodyTransform = world.getBodyTransform(bodyId: bodyId) else { return }
            for sensorBodyId in sensorBodyIds {
                if sensorBodyId == bodyId { continue }
                world.setBodyTransform(bodyId: sensorBodyId,
                                       position: bodyTransform.position,
                                       rotation: bodyTransform.rotation,
                                       activate: false)
            }
        }
    }

    private func validateShape(entityId: UUID, shape: ColliderShape) -> Bool {
        switch shape.shapeType {
        case .box:
            if shape.boxHalfExtents.x <= 0 || shape.boxHalfExtents.y <= 0 || shape.boxHalfExtents.z <= 0 {
                logWarningOnce(entityId: entityId, message: "Box collider has invalid half extents. Update values > 0.")
                return false
            }
        case .sphere:
            if shape.sphereRadius <= 0 {
                logWarningOnce(entityId: entityId, message: "Sphere collider has invalid radius. Update value > 0.")
                return false
            }
        case .capsule:
            if shape.capsuleRadius <= 0 || shape.capsuleHalfHeight <= 0 {
                logWarningOnce(entityId: entityId, message: "Capsule collider has invalid radius/half height. Update values > 0.")
                return false
            }
        }
        return true
    }

    private func validateWorldScale(entityId: UUID, scale: SIMD3<Float>) -> Bool {
        let absScale = SIMD3<Float>(abs(scale.x), abs(scale.y), abs(scale.z))
        if absScale.x < Self.minimumScaleEpsilon || absScale.y < Self.minimumScaleEpsilon || absScale.z < Self.minimumScaleEpsilon {
            if !warnedZeroScaleEntities.contains(entityId) {
                warnedZeroScaleEntities.insert(entityId)
                EngineLoggerContext.log("Physics collider disabled due to near-zero world scale.", level: .warning, category: .scene)
            }
            return false
        }
        if (scale.x < 0 || scale.y < 0 || scale.z < 0) && !warnedMirroredScaleEntities.contains(entityId) {
            warnedMirroredScaleEntities.insert(entityId)
            EngineLoggerContext.log("Mirrored scale detected. Physics uses signed offset with absolute shape extents.", level: .warning, category: .scene)
        }
        return true
    }

    private func logWarningOnce(entityId: UUID, message: String) {
        if warnedEntities.contains(entityId) { return }
        warnedEntities.insert(entityId)
        EngineLoggerContext.log(message, level: .warning, category: .scene)
    }

#if DEBUG
    private func logScaleWarningIfNeeded(entityId: UUID, collider: ColliderShape, scale: SIMD3<Float>) {
        if warnedScaleEntities.contains(entityId) { return }
        let absScale = SIMD3<Float>(abs(scale.x), abs(scale.y), abs(scale.z))
        let isNonUniform = abs(absScale.x - absScale.y) > 0.0001
            || abs(absScale.y - absScale.z) > 0.0001
            || abs(absScale.x - absScale.z) > 0.0001
        guard isNonUniform else { return }

        let message: String
        switch collider.shapeType {
        case .sphere:
            message = "Sphere collider uses max axis scale when non-uniform scale is applied."
        case .capsule:
            message = "Capsule collider uses Y for height and max(X,Z) for radius when non-uniform scale is applied."
        case .box:
            return
        }
        warnedScaleEntities.insert(entityId)
        EngineLoggerContext.log(message, level: .warning, category: .scene)
    }
#endif

#if DEBUG
    private static func angularDeltaDegrees(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let dot = abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
        let clamped = min(1.0, max(-1.0, Double(dot)))
        let angle = 2.0 * acos(clamped)
        return Float(angle * 180.0 / Double.pi)
    }
#endif

    private static func quaternionAngleDelta(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let dot = abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
        let clamped = min(1.0, max(-1.0, dot))
        let angle = 2.0 * acos(Double(clamped))
        return Float(angle)
    }

    private func updateOverlapEvents() {
        overlapEvents = world.overlapEvents()
        let previousTriggerPairs = activeOverlaps
        let previousCollisionPairs = activeCollisionPairs
        var currentTriggerPairs = previousTriggerPairs
        var currentCollisionPairs = previousCollisionPairs

        collisionEvents.removeAll(keepingCapacity: true)
        scriptEvents.removeAll(keepingCapacity: true)
        if overlapEvents.isEmpty {
            activeOverlaps.removeAll(keepingCapacity: true)
            activeCollisionPairs.removeAll(keepingCapacity: true)
            return
        }

        for event in overlapEvents {
            guard let entityA = event.entityIdA, let entityB = event.entityIdB else { continue }
            let key = OverlapKey(a: entityA, b: entityB)
            let isTriggerPair = world.isTriggerBody(event.bodyIdA) || world.isTriggerBody(event.bodyIdB)
            if isTriggerPair {
                if event.isBegin {
                    currentTriggerPairs.insert(key)
                } else {
                    currentTriggerPairs.remove(key)
                }
            } else {
                if event.isBegin {
                    currentCollisionPairs.insert(key)
                } else {
                    currentCollisionPairs.remove(key)
                }
            }
        }

        activeOverlaps = currentTriggerPairs
        activeCollisionPairs = currentCollisionPairs

        let triggerEnter = currentTriggerPairs.subtracting(previousTriggerPairs).sorted(by: OverlapKey.lessThan)
        let triggerStay = currentTriggerPairs.intersection(previousTriggerPairs).sorted(by: OverlapKey.lessThan)
        let triggerExit = previousTriggerPairs.subtracting(currentTriggerPairs).sorted(by: OverlapKey.lessThan)
        let collisionEnter = currentCollisionPairs.subtracting(previousCollisionPairs).sorted(by: OverlapKey.lessThan)
        let collisionStay = currentCollisionPairs.intersection(previousCollisionPairs).sorted(by: OverlapKey.lessThan)
        let collisionExit = previousCollisionPairs.subtracting(currentCollisionPairs).sorted(by: OverlapKey.lessThan)

        scriptEvents.reserveCapacity(triggerEnter.count +
                                     triggerStay.count +
                                     triggerExit.count +
                                     collisionEnter.count +
                                     collisionStay.count +
                                     collisionExit.count)
        appendScriptEvents(keys: triggerEnter, type: .triggerEnter)
        appendScriptEvents(keys: triggerStay, type: .triggerStay)
        appendScriptEvents(keys: triggerExit, type: .triggerExit)
        appendScriptEvents(keys: collisionEnter, type: .collisionEnter)
        appendScriptEvents(keys: collisionStay, type: .collisionStay)
        appendScriptEvents(keys: collisionExit, type: .collisionExit)

        collisionEvents.reserveCapacity(collisionEnter.count + collisionExit.count)
        for key in collisionEnter {
            collisionEvents.append(
                PhysicsCollisionEvent(entityIdA: key.a,
                                      entityIdB: key.b,
                                      isBegin: true,
                                      normal: nil,
                                      position: nil)
            )
        }
        for key in collisionExit {
            collisionEvents.append(
                PhysicsCollisionEvent(entityIdA: key.a,
                                      entityIdB: key.b,
                                      isBegin: false,
                                      normal: nil,
                                      position: nil)
            )
        }
    }

    private func appendScriptEvents(keys: [OverlapKey], type: PhysicsScriptEventType) {
        for key in keys {
            scriptEvents.append(
                PhysicsScriptEvent(type: type,
                                   entityA: key.a,
                                   entityB: key.b,
                                   shapeA: nil,
                                   shapeB: nil)
            )
        }
    }

    private func rebuildWorldAndBodies(scene: EngineScene) {
        let preservedStateByEntity = captureMotionState(scene: scene)
        guard world.recreate(settings: settings) else { return }
        rebuildBodies(scene: scene, preservedStateByEntity: preservedStateByEntity)
    }

    private func rebuildAllBodiesPreservingMotion(scene: EngineScene) {
        let preservedStateByEntity = captureMotionState(scene: scene)
        rebuildBodies(scene: scene, preservedStateByEntity: preservedStateByEntity)
    }

    private func captureMotionState(scene: EngineScene) -> [UUID: BodyMotionState] {
        let ecs = scene.ecs
        var preservedStateByEntity: [UUID: BodyMotionState] = [:]
        for entity in ecs.allEntities() {
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.motionType == .dynamic,
                  rigidbody.isEnabled else { continue }
            if let preserved = preserveMotionStateIfPossible(rigidbody: rigidbody) {
                preservedStateByEntity[entity.id] = preserved
            }
        }
        return preservedStateByEntity
    }

    private func rebuildBodies(scene: EngineScene, preservedStateByEntity: [UUID: BodyMotionState]) {
        let ecs = scene.ecs
        destroyBodies(scene: scene)
        buildBodies(scene: scene)
        for entity in ecs.allEntities() {
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  let bodyId = rigidbody.bodyId,
                  let preserved = preservedStateByEntity[entity.id] else { continue }
            restoreMotionStateIfPossible(preserved, to: bodyId)
        }
        pullDynamicTransforms(ecs: ecs)
        hasSteppedOnce = true
    }

    private func preserveMotionStateIfPossible(rigidbody: RigidbodyComponent) -> BodyMotionState? {
        guard rigidbody.motionType == .dynamic,
              let bodyId = rigidbody.bodyId,
              let velocity = world.getBodyVelocity(bodyId: bodyId) else { return nil }
        let isSleeping = world.isBodySleeping(bodyId: bodyId)
        return BodyMotionState(linearVelocity: velocity.linear,
                               angularVelocity: velocity.angular,
                               isSleeping: isSleeping)
    }

    private func restoreMotionStateIfPossible(_ state: BodyMotionState?, to bodyId: UInt64) {
        guard let state else { return }
        world.setBodyVelocity(bodyId: bodyId,
                              linear: state.linearVelocity,
                              angular: state.angularVelocity)
        world.setBodyActive(bodyId: bodyId, isActive: !state.isSleeping)
    }

    private static func debugColor(rigidbody: RigidbodyComponent?, isTrigger: Bool, isSelected: Bool) -> SIMD4<Float> {
        if isSelected { return SIMD4<Float>(1.0, 0.9, 0.2, 1.0) }
        if isTrigger { return SIMD4<Float>(1.0, 0.65, 0.2, 0.95) }
        guard let rigidbody else { return SIMD4<Float>(0.65, 0.65, 0.65, 0.9) }
        switch rigidbody.motionType {
        case .staticBody:
            return SIMD4<Float>(0.65, 0.65, 0.65, 0.9)
        case .dynamic:
            return SIMD4<Float>(0.25, 0.95, 0.45, 0.95)
        case .kinematic:
            return SIMD4<Float>(0.35, 0.75, 1.0, 0.95)
        }
    }
}

public struct OverlapPair {
    let a: UUID
    let b: UUID
}

public struct PhysicsCollisionEvent {
    public let entityIdA: UUID
    public let entityIdB: UUID
    public let isBegin: Bool
    public let normal: SIMD3<Float>?
    public let position: SIMD3<Float>?
}

public enum PhysicsScriptEventType: Int32 {
    case collisionEnter = 0
    case collisionStay = 1
    case collisionExit = 2
    case triggerEnter = 3
    case triggerStay = 4
    case triggerExit = 5
}

public struct PhysicsScriptEvent {
    public let type: PhysicsScriptEventType
    public let entityA: UUID
    public let entityB: UUID
    public let shapeA: Int32?
    public let shapeB: Int32?
}

private struct OverlapKey: Hashable {
    let a: UUID
    let b: UUID

    init(a: UUID, b: UUID) {
        if a.uuidString <= b.uuidString {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
    }

    static func lessThan(_ lhs: OverlapKey, _ rhs: OverlapKey) -> Bool {
        if lhs.a != rhs.a {
            return lhs.a.uuidString < rhs.a.uuidString
        }
        return lhs.b.uuidString < rhs.b.uuidString
    }
}

private struct BodyMotionState {
    let linearVelocity: SIMD3<Float>
    let angularVelocity: SIMD3<Float>
    let isSleeping: Bool
}

private enum PhysicsMath {
    static func quaternionFromEuler(_ euler: SIMD3<Float>) -> SIMD4<Float> {
        let result = TransformMath.quaternionFromEulerXYZ(euler)
#if DEBUG
        let roundTrip = eulerFromQuaternionXYZ(result)
        let delta = max(max(angleDelta(euler.x, roundTrip.x), angleDelta(euler.y, roundTrip.y)),
                        angleDelta(euler.z, roundTrip.z))
        MC_ASSERT(delta < 1e-5, "Euler round-trip mismatch for XYZ composition.")
#endif
        return result
    }

    static func eulerFromQuaternionXYZ(_ quat: SIMD4<Float>) -> SIMD3<Float> {
        TransformMath.eulerFromQuaternionXYZ(quat)
    }

#if DEBUG
    private static func angleDelta(_ a: Float, _ b: Float) -> Float {
        let twoPi = Float.pi * 2.0
        var delta = fmodf(b - a, twoPi)
        if delta > Float.pi { delta -= twoPi }
        if delta < -Float.pi { delta += twoPi }
        return abs(delta)
    }
#endif

    static func scaledShape(from collider: ColliderShape, scale: SIMD3<Float>) -> (boxHalfExtents: SIMD3<Float>, sphereRadius: Float, capsuleHalfHeight: Float, capsuleRadius: Float, offset: SIMD3<Float>) {
        let absScale = SIMD3<Float>(abs(scale.x), abs(scale.y), abs(scale.z))
        let offset = collider.offset * scale

        switch collider.shapeType {
        case .box:
            return (collider.boxHalfExtents * absScale, collider.sphereRadius, collider.capsuleHalfHeight, collider.capsuleRadius, offset)
        case .sphere:
            let radiusScale = max(absScale.x, max(absScale.y, absScale.z))
            return (collider.boxHalfExtents, collider.sphereRadius * radiusScale, collider.capsuleHalfHeight, collider.capsuleRadius, offset)
        case .capsule:
            let radiusScale = max(absScale.x, absScale.z)
            return (collider.boxHalfExtents, collider.sphereRadius, collider.capsuleHalfHeight * absScale.y, collider.capsuleRadius * radiusScale, offset)
        }
    }

    static func scaledShape(from collider: ColliderComponent, scale: SIMD3<Float>) -> (boxHalfExtents: SIMD3<Float>, sphereRadius: Float, capsuleHalfHeight: Float, capsuleRadius: Float, offset: SIMD3<Float>) {
        scaledShape(from: collider.primaryShape(), scale: scale)
    }

    static func transformMatrix(position: SIMD3<Float>, rotation: SIMD4<Float>) -> matrix_float4x4 {
        TransformMath.makeMatrix(position: position,
                                 rotation: rotation,
                                 scale: SIMD3<Float>(repeating: 1.0))
    }
}
