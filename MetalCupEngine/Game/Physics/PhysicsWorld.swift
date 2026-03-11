/// PhysicsWorld.swift
/// Defines the PhysicsWorld wrapper around Jolt.
/// Created by Kaden Cringle.

import Foundation
import simd

@_silgen_name("MCEPhysicsCreateWorld")
private func MCEPhysicsCreateWorld(_ gravityX: Float,
                                   _ gravityY: Float,
                                   _ gravityZ: Float,
                                   _ maxBodies: UInt32,
                                   _ maxBodyPairs: UInt32,
                                   _ maxContactConstraints: UInt32,
                                   _ singleThreaded: UInt32,
                                   _ collisionLayerCount: UInt32,
                                   _ collisionMatrixRows: UnsafePointer<UInt32>?) -> UnsafeMutableRawPointer?

@_silgen_name("MCEPhysicsDestroyWorld")
private func MCEPhysicsDestroyWorld(_ world: UnsafeMutableRawPointer?)

@_silgen_name("MCEPhysicsWorldSetGravity")
private func MCEPhysicsWorldSetGravity(_ world: UnsafeMutableRawPointer?, _ gravityX: Float, _ gravityY: Float, _ gravityZ: Float)

@_silgen_name("MCEPhysicsStepWorld")
private func MCEPhysicsStepWorld(_ world: UnsafeMutableRawPointer?, _ dt: Float, _ collisionSteps: UInt32)

@_silgen_name("MCEPhysicsCreateBodyMulti")
private func MCEPhysicsCreateBodyMulti(_ world: UnsafeMutableRawPointer?,
                                       _ shapeCount: UInt32,
                                       _ shapeTypes: UnsafePointer<UInt32>?,
                                       _ boxHalfExtents: UnsafePointer<Float>?,
                                       _ sphereRadii: UnsafePointer<Float>?,
                                       _ capsuleHalfHeights: UnsafePointer<Float>?,
                                       _ capsuleRadii: UnsafePointer<Float>?,
                                       _ offsets: UnsafePointer<Float>?,
                                       _ rotationOffsets: UnsafePointer<Float>?,
                                       _ motionType: UInt32,
                                       _ posX: Float, _ posY: Float, _ posZ: Float,
                                       _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                       _ friction: Float,
                                       _ restitution: Float,
                                       _ linearDamping: Float,
                                       _ angularDamping: Float,
                                       _ gravityFactor: Float,
                                       _ mass: Float,
                                       _ userData: UInt64,
                                       _ ccdEnabled: UInt32,
                                       _ isSensor: UInt32,
                                       _ allowSleeping: UInt32,
                                       _ collisionLayer: UInt32) -> UInt64

@_silgen_name("MCEPhysicsDestroyBody")
private func MCEPhysicsDestroyBody(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64)

@_silgen_name("MCEPhysicsSetBodyTransform")
private func MCEPhysicsSetBodyTransform(_ world: UnsafeMutableRawPointer?,
                                        _ bodyId: UInt64,
                                        _ posX: Float, _ posY: Float, _ posZ: Float,
                                        _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                        _ activate: UInt32)

@_silgen_name("MCEPhysicsMoveKinematic")
private func MCEPhysicsMoveKinematic(_ world: UnsafeMutableRawPointer?,
                                     _ bodyId: UInt64,
                                     _ posX: Float, _ posY: Float, _ posZ: Float,
                                     _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                     _ dt: Float)

