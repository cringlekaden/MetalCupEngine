/// PhysicsSystem.swift
/// Defines PhysicsSystem to sync ECS with Jolt.
/// Euler rotation order is XYZ (rotate X, then Y, then Z) across the engine. 
/// Created by Kaden Cringle.

import Foundation
import simd

public final class PhysicsSystem {
    public struct ScriptEventQueueTelemetry {
        public var droppedCollisionEvents: Int
        public var droppedTriggerEvents: Int
        public var droppedStayEvents: Int
        public var totalDroppedCollisionEvents: Int
        public var totalDroppedTriggerEvents: Int
        public var totalDroppedStayEvents: Int

        public init(droppedCollisionEvents: Int = 0,
                    droppedTriggerEvents: Int = 0,
                    droppedStayEvents: Int = 0,
                    totalDroppedCollisionEvents: Int = 0,
                    totalDroppedTriggerEvents: Int = 0,
                    totalDroppedStayEvents: Int = 0) {
            self.droppedCollisionEvents = droppedCollisionEvents
            self.droppedTriggerEvents = droppedTriggerEvents
            self.droppedStayEvents = droppedStayEvents
            self.totalDroppedCollisionEvents = totalDroppedCollisionEvents
            self.totalDroppedTriggerEvents = totalDroppedTriggerEvents
            self.totalDroppedStayEvents = totalDroppedStayEvents
        }
    }

    public struct ScriptEventQueueLimits {
        public var maxTriggerEventsPerFrame: Int
        public var maxCollisionEventsPerFrame: Int

        public init(maxTriggerEventsPerFrame: Int = 2048,
                    maxCollisionEventsPerFrame: Int = 2048) {
            self.maxTriggerEventsPerFrame = max(1, maxTriggerEventsPerFrame)
            self.maxCollisionEventsPerFrame = max(1, maxCollisionEventsPerFrame)
        }
    }

    public struct CharacterGroundProbe {
        public var isGrounded: Bool
        public var hitPosition: SIMD3<Float>
        public var hitNormal: SIMD3<Float>
        public var distance: Float

        public init(isGrounded: Bool = false,
                    hitPosition: SIMD3<Float> = .zero,
                    hitNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                    distance: Float = 0.0) {
            self.isGrounded = isGrounded
            self.hitPosition = hitPosition
            self.hitNormal = hitNormal
            self.distance = distance
        }
    }

    public struct CharacterSweepResult {
        public var finalPosition: SIMD3<Float>
        public var didCollide: Bool
        public var hitNormal: SIMD3<Float>
        public var hitPosition: SIMD3<Float>
        public var hitBodyId: UInt64
        public var travelFraction: Float

