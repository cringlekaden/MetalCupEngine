/// PhysicsWorld.swift
/// Defines the PhysicsWorld wrapper around Jolt.
/// Created by Codex.

import Foundation
import simd

@_silgen_name("MCEPhysicsCreateWorld")
private func MCEPhysicsCreateWorld(_ gravityX: Float,
                                   _ gravityY: Float,
                                   _ gravityZ: Float,
                                   _ maxBodies: UInt32,
                                   _ maxBodyPairs: UInt32,
                                   _ maxContactConstraints: UInt32,
                                   _ singleThreaded: UInt32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEPhysicsDestroyWorld")
private func MCEPhysicsDestroyWorld(_ world: UnsafeMutableRawPointer?)

@_silgen_name("MCEPhysicsWorldSetGravity")
private func MCEPhysicsWorldSetGravity(_ world: UnsafeMutableRawPointer?, _ gravityX: Float, _ gravityY: Float, _ gravityZ: Float)

@_silgen_name("MCEPhysicsStepWorld")
private func MCEPhysicsStepWorld(_ world: UnsafeMutableRawPointer?, _ dt: Float, _ collisionSteps: UInt32)

@_silgen_name("MCEPhysicsCreateBody")
private func MCEPhysicsCreateBody(_ world: UnsafeMutableRawPointer?,
                                  _ shapeType: UInt32,
                                  _ motionType: UInt32,
                                  _ posX: Float, _ posY: Float, _ posZ: Float,
                                  _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                  _ boxHX: Float, _ boxHY: Float, _ boxHZ: Float,
                                  _ sphereRadius: Float,
                                  _ capsuleHalfHeight: Float,
                                  _ capsuleRadius: Float,
                                  _ offsetX: Float, _ offsetY: Float, _ offsetZ: Float,
                                  _ rotOffsetX: Float, _ rotOffsetY: Float, _ rotOffsetZ: Float, _ rotOffsetW: Float,
                                  _ friction: Float,
                                  _ restitution: Float,
                                  _ linearDamping: Float,
                                  _ angularDamping: Float,
                                  _ gravityFactor: Float,
                                  _ mass: Float,
                                  _ userData: UInt64,
                                  _ ccdEnabled: UInt32,
                                  _ isSensor: UInt32,
                                  _ allowSleeping: UInt32) -> UInt64

@_silgen_name("MCEPhysicsDestroyBody")
private func MCEPhysicsDestroyBody(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64)

@_silgen_name("MCEPhysicsSetBodyTransform")
private func MCEPhysicsSetBodyTransform(_ world: UnsafeMutableRawPointer?,
                                        _ bodyId: UInt64,
                                        _ posX: Float, _ posY: Float, _ posZ: Float,
                                        _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float)

@_silgen_name("MCEPhysicsGetBodyTransform")
private func MCEPhysicsGetBodyTransform(_ world: UnsafeMutableRawPointer?,
                                        _ bodyId: UInt64,
                                        _ positionOut: UnsafeMutablePointer<Float>?,
                                        _ rotationOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCEPhysicsSetBodyMotionType")
private func MCEPhysicsSetBodyMotionType(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64, _ motionType: UInt32)

@_silgen_name("MCEPhysicsCopyLastContacts")
private func MCEPhysicsCopyLastContacts(_ world: UnsafeMutableRawPointer?,
                                        _ buffer: UnsafeMutablePointer<Float>?,
                                        _ maxContacts: UInt32) -> UInt32

@_silgen_name("MCEPhysicsCopyLastContactBodyIds")
private func MCEPhysicsCopyLastContactBodyIds(_ world: UnsafeMutableRawPointer?,
                                              _ buffer: UnsafeMutablePointer<UInt64>?,
                                              _ maxContacts: UInt32) -> UInt32

@_silgen_name("MCEPhysicsClearLastContacts")
private func MCEPhysicsClearLastContacts(_ world: UnsafeMutableRawPointer?)

@_silgen_name("MCEPhysicsIsBodySleeping")
private func MCEPhysicsIsBodySleeping(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64) -> UInt32

@_silgen_name("MCEPhysicsRaycastClosest")
private func MCEPhysicsRaycastClosest(_ world: UnsafeMutableRawPointer?,
                                      _ originX: Float, _ originY: Float, _ originZ: Float,
                                      _ dirX: Float, _ dirY: Float, _ dirZ: Float,
                                      _ maxDistance: Float,
                                      _ positionOut: UnsafeMutablePointer<Float>?,
                                      _ normalOut: UnsafeMutablePointer<Float>?,
                                      _ distanceOut: UnsafeMutablePointer<Float>?,
                                      _ bodyIdOut: UnsafeMutablePointer<UInt64>?,
                                      _ userDataOut: UnsafeMutablePointer<UInt64>?) -> UInt32

@_silgen_name("MCEPhysicsSphereCastClosest")
private func MCEPhysicsSphereCastClosest(_ world: UnsafeMutableRawPointer?,
                                         _ originX: Float, _ originY: Float, _ originZ: Float,
                                         _ dirX: Float, _ dirY: Float, _ dirZ: Float,
                                         _ radius: Float,
                                         _ maxDistance: Float,
                                         _ positionOut: UnsafeMutablePointer<Float>?,
                                         _ normalOut: UnsafeMutablePointer<Float>?,
                                         _ distanceOut: UnsafeMutablePointer<Float>?,
                                         _ bodyIdOut: UnsafeMutablePointer<UInt64>?,
                                         _ userDataOut: UnsafeMutablePointer<UInt64>?) -> UInt32

@_silgen_name("MCEPhysicsCopyOverlapEvents")
private func MCEPhysicsCopyOverlapEvents(_ world: UnsafeMutableRawPointer?,
                                         _ bodyAOut: UnsafeMutablePointer<UInt64>?,
                                         _ bodyBOut: UnsafeMutablePointer<UInt64>?,
                                         _ userDataAOut: UnsafeMutablePointer<UInt64>?,
                                         _ userDataBOut: UnsafeMutablePointer<UInt64>?,
                                         _ isBeginOut: UnsafeMutablePointer<UInt32>?,
                                         _ maxEvents: UInt32) -> UInt32

public struct PhysicsSettings {
    public enum QualityPreset: UInt32, CaseIterable {
        case low = 0
        case medium = 1
        case high = 2

        var solverIterations: UInt32 {
            switch self {
            case .low:
                return 1
            case .medium:
                return 2
            case .high:
                return 4
            }
        }
    }

    public var isEnabled: Bool
    public var gravity: SIMD3<Float>
    /// Jolt collision steps (substeps), not solver iterations.
    public var solverIterations: UInt32
    public var qualityPreset: QualityPreset
    public var fixedDeltaTime: Float
    public var maxSubsteps: Int
    public var defaultFriction: Float
    public var defaultRestitution: Float
    public var defaultAngularDamping: Float
    public var ccdEnabled: Bool
    public var resolveInitialOverlap: Bool
    public var deterministic: Bool
    public var debugDrawEnabled: Bool
    public var debugDrawInPlay: Bool
    public var showColliders: Bool
    public var showCOMAxes: Bool
    public var showContacts: Bool
    public var showSleeping: Bool
    public var showOverlaps: Bool

    public init(isEnabled: Bool = true,
                gravity: SIMD3<Float> = SIMD3<Float>(0.0, -9.81, 0.0),
                solverIterations: UInt32 = 1,
                qualityPreset: QualityPreset = .medium,
                fixedDeltaTime: Float = 1.0 / 60.0,
                maxSubsteps: Int = 4,
                defaultFriction: Float = 0.6,
                defaultRestitution: Float = 0.0,
                defaultAngularDamping: Float = 0.2,
                ccdEnabled: Bool = false,
                resolveInitialOverlap: Bool = false,
                deterministic: Bool = false,
                debugDrawEnabled: Bool = true,
                debugDrawInPlay: Bool = false,
                showColliders: Bool = true,
                showCOMAxes: Bool = false,
                showContacts: Bool = false,
                showSleeping: Bool = false,
                showOverlaps: Bool = false) {
        self.isEnabled = isEnabled
        self.gravity = gravity
        self.qualityPreset = qualityPreset
        let resolvedSolver = max(1, solverIterations)
        self.solverIterations = max(resolvedSolver, qualityPreset.solverIterations)
        self.fixedDeltaTime = max(0.0001, fixedDeltaTime)
        self.maxSubsteps = max(1, min(maxSubsteps, 4))
        self.defaultFriction = min(max(defaultFriction, 0.0), 1.0)
        self.defaultRestitution = min(max(defaultRestitution, 0.0), 1.0)
        self.defaultAngularDamping = max(0.0, defaultAngularDamping)
        self.ccdEnabled = ccdEnabled
        self.resolveInitialOverlap = resolveInitialOverlap
        self.deterministic = deterministic
        self.debugDrawEnabled = debugDrawEnabled
        self.debugDrawInPlay = debugDrawInPlay
        self.showColliders = showColliders
        self.showCOMAxes = showCOMAxes
        self.showContacts = showContacts
        self.showSleeping = showSleeping
        self.showOverlaps = showOverlaps
    }
}

public final class PhysicsWorld {
    private var handle: UnsafeMutableRawPointer?
    private(set) var settings: PhysicsSettings
    private var contactFloatBuffer: [Float] = Array(repeating: 0.0, count: 256 * 6)
    private var contactBodyIdBuffer: [UInt64] = Array(repeating: 0, count: 256)
    private var overlapBodyA: [UInt64] = Array(repeating: 0, count: 256)
    private var overlapBodyB: [UInt64] = Array(repeating: 0, count: 256)
    private var overlapUserDataA: [UInt64] = Array(repeating: 0, count: 256)
    private var overlapUserDataB: [UInt64] = Array(repeating: 0, count: 256)
    private var overlapIsBegin: [UInt32] = Array(repeating: 0, count: 256)
    private var nextUserData: UInt64 = 1
    private var userDataForEntity: [UUID: UInt64] = [:]
    private var entityForUserData: [UInt64: UUID] = [:]
    private var bodyUserData: [UInt64: UInt64] = [:]

    public init?(settings: PhysicsSettings,
                 maxBodies: UInt32 = 1024,
                 maxBodyPairs: UInt32 = 1024,
                 maxContactConstraints: UInt32 = 1024) {
        guard settings.isEnabled else { return nil }
        self.settings = settings
        self.handle = MCEPhysicsCreateWorld(settings.gravity.x,
                                            settings.gravity.y,
                                            settings.gravity.z,
                                            maxBodies,
                                            maxBodyPairs,
                                            maxContactConstraints,
                                            settings.deterministic ? 1 : 0)
        if handle == nil {
            return nil
        }
    }

    deinit {
        if let handle {
            MCEPhysicsDestroyWorld(handle)
        }
    }

    func applySettings(_ settings: PhysicsSettings) {
        self.settings = settings
        guard let handle else { return }
        MCEPhysicsWorldSetGravity(handle, settings.gravity.x, settings.gravity.y, settings.gravity.z)
    }

    func step(dt: Float) {
        guard let handle else { return }
        MCEPhysicsStepWorld(handle, dt, settings.solverIterations)
    }

    func createBody(desc: PhysicsBodyCreation) -> UInt64 {
        guard let handle else { return 0 }
#if DEBUG
        // Rotation quaternion ordering is (x, y, z, w) when sent over the C bridge.
#endif
        let rotation = PhysicsWorld.sanitizedQuaternion(desc.rotation)
        let rotationOffset = PhysicsWorld.sanitizedQuaternion(desc.rotationOffset)
        let bodyId = MCEPhysicsCreateBody(handle,
                                    desc.shapeType.rawValue,
                                    desc.motionType.rawValue,
                                    desc.position.x, desc.position.y, desc.position.z,
                                    rotation.x, rotation.y, rotation.z, rotation.w,
                                    desc.boxHalfExtents.x, desc.boxHalfExtents.y, desc.boxHalfExtents.z,
                                    desc.sphereRadius,
                                    desc.capsuleHalfHeight,
                                    desc.capsuleRadius,
                                    desc.offset.x, desc.offset.y, desc.offset.z,
                                    rotationOffset.x, rotationOffset.y, rotationOffset.z, rotationOffset.w,
                                    desc.friction,
                                    desc.restitution,
                                    desc.linearDamping,
                                    desc.angularDamping,
                                    desc.gravityFactor,
                                    desc.mass,
                                    desc.userData,
                                    desc.ccdEnabled ? 1 : 0,
                                    desc.isTrigger ? 1 : 0,
                                    desc.allowSleeping ? 1 : 0)
        if bodyId != 0, desc.userData != 0 {
            bodyUserData[bodyId] = desc.userData
        }
        return bodyId
    }

    func destroyBody(bodyId: UInt64) {
        guard let handle else { return }
        MCEPhysicsDestroyBody(handle, bodyId)
        bodyUserData.removeValue(forKey: bodyId)
    }

    func setBodyTransform(bodyId: UInt64, position: SIMD3<Float>, rotation: SIMD4<Float>) {
        guard let handle else { return }
#if DEBUG
        // Rotation quaternion ordering is (x, y, z, w) when sent over the C bridge.
#endif
        let sanitized = PhysicsWorld.sanitizedQuaternion(rotation)
        MCEPhysicsSetBodyTransform(handle, bodyId,
                                   position.x, position.y, position.z,
                                   sanitized.x, sanitized.y, sanitized.z, sanitized.w)
    }

    func getBodyTransform(bodyId: UInt64) -> (position: SIMD3<Float>, rotation: SIMD4<Float>)? {
        guard let handle else { return nil }
        var position = SIMD3<Float>(0, 0, 0)
        var rotation = SIMD4<Float>(0, 0, 0, 1)
        let success = withUnsafeMutableBytes(of: &position) { posBytes in
            withUnsafeMutableBytes(of: &rotation) { rotBytes in
                let posPtr = posBytes.bindMemory(to: Float.self).baseAddress
                let rotPtr = rotBytes.bindMemory(to: Float.self).baseAddress
                return MCEPhysicsGetBodyTransform(handle, bodyId, posPtr, rotPtr) != 0
            }
        }
        guard success else { return nil }
#if DEBUG
        // C bridge returns quaternion as (x, y, z, w).
#endif
        return (position, rotation)
    }

    func setBodyMotionType(bodyId: UInt64, motionType: RigidbodyMotionType) {
        guard let handle else { return }
        MCEPhysicsSetBodyMotionType(handle, bodyId, motionType.rawValue)
    }

    func lastContacts() -> [PhysicsContact] {
        guard let handle else { return [] }
        let maxContacts = UInt32(min(contactBodyIdBuffer.count, contactFloatBuffer.count / 6))
        let written = contactFloatBuffer.withUnsafeMutableBufferPointer { floatPtr in
            MCEPhysicsCopyLastContacts(handle, floatPtr.baseAddress, maxContacts)
        }
        let idCount = contactBodyIdBuffer.withUnsafeMutableBufferPointer { idPtr in
            MCEPhysicsCopyLastContactBodyIds(handle, idPtr.baseAddress, maxContacts)
        }
        let count = Int(min(written, idCount))
        guard count > 0 else {
            MCEPhysicsClearLastContacts(handle)
            return []
        }

        var contacts: [PhysicsContact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let base = index * 6
            let position = SIMD3<Float>(contactFloatBuffer[base + 0],
                                         contactFloatBuffer[base + 1],
                                         contactFloatBuffer[base + 2])
            let normal = SIMD3<Float>(contactFloatBuffer[base + 3],
                                      contactFloatBuffer[base + 4],
                                      contactFloatBuffer[base + 5])
            let bodyId = contactBodyIdBuffer[index]
            contacts.append(PhysicsContact(position: position, normal: normal, bodyId: bodyId))
        }
        MCEPhysicsClearLastContacts(handle)
        return contacts
    }

    func raycastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> PhysicsRaycastHit? {
        guard let handle else { return nil }
        var position = SIMD3<Float>(0, 0, 0)
        var normal = SIMD3<Float>(0, 1, 0)
        var distance: Float = 0.0
        var bodyId: UInt64 = 0
        var userData: UInt64 = 0
        let hit = withUnsafeMutableBytes(of: &position) { posBytes in
            withUnsafeMutableBytes(of: &normal) { normBytes in
                let posPtr = posBytes.bindMemory(to: Float.self).baseAddress
                let normPtr = normBytes.bindMemory(to: Float.self).baseAddress
                return MCEPhysicsRaycastClosest(handle,
                                                origin.x, origin.y, origin.z,
                                                direction.x, direction.y, direction.z,
                                                maxDistance,
                                                posPtr,
                                                normPtr,
                                                &distance,
                                                &bodyId,
                                                &userData) != 0
            }
        }
        guard hit else { return nil }
        let entityId = entityForUserData[userData]
        return PhysicsRaycastHit(position: position,
                                 normal: normal,
                                 distance: distance,
                                 bodyId: bodyId,
                                 entityId: entityId)
    }

    func sphereCastClosest(origin: SIMD3<Float>, direction: SIMD3<Float>, radius: Float, maxDistance: Float) -> PhysicsRaycastHit? {
        guard let handle else { return nil }
        var position = SIMD3<Float>(0, 0, 0)
        var normal = SIMD3<Float>(0, 1, 0)
        var distance: Float = 0.0
        var bodyId: UInt64 = 0
        var userData: UInt64 = 0
        let hit = withUnsafeMutableBytes(of: &position) { posBytes in
            withUnsafeMutableBytes(of: &normal) { normBytes in
                let posPtr = posBytes.bindMemory(to: Float.self).baseAddress
                let normPtr = normBytes.bindMemory(to: Float.self).baseAddress
                return MCEPhysicsSphereCastClosest(handle,
                                                   origin.x, origin.y, origin.z,
                                                   direction.x, direction.y, direction.z,
                                                   radius,
                                                   maxDistance,
                                                   posPtr,
                                                   normPtr,
                                                   &distance,
                                                   &bodyId,
                                                   &userData) != 0
            }
        }
        guard hit else { return nil }
        let entityId = entityForUserData[userData]
        return PhysicsRaycastHit(position: position,
                                 normal: normal,
                                 distance: distance,
                                 bodyId: bodyId,
                                 entityId: entityId)
    }

    func overlapEvents() -> [PhysicsOverlapEvent] {
        guard let handle else { return [] }
        let maxEvents = UInt32(overlapBodyA.count)
        let count = overlapBodyA.withUnsafeMutableBufferPointer { bodyAPtr in
            overlapBodyB.withUnsafeMutableBufferPointer { bodyBPtr in
                overlapUserDataA.withUnsafeMutableBufferPointer { userAPtr in
                    overlapUserDataB.withUnsafeMutableBufferPointer { userBPtr in
                        overlapIsBegin.withUnsafeMutableBufferPointer { beginPtr in
                            MCEPhysicsCopyOverlapEvents(handle,
                                                        bodyAPtr.baseAddress,
                                                        bodyBPtr.baseAddress,
                                                        userAPtr.baseAddress,
                                                        userBPtr.baseAddress,
                                                        beginPtr.baseAddress,
                                                        maxEvents)
                        }
                    }
                }
            }
        }
        let eventCount = Int(count)
        guard eventCount > 0 else { return [] }
        var events: [PhysicsOverlapEvent] = []
        events.reserveCapacity(eventCount)
        for index in 0..<eventCount {
            let userA = overlapUserDataA[index]
            let userB = overlapUserDataB[index]
            let entityA = entityForUserData[userA]
            let entityB = entityForUserData[userB]
            let isBegin = overlapIsBegin[index] != 0
            events.append(PhysicsOverlapEvent(bodyIdA: overlapBodyA[index],
                                             bodyIdB: overlapBodyB[index],
                                             entityIdA: entityA,
                                             entityIdB: entityB,
                                             isBegin: isBegin))
        }
        return events
    }

    func isBodySleeping(bodyId: UInt64) -> Bool {
        guard let handle else { return false }
        return MCEPhysicsIsBodySleeping(handle, bodyId) != 0
    }

    func userData(for entityId: UUID) -> UInt64 {
        if let existing = userDataForEntity[entityId] {
            return existing
        }
        let value = nextUserData
        nextUserData &+= 1
        userDataForEntity[entityId] = value
        entityForUserData[value] = entityId
        return value
    }

    func entityId(for userData: UInt64) -> UUID? {
        entityForUserData[userData]
    }

    func entityIdForBody(_ bodyId: UInt64) -> UUID? {
        guard let userData = bodyUserData[bodyId] else { return nil }
        return entityForUserData[userData]
    }

    private static func sanitizedQuaternion(_ quaternion: SIMD4<Float>) -> SIMD4<Float> {
        let length = simd_length(quaternion)
#if DEBUG
        if !length.isFinite || length < 1e-4 || length > 1000.0 {
            MC_ASSERT(false, "Physics quaternion length is invalid.")
        }
#endif
        let deviation = abs(length - 1.0)
        if deviation > 1e-3, length > 0.0 {
            return quaternion / length
        }
        return quaternion
    }
}

public struct PhysicsBodyCreation {
    public var shapeType: ColliderShapeType
    public var motionType: RigidbodyMotionType
    public var position: SIMD3<Float>
    public var rotation: SIMD4<Float>
    public var boxHalfExtents: SIMD3<Float>
    public var sphereRadius: Float
    public var capsuleHalfHeight: Float
    public var capsuleRadius: Float
    public var offset: SIMD3<Float>
    public var rotationOffset: SIMD4<Float>
    public var friction: Float
    public var restitution: Float
    public var linearDamping: Float
    public var angularDamping: Float
    public var gravityFactor: Float
    public var mass: Float
    public var userData: UInt64
    public var ccdEnabled: Bool
    public var isTrigger: Bool
    public var allowSleeping: Bool

    public init(shapeType: ColliderShapeType,
                motionType: RigidbodyMotionType,
                position: SIMD3<Float>,
                rotation: SIMD4<Float>,
                boxHalfExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5),
                sphereRadius: Float = 0.5,
                capsuleHalfHeight: Float = 0.5,
                capsuleRadius: Float = 0.5,
                offset: SIMD3<Float> = .zero,
                rotationOffset: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                friction: Float = 0.6,
                restitution: Float = 0.0,
                linearDamping: Float = 0.02,
                angularDamping: Float = 0.2,
                gravityFactor: Float = 1.0,
                mass: Float = 1.0,
                userData: UInt64 = 0,
                ccdEnabled: Bool = false,
                isTrigger: Bool = false,
                allowSleeping: Bool = true) {
        self.shapeType = shapeType
        self.motionType = motionType
        self.position = position
        self.rotation = rotation
        self.boxHalfExtents = boxHalfExtents
        self.sphereRadius = sphereRadius
        self.capsuleHalfHeight = capsuleHalfHeight
        self.capsuleRadius = capsuleRadius
        self.offset = offset
        self.rotationOffset = rotationOffset
        self.friction = friction
        self.restitution = restitution
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravityFactor = gravityFactor
        self.mass = mass
        self.userData = userData
        self.ccdEnabled = ccdEnabled
        self.isTrigger = isTrigger
        self.allowSleeping = allowSleeping
    }
}

public struct PhysicsContact {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var bodyId: UInt64

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, bodyId: UInt64) {
        self.position = position
        self.normal = normal
        self.bodyId = bodyId
    }
}

public struct PhysicsRaycastHit {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var distance: Float
    public var bodyId: UInt64
    public var entityId: UUID?

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, distance: Float, bodyId: UInt64, entityId: UUID?) {
        self.position = position
        self.normal = normal
        self.distance = distance
        self.bodyId = bodyId
        self.entityId = entityId
    }
}

public struct PhysicsOverlapEvent {
    public var bodyIdA: UInt64
    public var bodyIdB: UInt64
    public var entityIdA: UUID?
    public var entityIdB: UUID?
    public var isBegin: Bool

    public init(bodyIdA: UInt64, bodyIdB: UInt64, entityIdA: UUID?, entityIdB: UUID?, isBegin: Bool) {
        self.bodyIdA = bodyIdA
        self.bodyIdB = bodyIdB
        self.entityIdA = entityIdA
        self.entityIdB = entityIdB
        self.isBegin = isBegin
    }
}