@_silgen_name("MCEPhysicsGetBodyTransform")
private func MCEPhysicsGetBodyTransform(_ world: UnsafeMutableRawPointer?,
                                        _ bodyId: UInt64,
                                        _ positionOut: UnsafeMutablePointer<Float>?,
                                        _ rotationOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCEPhysicsSetBodyMotionType")
private func MCEPhysicsSetBodyMotionType(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64, _ motionType: UInt32)

@_silgen_name("MCEPhysicsSetBodyLinearAndAngularVelocity")
private func MCEPhysicsSetBodyLinearAndAngularVelocity(_ world: UnsafeMutableRawPointer?,
                                                       _ bodyId: UInt64,
                                                       _ linearX: Float, _ linearY: Float, _ linearZ: Float,
                                                       _ angularX: Float, _ angularY: Float, _ angularZ: Float)

@_silgen_name("MCEPhysicsGetBodyLinearAndAngularVelocity")
private func MCEPhysicsGetBodyLinearAndAngularVelocity(_ world: UnsafeMutableRawPointer?,
                                                       _ bodyId: UInt64,
                                                       _ linearOut: UnsafeMutablePointer<Float>?,
                                                       _ angularOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCEPhysicsSetBodyActivation")
private func MCEPhysicsSetBodyActivation(_ world: UnsafeMutableRawPointer?, _ bodyId: UInt64, _ activate: UInt32)

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

@_silgen_name("MCEPhysicsCapsuleCastClosest")
private func MCEPhysicsCapsuleCastClosest(_ world: UnsafeMutableRawPointer?,
                                          _ originX: Float, _ originY: Float, _ originZ: Float,
                                          _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                          _ dirX: Float, _ dirY: Float, _ dirZ: Float,
                                          _ halfHeight: Float,
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

@_silgen_name("MCECharacter_Create")
private func MCECharacter_Create(_ world: UnsafeMutableRawPointer?,
                                 _ radius: Float,
                                 _ height: Float,
                                 _ posX: Float, _ posY: Float, _ posZ: Float,
                                 _ rotX: Float, _ rotY: Float, _ rotZ: Float, _ rotW: Float,
                                 _ objectLayer: UInt32,
                                 _ ignoreBodyId: UInt64) -> UInt64

@_silgen_name("MCECharacter_Destroy")
private func MCECharacter_Destroy(_ world: UnsafeMutableRawPointer?, _ handle: UInt64)

@_silgen_name("MCECharacter_SetShapeCapsule")
private func MCECharacter_SetShapeCapsule(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ radius: Float, _ height: Float)

@_silgen_name("MCECharacter_SetMaxSlope")
private func MCECharacter_SetMaxSlope(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ radians: Float)

@_silgen_name("MCECharacter_SetStepOffset")
private func MCECharacter_SetStepOffset(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ meters: Float)

@_silgen_name("MCECharacter_SetGravity")
private func MCECharacter_SetGravity(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ value: Float)

@_silgen_name("MCECharacter_SetJumpSpeed")
private func MCECharacter_SetJumpSpeed(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ value: Float)

@_silgen_name("MCECharacter_SetPushStrength")
private func MCECharacter_SetPushStrength(_ world: UnsafeMutableRawPointer?, _ handle: UInt64, _ value: Float)

@_silgen_name("MCECharacter_SetUpVector")
private func MCECharacter_SetUpVector(_ world: UnsafeMutableRawPointer?,
                                      _ handle: UInt64,
                                      _ x: Float, _ y: Float, _ z: Float)

@_silgen_name("MCECharacter_Update")
private func MCECharacter_Update(_ world: UnsafeMutableRawPointer?,
                                 _ handle: UInt64,
                                 _ dt: Float,
                                 _ desiredVelX: Float, _ desiredVelY: Float, _ desiredVelZ: Float,
                                 _ jumpRequested: UInt32) -> UInt32

@_silgen_name("MCECharacter_UpdateDisplacement")
private func MCECharacter_UpdateDisplacement(_ world: UnsafeMutableRawPointer?,
                                             _ handle: UInt64,
                                             _ dt: Float,
                                             _ desiredDeltaX: Float, _ desiredDeltaY: Float, _ desiredDeltaZ: Float,
                                             _ jumpRequested: UInt32) -> UInt32

@_silgen_name("MCECharacter_GetPosition")
private func MCECharacter_GetPosition(_ world: UnsafeMutableRawPointer?,
                                      _ handle: UInt64,
                                      _ positionOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCECharacter_GetRotation")
private func MCECharacter_GetRotation(_ world: UnsafeMutableRawPointer?,
                                      _ handle: UInt64,
                                      _ rotationOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCECharacter_IsGrounded")
private func MCECharacter_IsGrounded(_ world: UnsafeMutableRawPointer?, _ handle: UInt64) -> UInt32

@_silgen_name("MCECharacter_GetGroundNormal")
private func MCECharacter_GetGroundNormal(_ world: UnsafeMutableRawPointer?,
                                          _ handle: UInt64,
                                          _ normalOut: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCECharacter_GetGroundVelocity")
private func MCECharacter_GetGroundVelocity(_ world: UnsafeMutableRawPointer?,
                                            _ handle: UInt64,
                                            _ velocityOut: UnsafeMutablePointer<Float>?) -> UInt32
@_silgen_name("MCECharacter_GetGroundBodyID")
private func MCECharacter_GetGroundBodyID(_ world: UnsafeMutableRawPointer?, _ handle: UInt64) -> UInt64
@_silgen_name("MCECharacter_GetContactStats")
private func MCECharacter_GetContactStats(_ world: UnsafeMutableRawPointer?,
                                          _ handle: UInt64,
                                          _ totalContactsOut: UnsafeMutablePointer<UInt32>?,
                                          _ dynamicContactsOut: UnsafeMutablePointer<UInt32>?,
                                          _ firstDynamicBodyIdOut: UnsafeMutablePointer<UInt64>?) -> UInt32

public struct PhysicsSettings {
    public static let maxCollisionLayers: Int = 16
    public static let minimumCapacity: UInt32 = 1024
    public static let maximumCapacity: UInt32 = 131_072

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
    public var defaultLinearDamping: Float
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
    public var collisionLayerNames: [String]
    public var collisionMatrix: [UInt32]
    public var maxBodies: UInt32
    public var maxBodyPairs: UInt32
    public var maxContactConstraints: UInt32

    public init(isEnabled: Bool = true,
                gravity: SIMD3<Float> = SIMD3<Float>(0.0, -9.81, 0.0),
                solverIterations: UInt32 = 1,
                qualityPreset: QualityPreset = .medium,
                fixedDeltaTime: Float = 1.0 / 60.0,
                maxSubsteps: Int = 4,
                defaultFriction: Float = 0.6,
                defaultRestitution: Float = 0.0,
                defaultLinearDamping: Float = 0.02,
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
                showOverlaps: Bool = false,
                collisionLayerNames: [String] = PhysicsSettings.defaultCollisionLayerNames(),
                collisionMatrix: [UInt32] = PhysicsSettings.defaultCollisionMatrix(),
                maxBodies: UInt32 = 8_192,
                maxBodyPairs: UInt32 = 16_384,
                maxContactConstraints: UInt32 = 8_192) {
        self.isEnabled = isEnabled
        self.gravity = gravity
        self.qualityPreset = qualityPreset
        let resolvedSolver = max(1, solverIterations)
        self.solverIterations = max(resolvedSolver, qualityPreset.solverIterations)
        self.fixedDeltaTime = max(0.0001, fixedDeltaTime)
        self.maxSubsteps = max(1, min(maxSubsteps, 16))
        self.defaultFriction = min(max(defaultFriction, 0.0), 1.0)
        self.defaultRestitution = min(max(defaultRestitution, 0.0), 1.0)
        self.defaultLinearDamping = max(0.0, defaultLinearDamping)
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
        self.collisionLayerNames = PhysicsSettings.normalizedCollisionLayerNames(collisionLayerNames)
        self.collisionMatrix = PhysicsSettings.normalizedCollisionMatrix(collisionMatrix)
        self.maxBodies = PhysicsSettings.clampCapacity(maxBodies)
        self.maxBodyPairs = PhysicsSettings.clampCapacity(maxBodyPairs)
        self.maxContactConstraints = PhysicsSettings.clampCapacity(maxContactConstraints)
    }

    public static func defaultCollisionLayerNames() -> [String] {
        var names: [String] = ["Default"]
        for index in 1..<maxCollisionLayers {
            names.append("Layer \(index)")
        }
        return names
    }

    public static func defaultCollisionMatrix() -> [UInt32] {
        let fullMask = fullCollisionMask()
        return Array(repeating: fullMask, count: maxCollisionLayers)
    }

    public static func fullCollisionMask() -> UInt32 {
        if maxCollisionLayers >= 32 {
            return UInt32.max
        }
        return (1 << UInt32(maxCollisionLayers)) - 1
    }

    public static func normalizedCollisionLayerNames(_ names: [String]) -> [String] {
        var result: [String] = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if result.count > maxCollisionLayers {
            result = Array(result.prefix(maxCollisionLayers))
        }
        if result.isEmpty {
            result = defaultCollisionLayerNames()
        }
        while result.count < maxCollisionLayers {
            result.append("Layer \(result.count)")
        }
        if result[0].isEmpty {
            result[0] = "Default"
        }
        return result
    }

    public static func normalizedCollisionMatrix(_ matrix: [UInt32]) -> [UInt32] {
        let fullMask = fullCollisionMask()
        var result = matrix
        if result.count > maxCollisionLayers {
            result = Array(result.prefix(maxCollisionLayers))
        }
        if result.isEmpty {
            result = defaultCollisionMatrix()
        }
        while result.count < maxCollisionLayers {
            result.append(fullMask)
        }
        return result.map { $0 & fullMask }
    }

    public static func clampCapacity(_ value: UInt32) -> UInt32 {
        min(max(value, minimumCapacity), maximumCapacity)
    }

    public func runtimeHash() -> Int {
        var hasher = Hasher()
        hasher.combine(isEnabled)
        hasher.combine(gravity.x.bitPattern)
        hasher.combine(gravity.y.bitPattern)
        hasher.combine(gravity.z.bitPattern)
        hasher.combine(solverIterations)
        hasher.combine(qualityPreset.rawValue)
        hasher.combine(fixedDeltaTime.bitPattern)
        hasher.combine(maxSubsteps)
        hasher.combine(defaultFriction.bitPattern)
        hasher.combine(defaultRestitution.bitPattern)
        hasher.combine(defaultLinearDamping.bitPattern)
        hasher.combine(defaultAngularDamping.bitPattern)
        hasher.combine(ccdEnabled)
        hasher.combine(resolveInitialOverlap)
        hasher.combine(deterministic)
        hasher.combine(debugDrawEnabled)
        hasher.combine(debugDrawInPlay)
        hasher.combine(showColliders)
        hasher.combine(showCOMAxes)
        hasher.combine(showContacts)
        hasher.combine(showSleeping)
        hasher.combine(showOverlaps)
        hasher.combine(maxBodies)
        hasher.combine(maxBodyPairs)
        hasher.combine(maxContactConstraints)
        for name in collisionLayerNames {
            hasher.combine(name)
        }
        for row in collisionMatrix {
            hasher.combine(row)
        }
        return hasher.finalize()
    }
}

public struct PhysicsCharacterCreation {
    public var radius: Float
    public var height: Float
    public var position: SIMD3<Float>
    public var rotation: SIMD4<Float>
    public var collisionLayer: Int32
    public var ignoreBodyId: UInt64

    public init(radius: Float,
                height: Float,
                position: SIMD3<Float>,
                rotation: SIMD4<Float>,
                collisionLayer: Int32 = 0,
                ignoreBodyId: UInt64 = 0) {
        self.radius = radius
        self.height = height
        self.position = position
        self.rotation = rotation
        self.collisionLayer = collisionLayer
        self.ignoreBodyId = ignoreBodyId
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
    private var bodyCollisionLayer: [UInt64: Int32] = [:]
    private var bodyIsTrigger: [UInt64: Bool] = [:]

    public init?(settings: PhysicsSettings) {
        self.settings = settings
        self.handle = PhysicsWorld.createWorldHandle(settings: settings)
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

    func recreate(settings: PhysicsSettings) -> Bool {
        let newHandle = PhysicsWorld.createWorldHandle(settings: settings)
        guard let newHandle else { return false }
        if let handle {
            MCEPhysicsDestroyWorld(handle)
        }
        handle = newHandle
        self.settings = settings
        bodyUserData.removeAll(keepingCapacity: true)
        bodyCollisionLayer.removeAll(keepingCapacity: true)
        bodyIsTrigger.removeAll(keepingCapacity: true)
        return true
    }

    func step(dt: Float) {
        guard let handle else { return }
        MCEPhysicsStepWorld(handle, dt, settings.solverIterations)
    }

    func createBody(desc: PhysicsBodyCreation) -> UInt64 {
        guard let handle else { return 0 }
        guard !desc.shapes.isEmpty else { return 0 }
#if DEBUG
        // Rotation quaternion ordering is (x, y, z, w) when sent over the C bridge.
#endif
        let rotation = PhysicsWorld.sanitizedQuaternion(desc.rotation)
        let shapeCount = desc.shapes.count
        var shapeTypes: [UInt32] = Array(repeating: 0, count: shapeCount)
        var boxHalfExtents: [Float] = Array(repeating: 0, count: shapeCount * 3)
        var sphereRadii: [Float] = Array(repeating: 0, count: shapeCount)
        var capsuleHalfHeights: [Float] = Array(repeating: 0, count: shapeCount)
        var capsuleRadii: [Float] = Array(repeating: 0, count: shapeCount)
        var offsets: [Float] = Array(repeating: 0, count: shapeCount * 3)
        var rotationOffsets: [Float] = Array(repeating: 0, count: shapeCount * 4)
        for index in 0..<shapeCount {
            let shape = desc.shapes[index]
            shapeTypes[index] = shape.shapeType.rawValue
            boxHalfExtents[index * 3 + 0] = shape.boxHalfExtents.x
            boxHalfExtents[index * 3 + 1] = shape.boxHalfExtents.y
            boxHalfExtents[index * 3 + 2] = shape.boxHalfExtents.z
            sphereRadii[index] = shape.sphereRadius
            capsuleHalfHeights[index] = shape.capsuleHalfHeight
            capsuleRadii[index] = shape.capsuleRadius
            offsets[index * 3 + 0] = shape.offset.x
            offsets[index * 3 + 1] = shape.offset.y
            offsets[index * 3 + 2] = shape.offset.z
            let quat = PhysicsWorld.sanitizedQuaternion(shape.rotationOffset)
            rotationOffsets[index * 4 + 0] = quat.x
            rotationOffsets[index * 4 + 1] = quat.y
            rotationOffsets[index * 4 + 2] = quat.z
            rotationOffsets[index * 4 + 3] = quat.w
        }

        let bodyId = shapeTypes.withUnsafeBufferPointer { shapeTypesPtr in
            boxHalfExtents.withUnsafeBufferPointer { boxHalfExtentsPtr in
                sphereRadii.withUnsafeBufferPointer { sphereRadiiPtr in
                    capsuleHalfHeights.withUnsafeBufferPointer { capsuleHalfHeightsPtr in
                        capsuleRadii.withUnsafeBufferPointer { capsuleRadiiPtr in
                            offsets.withUnsafeBufferPointer { offsetsPtr in
                                rotationOffsets.withUnsafeBufferPointer { rotationOffsetsPtr in
                                    MCEPhysicsCreateBodyMulti(handle,
                                                              UInt32(shapeCount),
                                                              shapeTypesPtr.baseAddress,
                                                              boxHalfExtentsPtr.baseAddress,
                                                              sphereRadiiPtr.baseAddress,
                                                              capsuleHalfHeightsPtr.baseAddress,
                                                              capsuleRadiiPtr.baseAddress,
                                                              offsetsPtr.baseAddress,
                                                              rotationOffsetsPtr.baseAddress,
                                                              desc.motionType.rawValue,
                                                              desc.position.x, desc.position.y, desc.position.z,
                                                              rotation.x, rotation.y, rotation.z, rotation.w,
                                                              desc.friction,
                                                              desc.restitution,
                                                              desc.linearDamping,
                                                              desc.angularDamping,
                                                              desc.gravityFactor,
                                                              desc.mass,
                                                              desc.userData,
                                                              desc.ccdEnabled ? 1 : 0,
                                                              desc.isTrigger ? 1 : 0,
                                                              desc.allowSleeping ? 1 : 0,
                                                              UInt32(max(0, min(Int(desc.collisionLayer), PhysicsSettings.maxCollisionLayers - 1))))
                                }
                            }
                        }
                    }
                }
            }
        }
        if bodyId != 0, desc.userData != 0 {
            bodyUserData[bodyId] = desc.userData
        }
        if bodyId != 0 {
            bodyCollisionLayer[bodyId] = desc.collisionLayer
            bodyIsTrigger[bodyId] = desc.isTrigger
        }
        return bodyId
    }

    func destroyBody(bodyId: UInt64) {
        guard let handle else { return }
        MCEPhysicsDestroyBody(handle, bodyId)
        bodyUserData.removeValue(forKey: bodyId)
        bodyCollisionLayer.removeValue(forKey: bodyId)
        bodyIsTrigger.removeValue(forKey: bodyId)
    }

    func setBodyTransform(bodyId: UInt64, position: SIMD3<Float>, rotation: SIMD4<Float>, activate: Bool = true) {
        guard let handle else { return }
#if DEBUG
        // Rotation quaternion ordering is (x, y, z, w) when sent over the C bridge.
#endif
        let sanitized = PhysicsWorld.sanitizedQuaternion(rotation)
        MCEPhysicsSetBodyTransform(handle, bodyId,
                                   position.x, position.y, position.z,
                                   sanitized.x, sanitized.y, sanitized.z, sanitized.w,
                                   activate ? 1 : 0)
    }

    func moveKinematic(bodyId: UInt64, position: SIMD3<Float>, rotation: SIMD4<Float>, dt: Float) {
        guard let handle, dt > 0.0 else { return }
#if DEBUG
        // Rotation quaternion ordering is (x, y, z, w) when sent over the C bridge.
#endif
        let sanitized = PhysicsWorld.sanitizedQuaternion(rotation)
        MCEPhysicsMoveKinematic(handle,
                                bodyId,
                                position.x, position.y, position.z,
                                sanitized.x, sanitized.y, sanitized.z, sanitized.w,
                                dt)
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

    func setBodyVelocity(bodyId: UInt64, linear: SIMD3<Float>, angular: SIMD3<Float>) {
        guard let handle else { return }
        MCEPhysicsSetBodyLinearAndAngularVelocity(handle, bodyId, linear.x, linear.y, linear.z, angular.x, angular.y, angular.z)
    }

    func getBodyVelocity(bodyId: UInt64) -> (linear: SIMD3<Float>, angular: SIMD3<Float>)? {
        guard let handle else { return nil }
        var linear = SIMD3<Float>(0, 0, 0)
        var angular = SIMD3<Float>(0, 0, 0)
        let success = withUnsafeMutableBytes(of: &linear) { linearBytes in
            withUnsafeMutableBytes(of: &angular) { angularBytes in
                let linearPtr = linearBytes.bindMemory(to: Float.self).baseAddress
                let angularPtr = angularBytes.bindMemory(to: Float.self).baseAddress
                return MCEPhysicsGetBodyLinearAndAngularVelocity(handle, bodyId, linearPtr, angularPtr) != 0
            }
        }
        guard success else { return nil }
        return (linear, angular)
    }

    func setBodyActive(bodyId: UInt64, isActive: Bool) {
        guard let handle else { return }
        MCEPhysicsSetBodyActivation(handle, bodyId, isActive ? 1 : 0)
    }

    func createCharacter(desc: PhysicsCharacterCreation) -> UInt64 {
        guard let handle else { return 0 }
        let rotation = PhysicsWorld.sanitizedQuaternion(desc.rotation)
        let layer = UInt32(max(0, min(Int(desc.collisionLayer), PhysicsSettings.maxCollisionLayers - 1)))
        return MCECharacter_Create(handle,
                                   max(0.02, desc.radius),
                                   max(0.1, desc.height),
                                   desc.position.x, desc.position.y, desc.position.z,
                                   rotation.x, rotation.y, rotation.z, rotation.w,
                                   layer,
                                   desc.ignoreBodyId)
    }

    func destroyCharacter(handle characterHandle: UInt64) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_Destroy(handle, characterHandle)
    }

    func setCharacterShapeCapsule(handle characterHandle: UInt64, radius: Float, height: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetShapeCapsule(handle, characterHandle, max(0.02, radius), max(0.1, height))
    }

    func setCharacterMaxSlope(handle characterHandle: UInt64, radians: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetMaxSlope(handle, characterHandle, radians)
    }

    func setCharacterStepOffset(handle characterHandle: UInt64, meters: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetStepOffset(handle, characterHandle, max(0.0, meters))
    }

    func setCharacterGravity(handle characterHandle: UInt64, value: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetGravity(handle, characterHandle, value)
    }

    func setCharacterJumpSpeed(handle characterHandle: UInt64, value: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetJumpSpeed(handle, characterHandle, max(0.0, value))
    }

    func setCharacterPushStrength(handle characterHandle: UInt64, value: Float) {
        guard let handle, characterHandle != 0 else { return }
        MCECharacter_SetPushStrength(handle, characterHandle, max(0.0, value))
    }

    func setCharacterUpVector(handle characterHandle: UInt64, up: SIMD3<Float>) {
        guard let handle, characterHandle != 0 else { return }
        let length = simd_length(up)
        let normalized = length > 1.0e-5 ? (up / length) : SIMD3<Float>(0.0, 1.0, 0.0)
        MCECharacter_SetUpVector(handle, characterHandle, normalized.x, normalized.y, normalized.z)
    }

    @discardableResult
    func updateCharacter(handle characterHandle: UInt64,
                         dt: Float,
                         desiredVelocity: SIMD3<Float>,
                         jumpRequested: Bool) -> Bool {
        guard let handle, characterHandle != 0, dt > 0.0 else { return false }
        return MCECharacter_Update(handle,
                                   characterHandle,
                                   dt,
                                   desiredVelocity.x, desiredVelocity.y, desiredVelocity.z,
                                   jumpRequested ? 1 : 0) != 0
    }

    @discardableResult
    func updateCharacterDisplacement(handle characterHandle: UInt64,
                                     dt: Float,
                                     desiredDisplacement: SIMD3<Float>,
                                     jumpRequested: Bool) -> Bool {
        guard let handle, characterHandle != 0, dt > 0.0 else { return false }
        return MCECharacter_UpdateDisplacement(handle,
                                               characterHandle,
                                               dt,
                                               desiredDisplacement.x, desiredDisplacement.y, desiredDisplacement.z,
                                               jumpRequested ? 1 : 0) != 0
    }

    func characterPosition(handle characterHandle: UInt64) -> SIMD3<Float>? {
        guard let handle, characterHandle != 0 else { return nil }
        var position = SIMD3<Float>(0, 0, 0)
        let success = withUnsafeMutableBytes(of: &position) { bytes in
            let ptr = bytes.bindMemory(to: Float.self).baseAddress
            return MCECharacter_GetPosition(handle, characterHandle, ptr) != 0
        }
        return success ? position : nil
    }

    func characterRotation(handle characterHandle: UInt64) -> SIMD4<Float>? {
        guard let handle, characterHandle != 0 else { return nil }
        var rotation = SIMD4<Float>(0, 0, 0, 1)
        let success = withUnsafeMutableBytes(of: &rotation) { bytes in
            let ptr = bytes.bindMemory(to: Float.self).baseAddress
            return MCECharacter_GetRotation(handle, characterHandle, ptr) != 0
        }
        return success ? TransformMath.normalizedQuaternion(rotation) : nil
    }

    func characterIsGrounded(handle characterHandle: UInt64) -> Bool {
        guard let handle, characterHandle != 0 else { return false }
        return MCECharacter_IsGrounded(handle, characterHandle) != 0
    }

    func characterGroundNormal(handle characterHandle: UInt64) -> SIMD3<Float> {
        guard let handle, characterHandle != 0 else { return SIMD3<Float>(0.0, 1.0, 0.0) }
        var normal = SIMD3<Float>(0.0, 1.0, 0.0)
        let success = withUnsafeMutableBytes(of: &normal) { bytes in
            let ptr = bytes.bindMemory(to: Float.self).baseAddress
            return MCECharacter_GetGroundNormal(handle, characterHandle, ptr) != 0
        }
        if !success { return SIMD3<Float>(0.0, 1.0, 0.0) }
        let len = simd_length(normal)
        if len > 1.0e-5 {
            return normal / len
        }
        return SIMD3<Float>(0.0, 1.0, 0.0)
    }

    func characterGroundVelocity(handle characterHandle: UInt64) -> SIMD3<Float> {
        guard let handle, characterHandle != 0 else { return .zero }
        var velocity = SIMD3<Float>.zero
        _ = withUnsafeMutableBytes(of: &velocity) { bytes in
            let ptr = bytes.bindMemory(to: Float.self).baseAddress
            MCECharacter_GetGroundVelocity(handle, characterHandle, ptr) != 0
        }
        return velocity
    }

    func characterGroundBodyId(handle characterHandle: UInt64) -> UInt64 {
        guard let handle, characterHandle != 0 else { return 0 }
        return MCECharacter_GetGroundBodyID(handle, characterHandle)
    }

    func characterContactStats(handle characterHandle: UInt64) -> (total: UInt32, dynamic: UInt32, firstDynamicBodyId: UInt64) {
        guard let handle, characterHandle != 0 else { return (0, 0, 0) }
        var total: UInt32 = 0
        var dynamic: UInt32 = 0
        var firstDynamicBodyId: UInt64 = 0
        _ = MCECharacter_GetContactStats(handle, characterHandle, &total, &dynamic, &firstDynamicBodyId)
        return (total, dynamic, firstDynamicBodyId)
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

    func raycast(origin: SIMD3<Float>,
                 direction: SIMD3<Float>,
                 maxDistance: Float,
                 layerMask: LayerMask,
                 includeTriggers: Bool) -> PhysicsRaycastHit? {
        let directionLength = simd_length(direction)
        guard directionLength > 1e-6 else { return nil }
        let normalizedDirection = direction / directionLength
        let requestedDistance = max(0.0, maxDistance)
        guard requestedDistance > 0 else { return nil }

        var currentOrigin = origin
        var traveledDistance: Float = 0.0
        var remainingDistance = requestedDistance
        let maxIterations = 64
        let epsilonStep: Float = 0.002

        for _ in 0..<maxIterations {
            guard let candidate = raycastClosest(origin: currentOrigin,
                                                 direction: normalizedDirection,
                                                 maxDistance: remainingDistance) else {
                return nil
            }

            let layer = collisionLayerForBody(candidate.bodyId)
            let layerPasses = layerMask.contains(layerIndex: layer)
            let triggerPasses = includeTriggers || !isTriggerBody(candidate.bodyId)
            let absoluteDistance = traveledDistance + candidate.distance

            if layerPasses && triggerPasses {
                var accepted = candidate
                accepted.distance = absoluteDistance
                return accepted
            }

            let advance = max(candidate.distance + epsilonStep, epsilonStep)
            traveledDistance += advance
            if traveledDistance >= requestedDistance {
                return nil
            }
            remainingDistance = requestedDistance - traveledDistance
            currentOrigin = origin + normalizedDirection * traveledDistance
        }
        return nil
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

    func capsuleCastClosest(origin: SIMD3<Float>,
                            rotation: SIMD4<Float>,
                            direction: SIMD3<Float>,
                            halfHeight: Float,
                            radius: Float,
                            maxDistance: Float) -> PhysicsRaycastHit? {
        guard let handle else { return nil }
        var position = SIMD3<Float>(0, 0, 0)
        var normal = SIMD3<Float>(0, 1, 0)
        var distance: Float = 0.0
        var bodyId: UInt64 = 0
        var userData: UInt64 = 0
        let sanitizedRotation = PhysicsWorld.sanitizedQuaternion(rotation)
        let hit = withUnsafeMutableBytes(of: &position) { posBytes in
            withUnsafeMutableBytes(of: &normal) { normBytes in
                let posPtr = posBytes.bindMemory(to: Float.self).baseAddress
                let normPtr = normBytes.bindMemory(to: Float.self).baseAddress
                return MCEPhysicsCapsuleCastClosest(handle,
                                                    origin.x, origin.y, origin.z,
                                                    sanitizedRotation.x, sanitizedRotation.y, sanitizedRotation.z, sanitizedRotation.w,
                                                    direction.x, direction.y, direction.z,
                                                    halfHeight,
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

    func collisionLayerForBody(_ bodyId: UInt64) -> Int32 {
        bodyCollisionLayer[bodyId] ?? 0
    }

    func isTriggerBody(_ bodyId: UInt64) -> Bool {
        bodyIsTrigger[bodyId] ?? false
    }

    private static func createWorldHandle(settings: PhysicsSettings) -> UnsafeMutableRawPointer? {
        let normalized = PhysicsSettings(
            isEnabled: settings.isEnabled,
            gravity: settings.gravity,
            solverIterations: settings.solverIterations,
            qualityPreset: settings.qualityPreset,
            fixedDeltaTime: settings.fixedDeltaTime,
            maxSubsteps: settings.maxSubsteps,
            defaultFriction: settings.defaultFriction,
            defaultRestitution: settings.defaultRestitution,
            defaultLinearDamping: settings.defaultLinearDamping,
            defaultAngularDamping: settings.defaultAngularDamping,
            ccdEnabled: settings.ccdEnabled,
            resolveInitialOverlap: settings.resolveInitialOverlap,
            deterministic: settings.deterministic,
            debugDrawEnabled: settings.debugDrawEnabled,
            debugDrawInPlay: settings.debugDrawInPlay,
            showColliders: settings.showColliders,
            showCOMAxes: settings.showCOMAxes,
            showContacts: settings.showContacts,
            showSleeping: settings.showSleeping,
            showOverlaps: settings.showOverlaps,
            collisionLayerNames: settings.collisionLayerNames,
            collisionMatrix: settings.collisionMatrix,
            maxBodies: settings.maxBodies,
            maxBodyPairs: settings.maxBodyPairs,
            maxContactConstraints: settings.maxContactConstraints
        )
        var matrix = normalized.collisionMatrix
        return matrix.withUnsafeBufferPointer { matrixPtr in
            MCEPhysicsCreateWorld(normalized.gravity.x,
                                  normalized.gravity.y,
                                  normalized.gravity.z,
                                  normalized.maxBodies,
                                  normalized.maxBodyPairs,
                                  normalized.maxContactConstraints,
                                  normalized.deterministic ? 1 : 0,
                                  UInt32(PhysicsSettings.maxCollisionLayers),
                                  matrixPtr.baseAddress)
        }
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

public struct PhysicsShapeCreation {
    public var shapeType: ColliderShapeType
    public var boxHalfExtents: SIMD3<Float>
    public var sphereRadius: Float
    public var capsuleHalfHeight: Float
    public var capsuleRadius: Float
    public var offset: SIMD3<Float>
    public var rotationOffset: SIMD4<Float>
    public var collisionLayerOverride: Int32?
    public var physicsMaterial: AssetHandle?

    public init(shapeType: ColliderShapeType,
                boxHalfExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5),
                sphereRadius: Float = 0.5,
                capsuleHalfHeight: Float = 0.5,
                capsuleRadius: Float = 0.5,
                offset: SIMD3<Float> = .zero,
                rotationOffset: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                collisionLayerOverride: Int32? = nil,
                physicsMaterial: AssetHandle? = nil) {
        self.shapeType = shapeType
        self.boxHalfExtents = boxHalfExtents
        self.sphereRadius = sphereRadius
        self.capsuleHalfHeight = capsuleHalfHeight
        self.capsuleRadius = capsuleRadius
        self.offset = offset
        self.rotationOffset = rotationOffset
        self.collisionLayerOverride = collisionLayerOverride
        self.physicsMaterial = physicsMaterial
    }
}

public struct PhysicsBodyCreation {
    public var motionType: RigidbodyMotionType
    public var position: SIMD3<Float>
    public var rotation: SIMD4<Float>
    public var shapes: [PhysicsShapeCreation]
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
    public var collisionLayer: Int32

    public init(motionType: RigidbodyMotionType,
                position: SIMD3<Float>,
                rotation: SIMD4<Float>,
                shapes: [PhysicsShapeCreation],
                friction: Float = 0.6,
                restitution: Float = 0.0,
                linearDamping: Float = 0.02,
                angularDamping: Float = 0.2,
                gravityFactor: Float = 1.0,
                mass: Float = 1.0,
                userData: UInt64 = 0,
                ccdEnabled: Bool = false,
                isTrigger: Bool = false,
                allowSleeping: Bool = true,
                collisionLayer: Int32 = 0) {
        self.motionType = motionType
        self.position = position
        self.rotation = rotation
        self.shapes = shapes
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
        self.collisionLayer = collisionLayer
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
    public var shapeIndex: Int32?
    public var subShapeId: UInt32?

    public init(position: SIMD3<Float>,
                normal: SIMD3<Float>,
                distance: Float,
                bodyId: UInt64,
                entityId: UUID?,
                shapeIndex: Int32? = nil,
                subShapeId: UInt32? = nil) {
        self.position = position
        self.normal = normal
        self.distance = distance
        self.bodyId = bodyId
        self.entityId = entityId
        self.shapeIndex = shapeIndex
        self.subShapeId = subShapeId
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