        public init(finalPosition: SIMD3<Float>,
                    didCollide: Bool,
                    hitNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                    hitPosition: SIMD3<Float> = .zero,
                    hitBodyId: UInt64 = 0,
                    travelFraction: Float = 1.0) {
            self.finalPosition = finalPosition
            self.didCollide = didCollide
            self.hitNormal = hitNormal
            self.hitPosition = hitPosition
            self.hitBodyId = hitBodyId
            self.travelFraction = travelFraction
        }
    }

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
    private var scriptEventQueueLimits = ScriptEventQueueLimits()
    private var scriptEventQueueTelemetry = ScriptEventQueueTelemetry()
    private var lastScriptEventOverflowLogTime: TimeInterval = 0.0
    private let scriptEventOverflowLogInterval: TimeInterval = 1.0
    private var sensorBodyIdsByEntity: [UUID: [UInt64]] = [:]
    private var runtimeSignatureByEntity: [UUID: Int] = [:]
    private var runtimeWorldScaleByEntity: [UUID: SIMD3<Float>] = [:]
    private var pendingKinematicTargets: [UInt64: KinematicTarget] = [:]
#if DEBUG
    private var warnedScaleEntities: Set<UUID> = []
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
        pullSimulatedTransforms(ecs: scene.ecs)
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
            if let controller = ecs.get(CharacterControllerComponent.self, for: entity),
               controller.isEnabled {
                clearRuntimeBodyBindingIfPresent(entity: entity, ecs: ecs)
                return
            }
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
        pendingKinematicTargets.removeAll(keepingCapacity: true)
    }

    public func fixedUpdate(scene: EngineScene, fixedDeltaTime: Float) {
        syncSettingsIfNeeded(scene: scene)
        guard settings.isEnabled else { return }
        let ecs = scene.ecs
        syncRuntimeBindings(scene: scene)
        syncSensorBodiesToParents(ecs: ecs)
        pushKinematicTransforms(ecs: ecs, fixedDeltaTime: fixedDeltaTime)
        world.step(dt: fixedDeltaTime)
        updateOverlapEvents()
        pullSimulatedTransforms(ecs: ecs)
    }

    public func rebuildBody(entity: Entity, scene: EngineScene) -> Bool {
        let ecs = scene.ecs
        if let controller = ecs.get(CharacterControllerComponent.self, for: entity),
           controller.isEnabled {
            clearRuntimeBodyBindingIfPresent(entity: entity, ecs: ecs)
            return false
        }
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

            if let controller = ecs.get(CharacterControllerComponent.self, for: entity) {
                let debugState = scene.characterDebugVisualization(entityId: entity.id)
                guard debugState.enabled else { return }
                let origin = ecs.worldTransform(for: entity).position
                let controllerColor = SIMD4<Float>(0.9, 0.95, 0.3, 0.9)
                let controllerRadius = max(0.02, controller.radius)
                let controllerHalfHeight = max(0.02, controller.height * 0.5 - controllerRadius)
                debugDraw.submitWireCapsule(transform: worldMatrix,
                                            radius: controllerRadius,
                                            halfHeight: controllerHalfHeight,
                                            color: controllerColor)
                let basisScale: Float = 0.35
                let forwardBasis = simd_length_squared(debugState.basisForward) > 1.0e-6
                    ? simd_normalize(debugState.basisForward)
                    : SIMD3<Float>(0.0, 0.0, 1.0)
                let rightBasis = simd_length_squared(debugState.basisRight) > 1.0e-6
                    ? simd_normalize(debugState.basisRight)
                    : SIMD3<Float>(1.0, 0.0, 0.0)
                let groundNormal = simd_length_squared(debugState.groundNormal) > 1.0e-6
                    ? simd_normalize(debugState.groundNormal)
                    : SIMD3<Float>(0.0, 1.0, 0.0)
                // Basis debug: right=red, forward=green, ground normal=blue.
                debugDraw.submitLine(origin, origin + rightBasis * basisScale, color: SIMD4<Float>(1.0, 0.2, 0.2, 0.95))
                debugDraw.submitLine(origin, origin + forwardBasis * basisScale, color: SIMD4<Float>(0.2, 1.0, 0.2, 0.95))
                debugDraw.submitLine(origin, origin + groundNormal * basisScale, color: SIMD4<Float>(0.2, 0.4, 1.0, 0.95))
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

    private func pushKinematicTransforms(ecs: SceneECS, fixedDeltaTime: Float) {
        ecs.forEachEntity { entity in
            if let controller = ecs.get(CharacterControllerComponent.self, for: entity),
               controller.isEnabled {
                return
            }
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  rigidbody.motionType == .kinematic,
                  let bodyId = rigidbody.bodyId,
                  ecs.get(TransformComponent.self, for: entity) != nil else {
                return
            }
            if let target = pendingKinematicTargets.removeValue(forKey: bodyId) {
                world.moveKinematic(bodyId: bodyId,
                                    position: target.position,
                                    rotation: target.rotation,
                                    dt: target.dt)
                return
            }
            let worldTransform = ecs.worldTransform(for: entity)
            world.moveKinematic(bodyId: bodyId,
                                position: worldTransform.position,
                                rotation: worldTransform.rotation,
                                dt: fixedDeltaTime)
        }
        pendingKinematicTargets.removeAll(keepingCapacity: true)
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

    public func scriptEventQueueStats() -> ScriptEventQueueTelemetry {
        scriptEventQueueTelemetry
    }

    public func scriptEventQueueConfig() -> ScriptEventQueueLimits {
        scriptEventQueueLimits
    }

    public func setScriptEventQueueLimits(_ limits: ScriptEventQueueLimits) {
        scriptEventQueueLimits = ScriptEventQueueLimits(maxTriggerEventsPerFrame: limits.maxTriggerEventsPerFrame,
                                                        maxCollisionEventsPerFrame: limits.maxCollisionEventsPerFrame)
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
        pendingKinematicTargets.removeValue(forKey: bodyId)
        return true
    }

    @discardableResult
    public func setBodyLinearVelocity(entity: Entity, scene: EngineScene, velocity: SIMD3<Float>) -> Bool {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              let bodyId = rigidbody.bodyId else { return false }
        guard rigidbody.motionType != .kinematic else {
            return false
        }
        let angular = world.getBodyVelocity(bodyId: bodyId)?.angular ?? SIMD3<Float>(repeating: 0.0)
        world.setBodyVelocity(bodyId: bodyId, linear: velocity, angular: angular)
        return true
    }

    @discardableResult
    public func setKinematicTarget(entity: Entity,
                                   scene: EngineScene,
                                   position: SIMD3<Float>,
                                   rotation: SIMD4<Float>,
                                   fixedDeltaTime: Float) -> Bool {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              rigidbody.isEnabled,
              rigidbody.motionType == .kinematic,
              let bodyId = rigidbody.bodyId else { return false }
        let dt = max(1.0e-4, fixedDeltaTime)
        pendingKinematicTargets[bodyId] = KinematicTarget(position: position,
                                                          rotation: TransformMath.normalizedQuaternion(rotation),
                                                          dt: dt)
        return true
    }

    public func bodyVelocity(entity: Entity, scene: EngineScene) -> SIMD3<Float>? {
        guard let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              let bodyId = rigidbody.bodyId else { return nil }
        return world.getBodyVelocity(bodyId: bodyId)?.linear
    }

    public func bodyVelocity(bodyId: UInt64) -> SIMD3<Float>? {
        world.getBodyVelocity(bodyId: bodyId)?.linear
    }

    func entityIdForBody(_ bodyId: UInt64) -> UUID? {
        world.entityIdForBody(bodyId)
    }

    func createCharacter(desc: PhysicsCharacterCreation) -> UInt64 {
        world.createCharacter(desc: desc)
    }

    func destroyCharacter(handle: UInt64) {
        world.destroyCharacter(handle: handle)
    }

    func setCharacterShapeCapsule(handle: UInt64, radius: Float, height: Float) {
        world.setCharacterShapeCapsule(handle: handle, radius: radius, height: height)
    }

    func setCharacterMaxSlope(handle: UInt64, radians: Float) {
        world.setCharacterMaxSlope(handle: handle, radians: radians)
    }

    func setCharacterStepOffset(handle: UInt64, meters: Float) {
        world.setCharacterStepOffset(handle: handle, meters: meters)
    }

    func setCharacterGravity(handle: UInt64, value: Float) {
        world.setCharacterGravity(handle: handle, value: value)
    }

    func setCharacterJumpSpeed(handle: UInt64, value: Float) {
        world.setCharacterJumpSpeed(handle: handle, value: value)
    }

    func setCharacterPushStrength(handle: UInt64, value: Float) {
        world.setCharacterPushStrength(handle: handle, value: value)
    }

    func setCharacterUpVector(handle: UInt64, up: SIMD3<Float>) {
        world.setCharacterUpVector(handle: handle, up: up)
    }

    @discardableResult
    func updateCharacter(handle: UInt64,
                         dt: Float,
                         desiredVelocity: SIMD3<Float>,
                         jumpRequested: Bool) -> Bool {
        world.updateCharacter(handle: handle, dt: dt, desiredVelocity: desiredVelocity, jumpRequested: jumpRequested)
    }

    func characterPosition(handle: UInt64) -> SIMD3<Float>? {
        world.characterPosition(handle: handle)
    }

    func characterRotation(handle: UInt64) -> SIMD4<Float>? {
        world.characterRotation(handle: handle)
    }

    func characterIsGrounded(handle: UInt64) -> Bool {
        world.characterIsGrounded(handle: handle)
    }

    func characterGroundNormal(handle: UInt64) -> SIMD3<Float> {
        world.characterGroundNormal(handle: handle)
    }

    func characterGroundVelocity(handle: UInt64) -> SIMD3<Float> {
        world.characterGroundVelocity(handle: handle)
    }

    func characterGroundBodyId(handle: UInt64) -> UInt64 {
        world.characterGroundBodyId(handle: handle)
    }

    func characterContactStats(handle: UInt64) -> (total: UInt32, dynamic: UInt32, firstDynamicBodyId: UInt64) {
        world.characterContactStats(handle: handle)
    }

    @discardableResult
    public func pushDynamicBody(bodyId: UInt64,
                                scene: EngineScene,
                                impulse: SIMD3<Float>) -> Bool {
        guard simd_length_squared(impulse) > 1.0e-8,
              let entityId = world.entityIdForBody(bodyId),
              let entity = scene.ecs.entity(with: entityId),
              let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity),
              rigidbody.isEnabled,
              rigidbody.motionType == .dynamic,
              let velocity = world.getBodyVelocity(bodyId: bodyId) else { return false }
        let inverseMass = 1.0 / max(0.001, rigidbody.mass)
        let deltaV = impulse * inverseMass
        let maxPushDelta: Float = 4.0
        let clampedDeltaV: SIMD3<Float> = {
            let len = simd_length(deltaV)
            guard len > maxPushDelta else { return deltaV }
            return deltaV / len * maxPushDelta
        }()
        world.setBodyVelocity(bodyId: bodyId,
                              linear: velocity.linear + clampedDeltaV,
                              angular: velocity.angular)
        world.setBodyActive(bodyId: bodyId, isActive: true)
        return true
    }

    public func sweepCharacter(entity: Entity,
                               scene: EngineScene,
                               startPosition: SIMD3<Float>,
                               desiredDelta: SIMD3<Float>,
                               radius: Float,
                               halfHeight: Float,
                               offset: SIMD3<Float>,
                               rotationOffset _: SIMD4<Float>,
                               maxSlideIterations: Int = 2,
                               layerMask: LayerMask? = nil) -> CharacterSweepResult {
        guard scene.ecs.get(TransformComponent.self, for: entity) != nil else {
            return CharacterSweepResult(finalPosition: startPosition, didCollide: false)
        }
        let safeRadius = max(0.02, radius)
        let safeHalfHeight = max(0.02, halfHeight)
        let capsuleRotation = TransformMath.identityQuaternion
        let worldOffset = offset
        let effectiveLayerMask = layerMask ?? defaultCharacterQueryMask(entity: entity, scene: scene)

        let requestedDistance = simd_length(desiredDelta)
        if requestedDistance <= 1.0e-6 {
            return CharacterSweepResult(finalPosition: startPosition, didCollide: false)
        }

        var remainingDelta = desiredDelta
        var resolvedDelta = SIMD3<Float>.zero
        var didCollide = false
        var lastNormal = SIMD3<Float>(0.0, 1.0, 0.0)
        var lastHitPosition = SIMD3<Float>.zero
        var lastHitBodyId: UInt64 = 0
        let skinWidth = max(0.002, safeRadius * 0.05)
        let maxIterations = max(1, maxSlideIterations)
        let castBasePosition = startPosition

        for _ in 0..<maxIterations {
            let segmentLength = simd_length(remainingDelta)
            if segmentLength <= 1.0e-6 { break }
            let castDirection = remainingDelta / segmentLength
            let castOrigin = castBasePosition + resolvedDelta + worldOffset
            guard let hit = filteredCapsuleCast(origin: castOrigin,
                                                rotation: capsuleRotation,
                                                direction: castDirection,
                                                halfHeight: safeHalfHeight,
                                                radius: safeRadius,
                                                maxDistance: segmentLength + skinWidth,
                                                ignoreEntityId: entity.id,
                                                layerMask: effectiveLayerMask,
                                                includeTriggers: false) else {
                resolvedDelta += remainingDelta
                break
            }

            didCollide = true
            let clampedDistance = max(0.0, min(segmentLength, hit.distance - skinWidth))
            resolvedDelta += castDirection * clampedDistance
            let normal = simd_length_squared(hit.normal) > 1.0e-6 ? simd_normalize(hit.normal) : SIMD3<Float>(0.0, 1.0, 0.0)
            lastNormal = normal
            lastHitPosition = hit.position
            lastHitBodyId = hit.bodyId
            let remainingDistance = max(0.0, segmentLength - clampedDistance)
            if remainingDistance <= 1.0e-4 {
                remainingDelta = .zero
                break
            }
            let remainderDirection = remainingDelta / segmentLength
            let remainder = remainderDirection * remainingDistance
            let normalComponent = simd_dot(remainder, normal)
            var slide = remainder - normal * normalComponent
            if simd_length_squared(slide) <= 1.0e-8 {
                remainingDelta = .zero
                break
            }
            if simd_dot(slide, remainingDelta) <= 0 {
                remainingDelta = .zero
                break
            }
            slide *= max(0.0, 1.0 - min(1.0, skinWidth / max(remainingDistance, 1.0e-4)))
            remainingDelta = slide
        }

        let finalPosition = startPosition + resolvedDelta
        let traveled = simd_length(resolvedDelta)
        let travelFraction = requestedDistance > 1.0e-6 ? min(1.0, traveled / requestedDistance) : 1.0
        return CharacterSweepResult(finalPosition: finalPosition,
                                    didCollide: didCollide,
                                    hitNormal: lastNormal,
                                    hitPosition: lastHitPosition,
                                    hitBodyId: lastHitBodyId,
                                    travelFraction: travelFraction)
    }

    public func resolveCharacterPenetration(entity: Entity,
                                            scene: EngineScene,
                                            position: SIMD3<Float>,
                                            radius: Float,
                                            halfHeight: Float,
                                            offset: SIMD3<Float>,
                                            maxIterations: Int = 4,
                                            skinWidth: Float = 0.02) -> (position: SIMD3<Float>, correction: SIMD3<Float>, maxDepth: Float) {
        let safeSkin = max(0.002, skinWidth)
        var current = position
        var accumulated = SIMD3<Float>.zero
        var maxDepth: Float = 0.0
        let directions: [SIMD3<Float>] = [
            SIMD3<Float>(0.0, 1.0, 0.0),
            SIMD3<Float>(1.0, 0.0, 0.0),
            SIMD3<Float>(-1.0, 0.0, 0.0),
            SIMD3<Float>(0.0, 0.0, 1.0),
            SIMD3<Float>(0.0, 0.0, -1.0)
        ]
        let effectiveLayerMask = defaultCharacterQueryMask(entity: entity, scene: scene)

        for _ in 0..<max(1, maxIterations) {
            var correction = SIMD3<Float>.zero
            var iterationMaxDepth: Float = 0.0
            for direction in directions {
                guard let hit = filteredCapsuleCast(origin: current + offset,
                                                    rotation: TransformMath.identityQuaternion,
                                                    direction: direction,
                                                    halfHeight: halfHeight,
                                                    radius: radius,
                                                    maxDistance: safeSkin + 0.03,
                                                    ignoreEntityId: entity.id,
                                                    layerMask: effectiveLayerMask,
                                                    includeTriggers: false) else {
                    continue
                }
                if hit.distance >= safeSkin { continue }
                let depth = safeSkin - hit.distance
                correction -= direction * depth
                iterationMaxDepth = max(iterationMaxDepth, depth)
            }
            if simd_length_squared(correction) <= 1.0e-10 { break }
            let correctionLen = simd_length(correction)
            let maxCorrection = safeSkin * 2.0
            if correctionLen > maxCorrection {
                correction = correction / correctionLen * maxCorrection
            }
            current += correction
            accumulated += correction
            maxDepth = max(maxDepth, iterationMaxDepth)
        }

        return (position: current, correction: accumulated, maxDepth: maxDepth)
    }

    public func isGrounded(entity: Entity, scene: EngineScene, probeDistance: Float = 0.2) -> Bool {
        let probe = characterGroundProbe(entity: entity,
                                         scene: scene,
                                         radius: 0.2,
                                         height: 1.8,
                                         probeDistance: probeDistance,
                                         maxSlopeDegrees: 89.0)
        return probe.isGrounded
    }

    public func characterGroundProbe(entity: Entity,
                                     scene: EngineScene,
                                     radius: Float,
                                     height: Float,
                                     probeDistance: Float,
                                     maxSlopeDegrees: Float,
                                     worldPositionOverride: SIMD3<Float>? = nil) -> CharacterGroundProbe {
        guard let capsule = characterCapsuleState(entity: entity,
                                                  scene: scene,
                                                  fallbackRadius: radius,
                                                  fallbackHeight: height,
                                                  worldPositionOverride: worldPositionOverride) else {
            return CharacterGroundProbe()
        }
        let probe = max(0.02, probeDistance)
        let castRadius = max(0.01, capsule.radius - 0.002)
        let skinWidth = max(0.002, castRadius * 0.05)
        let origin = capsule.center + SIMD3<Float>(0.0, skinWidth, 0.0)
        let castDistance = probe + skinWidth + 0.02
        let effectiveLayerMask = defaultCharacterQueryMask(entity: entity, scene: scene)
        let hit = filteredCapsuleCast(origin: origin,
                                      rotation: capsule.rotation,
                                      direction: SIMD3<Float>(0.0, -1.0, 0.0),
                                      halfHeight: capsule.halfHeight,
                                      radius: castRadius,
                                      maxDistance: castDistance,
                                      ignoreEntityId: entity.id,
                                      layerMask: effectiveLayerMask,
                                      includeTriggers: false)
        guard let hit else { return CharacterGroundProbe() }
        let slopeCos = cos(max(0.0, min(maxSlopeDegrees, 89.0)) * (Float.pi / 180.0))
        let normal = simd_normalize(hit.normal)
        let isGrounded = normal.y >= slopeCos
        let distanceToGround = max(0.0, hit.distance - skinWidth)
        return CharacterGroundProbe(isGrounded: isGrounded,
                                    hitPosition: hit.position,
                                    hitNormal: normal,
                                    distance: distanceToGround)
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

    public func raycastClosest(origin: SIMD3<Float>,
                               direction: SIMD3<Float>,
                               maxDistance: Float,
                               layerMask: LayerMask? = nil,
                               includeTriggers: Bool = false) -> PhysicsRaycastHit? {
        let effectiveLayerMask = layerMask ?? defaultGameplayQueryMask()
        return raycast(origin: origin,
                       direction: direction,
                       maxDistance: maxDistance,
                       layerMask: effectiveLayerMask,
                       includeTriggers: includeTriggers)
    }

    public func raycastForEditorPicking(origin: SIMD3<Float>,
                                        direction: SIMD3<Float>,
                                        maxDistance: Float,
                                        layerMask: LayerMask? = nil) -> PhysicsRaycastHit? {
        let effectiveLayerMask = layerMask ?? defaultEditorPickingMask()
        return raycast(origin: origin,
                       direction: direction,
                       maxDistance: maxDistance,
                       layerMask: effectiveLayerMask,
                       includeTriggers: false)
    }

    public func defaultGameplayLayerMask() -> LayerMask {
        defaultGameplayQueryMask()
    }

    public func defaultEditorPickingLayerMask() -> LayerMask {
        defaultEditorPickingMask()
    }

    public func sphereCastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, radius: Float, maxDistance: Float) -> PhysicsRaycastHit? {
        world.sphereCastClosest(origin: origin, direction: direction, radius: radius, maxDistance: maxDistance)
    }

    private func pullSimulatedTransforms(ecs: SceneECS) {
        ecs.forEachEntity { entity in
            if let controller = ecs.get(CharacterControllerComponent.self, for: entity),
               controller.isEnabled {
                return
            }
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  (rigidbody.motionType == .dynamic || rigidbody.motionType == .kinematic),
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

    private func filteredCapsuleCast(origin: SIMD3<Float>,
                                     rotation: SIMD4<Float>,
                                     direction: SIMD3<Float>,
                                     halfHeight: Float,
                                     radius: Float,
                                     maxDistance: Float,
                                     ignoreEntityId: UUID,
                                     layerMask: LayerMask,
                                     includeTriggers: Bool) -> PhysicsRaycastHit? {
        let directionLength = simd_length(direction)
        guard directionLength > 1e-6, maxDistance > 0 else { return nil }
        let normalizedDirection = direction / directionLength
        var currentOrigin = origin
        var traveledDistance: Float = 0.0
        var remainingDistance = maxDistance
        let maxIterations = 64
        let epsilonStep: Float = 0.005
        for _ in 0..<maxIterations {
            guard let candidate = world.capsuleCastClosest(origin: currentOrigin,
                                                           rotation: rotation,
                                                           direction: normalizedDirection,
                                                           halfHeight: halfHeight,
                                                           radius: radius,
                                                           maxDistance: remainingDistance) else {
                return nil
            }
            let isSelf = candidate.entityId == ignoreEntityId
            let isTrigger = world.isTriggerBody(candidate.bodyId)
            let layer = world.collisionLayerForBody(candidate.bodyId)
            let layerPasses = layerMask.contains(layerIndex: layer)
            let triggerPasses = includeTriggers || !isTrigger
            let absoluteDistance = traveledDistance + candidate.distance
            if !isSelf && layerPasses && triggerPasses {
                var accepted = candidate
                accepted.distance = absoluteDistance
                return accepted
            }
            let selfSkip = isSelf ? max(radius * 0.75, 0.05) : epsilonStep
            let advance = max(candidate.distance + max(epsilonStep, selfSkip), epsilonStep)
            traveledDistance += advance
            if traveledDistance >= maxDistance {
                return nil
            }
            remainingDistance = maxDistance - traveledDistance
            currentOrigin = origin + normalizedDirection * traveledDistance
        }
        return nil
    }

    private func defaultGameplayQueryMask() -> LayerMask {
        layerMaskForCollisionLayer(LayerCatalog.defaultLayerIndex)
    }

    private func defaultEditorPickingMask() -> LayerMask {
        layerMaskForCollisionLayer(LayerCatalog.defaultLayerIndex)
    }

    private func defaultCharacterQueryMask(entity: Entity, scene: EngineScene) -> LayerMask {
        let collisionLayer = scene.ecs.get(RigidbodyComponent.self, for: entity)?.collisionLayer ?? LayerCatalog.defaultLayerIndex
        return layerMaskForCollisionLayer(collisionLayer)
    }

    private func layerMaskForCollisionLayer(_ layer: Int32) -> LayerMask {
        guard !settings.collisionMatrix.isEmpty else { return .all }
        let clampedLayer = max(0, min(Int(layer), settings.collisionMatrix.count - 1))
        return LayerMask(rawValue: settings.collisionMatrix[clampedLayer])
    }

    private func characterCapsuleState(entity: Entity,
                                       scene: EngineScene,
                                       fallbackRadius: Float,
                                       fallbackHeight: Float,
                                       worldPositionOverride: SIMD3<Float>? = nil) -> CharacterCapsuleState? {
        guard scene.ecs.get(TransformComponent.self, for: entity) != nil else { return nil }
        let worldTransform = scene.ecs.worldTransform(for: entity)
        let bodyPosition = worldPositionOverride ?? worldTransform.position
        let bodyRotation = TransformMath.normalizedQuaternion(worldTransform.rotation)
        let yaw = atan2(2.0 * (bodyRotation.w * bodyRotation.y + bodyRotation.x * bodyRotation.z),
                        1.0 - 2.0 * (bodyRotation.y * bodyRotation.y + bodyRotation.z * bodyRotation.z))
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0.0, 1.0, 0.0)).vector
        let sourceShape: ColliderShape
        if let collider = scene.ecs.get(ColliderComponent.self, for: entity) {
            let solidCapsule = collider.allShapes().first { $0.isEnabled && !$0.isTrigger && $0.shapeType == .capsule }
            if let solidCapsule {
                sourceShape = solidCapsule
            } else {
                let safeRadius = max(0.05, fallbackRadius)
                let standingHalfHeight = max(safeRadius, fallbackHeight * 0.5)
                sourceShape = ColliderShape(shapeType: .capsule,
                                            sphereRadius: safeRadius,
                                            capsuleHalfHeight: max(0.05, standingHalfHeight - safeRadius),
                                            capsuleRadius: safeRadius)
            }
        } else {
            let safeRadius = max(0.05, fallbackRadius)
            let standingHalfHeight = max(safeRadius, fallbackHeight * 0.5)
            sourceShape = ColliderShape(shapeType: .capsule,
                                        sphereRadius: safeRadius,
                                        capsuleHalfHeight: max(0.05, standingHalfHeight - safeRadius),
                                        capsuleRadius: safeRadius)
        }
        let scaled = PhysicsMath.scaledShape(from: sourceShape, scale: worldTransform.scale)
        let radius = max(0.02, scaled.capsuleRadius)
        let halfHeight = max(0.02, scaled.capsuleHalfHeight)
        let rotationOffset = TransformMath.identityQuaternion
        let capsuleRotation = TransformMath.identityQuaternion
        let offsetWorld = simd_quatf(vector: yawRotation).act(scaled.offset)
        return CharacterCapsuleState(center: bodyPosition + offsetWorld,
                                     rotation: capsuleRotation,
                                     radius: radius,
                                     halfHeight: halfHeight,
                                     offset: scaled.offset,
                                     rotationOffset: rotationOffset)
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
                EngineLoggerContext.log(
                    "Physics body created entity=\(entity.id.uuidString) motionType=\(rigidbody.motionType.rawValue) layer=\(layer) isSensor=false solidShapes=\(solidShapes.count)",
                    level: .debug,
                    category: .scene
                )
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
                EngineLoggerContext.log(
                    "Physics body created entity=\(entity.id.uuidString) motionType=\(triggerMotionType.rawValue) layer=\(layer) isSensor=true solidShapes=0",
                    level: .debug,
                    category: .scene
                )
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
            if let controller = ecs.get(CharacterControllerComponent.self, for: entity),
               controller.isEnabled {
                clearRuntimeBodyBindingIfPresent(entity: entity, ecs: ecs)
                runtimeSignatureByEntity.removeValue(forKey: entity.id)
                runtimeWorldScaleByEntity.removeValue(forKey: entity.id)
                return
            }
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

    private func clearRuntimeBodyBindingIfPresent(entity: Entity, ecs: SceneECS) {
        if var rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
           let bodyId = rigidbody.bodyId {
            world.destroyBody(bodyId: bodyId)
            rigidbody.bodyId = nil
            ecs.add(rigidbody, to: entity)
        }
        if let sensorBodies = sensorBodyIdsByEntity[entity.id] {
            for sensorBody in sensorBodies {
                world.destroyBody(bodyId: sensorBody)
            }
            sensorBodyIdsByEntity.removeValue(forKey: entity.id)
        }
        runtimeSignatureByEntity.removeValue(forKey: entity.id)
        runtimeWorldScaleByEntity.removeValue(forKey: entity.id)
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
        scriptEventQueueTelemetry.droppedCollisionEvents = 0
        scriptEventQueueTelemetry.droppedTriggerEvents = 0
        scriptEventQueueTelemetry.droppedStayEvents = 0
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

        let maxTriggerEvents = max(1, scriptEventQueueLimits.maxTriggerEventsPerFrame)
        let maxCollisionEvents = max(1, scriptEventQueueLimits.maxCollisionEventsPerFrame)
        scriptEvents.reserveCapacity(min(triggerEnter.count + triggerStay.count + triggerExit.count, maxTriggerEvents) +
                                     min(collisionEnter.count + collisionStay.count + collisionExit.count, maxCollisionEvents))
        var deliveredTriggerEvents = 0
        var deliveredCollisionEvents = 0

        // Deterministic policy:
        // 1) preserve enter/exit before stay
        // 2) once cap is reached, deterministically drop remaining newest events in this ordered pass
        appendScriptEvents(keys: triggerEnter, type: .triggerEnter, maxEvents: maxTriggerEvents, deliveredEvents: &deliveredTriggerEvents)
        appendScriptEvents(keys: triggerExit, type: .triggerExit, maxEvents: maxTriggerEvents, deliveredEvents: &deliveredTriggerEvents)
        appendScriptEvents(keys: triggerStay, type: .triggerStay, maxEvents: maxTriggerEvents, deliveredEvents: &deliveredTriggerEvents)
        appendScriptEvents(keys: collisionEnter, type: .collisionEnter, maxEvents: maxCollisionEvents, deliveredEvents: &deliveredCollisionEvents)
        appendScriptEvents(keys: collisionExit, type: .collisionExit, maxEvents: maxCollisionEvents, deliveredEvents: &deliveredCollisionEvents)
        appendScriptEvents(keys: collisionStay, type: .collisionStay, maxEvents: maxCollisionEvents, deliveredEvents: &deliveredCollisionEvents)

        scriptEventQueueTelemetry.totalDroppedCollisionEvents += scriptEventQueueTelemetry.droppedCollisionEvents
        scriptEventQueueTelemetry.totalDroppedTriggerEvents += scriptEventQueueTelemetry.droppedTriggerEvents
        scriptEventQueueTelemetry.totalDroppedStayEvents += scriptEventQueueTelemetry.droppedStayEvents
        logScriptEventOverflowIfNeeded()

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

    private func appendScriptEvents(keys: [OverlapKey],
                                    type: PhysicsScriptEventType,
                                    maxEvents: Int,
                                    deliveredEvents: inout Int) {
        for key in keys {
            guard deliveredEvents < maxEvents else {
                if type.isCollision {
                    scriptEventQueueTelemetry.droppedCollisionEvents += 1
                } else {
                    scriptEventQueueTelemetry.droppedTriggerEvents += 1
                }
                if type.isStay {
                    scriptEventQueueTelemetry.droppedStayEvents += 1
                }
                continue
            }
            scriptEvents.append(
                PhysicsScriptEvent(type: type,
                                   entityA: key.a,
                                   entityB: key.b,
                                   shapeA: nil,
                                   shapeB: nil)
            )
            deliveredEvents += 1
        }
    }

    private func logScriptEventOverflowIfNeeded() {
        let droppedTotal = scriptEventQueueTelemetry.droppedCollisionEvents + scriptEventQueueTelemetry.droppedTriggerEvents
        guard droppedTotal > 0 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastScriptEventOverflowLogTime >= scriptEventOverflowLogInterval else { return }
        lastScriptEventOverflowLogTime = now
        EngineLoggerContext.log(
            "Physics script event queue overflow: droppedCollisionEvents=\(scriptEventQueueTelemetry.droppedCollisionEvents), droppedTriggerEvents=\(scriptEventQueueTelemetry.droppedTriggerEvents), droppedStayEvents=\(scriptEventQueueTelemetry.droppedStayEvents), caps(trigger=\(scriptEventQueueLimits.maxTriggerEventsPerFrame), collision=\(scriptEventQueueLimits.maxCollisionEventsPerFrame))",
            level: .warning,
            category: .scene
        )
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
        pullSimulatedTransforms(ecs: ecs)
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

    var isCollision: Bool {
        switch self {
        case .collisionEnter, .collisionStay, .collisionExit:
            return true
        case .triggerEnter, .triggerStay, .triggerExit:
            return false
        }
    }

    var isStay: Bool {
        switch self {
        case .collisionStay, .triggerStay:
            return true
        case .collisionEnter, .collisionExit, .triggerEnter, .triggerExit:
            return false
        }
    }
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

private struct KinematicTarget {
    let position: SIMD3<Float>
    let rotation: SIMD4<Float>
    let dt: Float
}

private struct CharacterCapsuleState {
    let center: SIMD3<Float>
    let rotation: SIMD4<Float>
    let radius: Float
    let halfHeight: Float
    let offset: SIMD3<Float>
    let rotationOffset: SIMD4<Float>
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
