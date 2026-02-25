/// PhysicsSystem.swift
/// Defines PhysicsSystem to sync ECS with Jolt.
/// Created by Codex.
/// Euler rotation order is XYZ (rotate X, then Y, then Z) across the engine.

import Foundation
import simd

public final class PhysicsSystem {
    private static let positionWritebackEpsilon: Float = 1e-4
    private static let rotationWritebackEpsilon: Float = 1e-4
    private var world: PhysicsWorld
    private let settings: PhysicsSettings
    private var warnedEntities: Set<UUID> = []
    private var overlapEvents: [PhysicsOverlapEvent] = []
    private var activeOverlaps: Set<OverlapKey> = []
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
    }

    public func buildBodies(scene: EngineScene) {
        let ecs = scene.ecs
        overlapEvents.removeAll(keepingCapacity: true)
        activeOverlaps.removeAll(keepingCapacity: true)
        for entity in ecs.allEntities() {
            guard let transform = ecs.get(TransformComponent.self, for: entity) else { continue }
            guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity) else {
                if ecs.has(ColliderComponent.self, entity) {
                    logWarningOnce(entityId: entity.id, message: "Collider present without Rigidbody. Add a Rigidbody to enable physics.")
                }
                continue
            }
            guard let collider = ecs.get(ColliderComponent.self, for: entity) else {
                logWarningOnce(entityId: entity.id, message: "Rigidbody present without Collider. Add a Collider to enable physics.")
                continue
            }
            guard rigidbody.isEnabled, collider.isEnabled else { continue }
            guard validateCollider(entityId: entity.id, collider: collider) else { continue }
#if DEBUG
            logScaleWarningIfNeeded(entityId: entity.id, collider: collider, scale: transform.scale)
#endif

            let userData = world.userData(for: entity.id)
            let creation = PhysicsSystem.buildBodyCreation(rigidbody: rigidbody,
                                                          collider: collider,
                                                          transform: transform,
                                                          settings: settings,
                                                          userData: userData)
            let bodyId = world.createBody(desc: creation)
            if bodyId != 0 {
                rigidbody.bodyId = bodyId
                ecs.add(rigidbody, to: entity)
#if DEBUG
                if let fetched = world.getBodyTransform(bodyId: bodyId) {
                    let ecsRotation = transform.rotation
                    let posDelta = simd_length(fetched.position - transform.position)
                    let angDelta = PhysicsSystem.angularDeltaDegrees(ecsRotation, fetched.rotation)
                    EngineLoggerContext.log(
                        String(format: "Physics Debug Body '%@': create delta pos=%.6f, ang=%.4f°",
                               entity.id.uuidString, posDelta, angDelta),
                        level: .debug,
                        category: .scene
                    )
                }

                if debugEntityId == nil, rigidbody.motionType == .dynamic {
                    debugEntityId = entity.id
                }
#endif
            }
        }
    }

    public func destroyBodies(scene: EngineScene) {
        let ecs = scene.ecs
        for entity in ecs.allEntities() {
            guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  let bodyId = rigidbody.bodyId else {
                continue
            }
            world.destroyBody(bodyId: bodyId)
            rigidbody.bodyId = nil
            ecs.add(rigidbody, to: entity)
        }
        overlapEvents.removeAll(keepingCapacity: true)
        activeOverlaps.removeAll(keepingCapacity: true)
    }

    public func fixedUpdate(scene: EngineScene, fixedDeltaTime: Float) {
        guard settings.isEnabled else { return }
        let ecs = scene.ecs
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
        if hasSteppedOnce {
            pullDynamicTransforms(ecs: ecs)
        } else if settings.resolveInitialOverlap {
            pullDynamicTransforms(ecs: ecs)
#if DEBUG
            EngineLoggerContext.log(
                "Physics Debug Body: initial overlap resolution applied after first step.",
                level: .debug,
                category: .scene
            )
#endif
        }
        hasSteppedOnce = true
    }

    public func rebuildBody(entity: Entity, scene: EngineScene) -> Bool {
        let ecs = scene.ecs
        guard var rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
              let collider = ecs.get(ColliderComponent.self, for: entity),
              let transform = ecs.get(TransformComponent.self, for: entity) else {
            return false
        }
        if let bodyId = rigidbody.bodyId {
            world.destroyBody(bodyId: bodyId)
            rigidbody.bodyId = nil
        }
        guard rigidbody.isEnabled, collider.isEnabled else {
            ecs.add(rigidbody, to: entity)
            return false
        }
        guard validateCollider(entityId: entity.id, collider: collider) else { return false }
#if DEBUG
        logScaleWarningIfNeeded(entityId: entity.id, collider: collider, scale: transform.scale)
#endif

        let userData = world.userData(for: entity.id)
        let creation = PhysicsSystem.buildBodyCreation(rigidbody: rigidbody,
                                                      collider: collider,
                                                      transform: transform,
                                                      settings: settings,
                                                      userData: userData)
        let bodyId = world.createBody(desc: creation)
        if bodyId == 0 { return false }
        rigidbody.bodyId = bodyId
        ecs.add(rigidbody, to: entity)
        return true
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
                  let transform = ecs.get(TransformComponent.self, for: entity) else { continue }
            let rigidbody = ecs.get(RigidbodyComponent.self, for: entity)
            if let bodyId = rigidbody?.bodyId {
                bodyState[bodyId] = (motionType: rigidbody?.motionType ?? .staticBody, isTrigger: collider.isTrigger)
            }
            let baseColor = debugColor(rigidbody: rigidbody, collider: collider, isSelected: selectionId == entity.id)
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
            let scaled = PhysicsMath.scaledShape(from: collider, scale: transform.scale)
            let worldMatrix = PhysicsMath.transformMatrix(position: transform.position, rotation: transform.rotation)
            let offsetRotation = TransformMath.quaternionFromEulerXYZ(collider.rotationOffset)
            let offsetMatrix = PhysicsMath.transformMatrix(position: scaled.offset, rotation: offsetRotation)
            let colliderMatrix = matrix_multiply(worldMatrix, offsetMatrix)

            if drawColliders {
                switch collider.shapeType {
                case .box:
                    debugDraw.submitWireBox(transform: colliderMatrix, halfExtents: scaled.boxHalfExtents, color: color)
                case .sphere:
                    debugDraw.submitWireSphere(transform: colliderMatrix, radius: scaled.sphereRadius, color: color)
                case .capsule:
                    debugDraw.submitWireCapsule(transform: colliderMatrix, radius: scaled.capsuleRadius, halfHeight: scaled.capsuleHalfHeight, color: color)
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
                          let transformA = ecs.get(TransformComponent.self, for: entityA),
                          let transformB = ecs.get(TransformComponent.self, for: entityB) else { continue }
                    debugDraw.submitLine(transformA.position, transformB.position,
                                         color: SIMD4<Float>(0.85, 0.4, 1.0, 0.9))
                }
            }
        }
    }

    private func pushKinematicTransforms(ecs: SceneECS) {
        for entity in ecs.allEntities() {
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  rigidbody.motionType == .kinematic,
                  let bodyId = rigidbody.bodyId,
                  let transform = ecs.get(TransformComponent.self, for: entity) else {
                continue
            }
            let rotation = transform.rotation
            world.setBodyTransform(bodyId: bodyId, position: transform.position, rotation: rotation)
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

    public func activeOverlapPairs() -> [OverlapPair] {
        activeOverlaps.map { OverlapPair(a: $0.a, b: $0.b) }
    }

    public func isBodySleeping(bodyId: UInt64) -> Bool {
        world.isBodySleeping(bodyId: bodyId)
    }

    public func raycastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> PhysicsRaycastHit? {
        world.raycastClosest(origin: origin, direction: direction, maxDistance: maxDistance)
    }

    public func sphereCastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, radius: Float, maxDistance: Float) -> PhysicsRaycastHit? {
        world.sphereCastClosest(origin: origin, direction: direction, radius: radius, maxDistance: maxDistance)
    }

    private func pullDynamicTransforms(ecs: SceneECS) {
        for entity in ecs.allEntities() {
            guard let rigidbody = ecs.get(RigidbodyComponent.self, for: entity),
                  rigidbody.isEnabled,
                  rigidbody.motionType == .dynamic,
                  let bodyId = rigidbody.bodyId,
                  let transform = ecs.get(TransformComponent.self, for: entity) else {
                continue
            }
            guard let result = world.getBodyTransform(bodyId: bodyId) else { continue }
            let positionDelta = simd_length(result.position - transform.position)
            let currentQuat = transform.rotation
            let rotationDelta = PhysicsSystem.quaternionAngleDelta(currentQuat, result.rotation)
            if positionDelta <= Self.positionWritebackEpsilon,
               rotationDelta <= Self.rotationWritebackEpsilon {
                continue
            }
            var updated = transform
            updated.position = result.position
            updated.rotation = TransformMath.normalizedQuaternion(result.rotation)
            ecs.add(updated, to: entity)
        }
    }

    private static func buildBodyCreation(rigidbody: RigidbodyComponent,
                                          collider: ColliderComponent,
                                          transform: TransformComponent,
                                          settings: PhysicsSettings,
                                          userData: UInt64) -> PhysicsBodyCreation {
        let scaled = PhysicsMath.scaledShape(from: collider, scale: transform.scale)
        return PhysicsBodyCreation(
            shapeType: collider.shapeType,
            motionType: rigidbody.motionType,
            position: transform.position,
            rotation: transform.rotation,
            boxHalfExtents: scaled.boxHalfExtents,
            sphereRadius: scaled.sphereRadius,
            capsuleHalfHeight: scaled.capsuleHalfHeight,
            capsuleRadius: scaled.capsuleRadius,
            offset: scaled.offset,
            rotationOffset: PhysicsMath.quaternionFromEuler(collider.rotationOffset),
            friction: rigidbody.friction,
            restitution: rigidbody.restitution,
            linearDamping: rigidbody.linearDamping,
            angularDamping: rigidbody.angularDamping,
            gravityFactor: rigidbody.gravityFactor,
            mass: rigidbody.mass,
            userData: userData,
            ccdEnabled: settings.ccdEnabled || rigidbody.ccdEnabled,
            isTrigger: collider.isTrigger,
            allowSleeping: rigidbody.allowSleeping
        )
    }

    private func validateCollider(entityId: UUID, collider: ColliderComponent) -> Bool {
        switch collider.shapeType {
        case .box:
            if collider.boxHalfExtents.x <= 0 || collider.boxHalfExtents.y <= 0 || collider.boxHalfExtents.z <= 0 {
                logWarningOnce(entityId: entityId, message: "Box collider has invalid half extents. Update values > 0.")
                return false
            }
        case .sphere:
            if collider.sphereRadius <= 0 {
                logWarningOnce(entityId: entityId, message: "Sphere collider has invalid radius. Update value > 0.")
                return false
            }
        case .capsule:
            if collider.capsuleRadius <= 0 || collider.capsuleHalfHeight <= 0 {
                logWarningOnce(entityId: entityId, message: "Capsule collider has invalid radius/half height. Update values > 0.")
                return false
            }
        }
        return true
    }

    private func logWarningOnce(entityId: UUID, message: String) {
        if warnedEntities.contains(entityId) { return }
        warnedEntities.insert(entityId)
        EngineLoggerContext.log(message, level: .warning, category: .scene)
    }

#if DEBUG
    private func logScaleWarningIfNeeded(entityId: UUID, collider: ColliderComponent, scale: SIMD3<Float>) {
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
        if overlapEvents.isEmpty { return }
        for event in overlapEvents {
            guard let entityA = event.entityIdA, let entityB = event.entityIdB else { continue }
            let key = OverlapKey(a: entityA, b: entityB)
            if event.isBegin {
                activeOverlaps.insert(key)
            } else {
                activeOverlaps.remove(key)
            }
        }
    }

    private static func debugColor(rigidbody: RigidbodyComponent?, collider: ColliderComponent, isSelected: Bool) -> SIMD4<Float> {
        if isSelected { return SIMD4<Float>(1.0, 0.9, 0.2, 1.0) }
        if collider.isTrigger { return SIMD4<Float>(1.0, 0.65, 0.2, 0.95) }
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

    static func scaledShape(from collider: ColliderComponent, scale: SIMD3<Float>) -> (boxHalfExtents: SIMD3<Float>, sphereRadius: Float, capsuleHalfHeight: Float, capsuleRadius: Float, offset: SIMD3<Float>) {
        let absScale = SIMD3<Float>(abs(scale.x), abs(scale.y), abs(scale.z))
        let offset = collider.offset * absScale

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

    static func transformMatrix(position: SIMD3<Float>, rotation: SIMD4<Float>) -> matrix_float4x4 {
        TransformMath.makeMatrix(position: position,
                                 rotation: rotation,
                                 scale: SIMD3<Float>(repeating: 1.0))
    }
}
