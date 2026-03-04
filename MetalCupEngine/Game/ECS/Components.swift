/// Components.swift
/// Defines the Components types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct NameComponent {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct TransformComponent {
    public var position: SIMD3<Float>
    public var scale: SIMD3<Float>
    private var rotationStorage: SIMD4<Float>

    public var rotation: SIMD4<Float> {
        get { rotationStorage }
        set { rotationStorage = TransformMath.normalizedQuaternion(newValue) }
    }

    public init(
        position: SIMD3<Float> = .zero,
        rotation: SIMD4<Float> = TransformMath.identityQuaternion,
        scale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    ) {
        self.position = position
        self.scale = scale
        self.rotationStorage = TransformMath.normalizedQuaternion(rotation)
    }
}

public struct ParentComponent {
    public var parent: UUID

    public init(parent: UUID) {
        self.parent = parent
    }
}

public struct ChildrenComponent {
    public var children: [UUID]

    public init(children: [UUID] = []) {
        self.children = children
    }
}

public enum RigidbodyMotionType: UInt32, Codable {
    case staticBody = 0
    case dynamic = 1
    case kinematic = 2
}

public enum ColliderShapeType: UInt32, Codable {
    case box = 0
    case sphere = 1
    case capsule = 2
}

public struct ColliderShape: Codable {
    public var isEnabled: Bool
    public var shapeType: ColliderShapeType
    public var boxHalfExtents: SIMD3<Float>
    public var sphereRadius: Float
    public var capsuleHalfHeight: Float
    public var capsuleRadius: Float
    public var offset: SIMD3<Float>
    public var rotationOffset: SIMD3<Float>
    public var isTrigger: Bool
    public var collisionLayerOverride: Int32?
    public var physicsMaterial: AssetHandle?

    public init(isEnabled: Bool = true,
                shapeType: ColliderShapeType = .box,
                boxHalfExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5),
                sphereRadius: Float = 0.5,
                capsuleHalfHeight: Float = 0.5,
                capsuleRadius: Float = 0.5,
                offset: SIMD3<Float> = .zero,
                rotationOffset: SIMD3<Float> = .zero,
                isTrigger: Bool = false,
                collisionLayerOverride: Int32? = nil,
                physicsMaterial: AssetHandle? = nil) {
        self.isEnabled = isEnabled
        self.shapeType = shapeType
        self.boxHalfExtents = boxHalfExtents
        self.sphereRadius = sphereRadius
        self.capsuleHalfHeight = capsuleHalfHeight
        self.capsuleRadius = capsuleRadius
        self.offset = offset
        self.rotationOffset = rotationOffset
        self.isTrigger = isTrigger
        self.collisionLayerOverride = collisionLayerOverride
        self.physicsMaterial = physicsMaterial
    }
}

public struct RigidbodyComponent {
    public var isEnabled: Bool
    public var motionType: RigidbodyMotionType
    public var mass: Float
    public var friction: Float
    public var restitution: Float
    public var linearDamping: Float
    public var angularDamping: Float
    public var gravityFactor: Float
    public var allowSleeping: Bool
    public var ccdEnabled: Bool
    public var collisionLayer: Int32
    public var bodyId: UInt64?

    public init(isEnabled: Bool = true,
                motionType: RigidbodyMotionType = .dynamic,
                mass: Float = 1.0,
                friction: Float = 0.6,
                restitution: Float = 0.0,
                linearDamping: Float = 0.02,
                angularDamping: Float = 0.2,
                gravityFactor: Float = 1.0,
                allowSleeping: Bool = true,
                ccdEnabled: Bool = false,
                collisionLayer: Int32 = 0,
                bodyId: UInt64? = nil) {
        self.isEnabled = isEnabled
        self.motionType = motionType
        self.mass = mass
        self.friction = friction
        self.restitution = restitution
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravityFactor = gravityFactor
        self.allowSleeping = allowSleeping
        self.ccdEnabled = ccdEnabled
        self.collisionLayer = collisionLayer
        self.bodyId = bodyId
    }
}

public struct ColliderComponent {
    public var isEnabled: Bool
    public var shapeType: ColliderShapeType
    public var boxHalfExtents: SIMD3<Float>
    public var sphereRadius: Float
    public var capsuleHalfHeight: Float
    public var capsuleRadius: Float
    public var offset: SIMD3<Float>
    public var rotationOffset: SIMD3<Float>
    public var isTrigger: Bool
    public var collisionLayerOverride: Int32?
    public var physicsMaterial: AssetHandle?
    public var additionalShapes: [ColliderShape]

    public init(isEnabled: Bool = true,
                shapeType: ColliderShapeType = .box,
                boxHalfExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5),
                sphereRadius: Float = 0.5,
                capsuleHalfHeight: Float = 0.5,
                capsuleRadius: Float = 0.5,
                offset: SIMD3<Float> = .zero,
                rotationOffset: SIMD3<Float> = .zero,
                isTrigger: Bool = false,
                collisionLayerOverride: Int32? = nil,
                physicsMaterial: AssetHandle? = nil,
                additionalShapes: [ColliderShape] = []) {
        self.isEnabled = isEnabled
        self.shapeType = shapeType
        self.boxHalfExtents = boxHalfExtents
        self.sphereRadius = sphereRadius
        self.capsuleHalfHeight = capsuleHalfHeight
        self.capsuleRadius = capsuleRadius
        self.offset = offset
        self.rotationOffset = rotationOffset
        self.isTrigger = isTrigger
        self.collisionLayerOverride = collisionLayerOverride
        self.physicsMaterial = physicsMaterial
        self.additionalShapes = additionalShapes
    }

    public func primaryShape() -> ColliderShape {
        ColliderShape(
            isEnabled: isEnabled,
            shapeType: shapeType,
            boxHalfExtents: boxHalfExtents,
            sphereRadius: sphereRadius,
            capsuleHalfHeight: capsuleHalfHeight,
            capsuleRadius: capsuleRadius,
            offset: offset,
            rotationOffset: rotationOffset,
            isTrigger: isTrigger,
            collisionLayerOverride: collisionLayerOverride,
            physicsMaterial: physicsMaterial
        )
    }

    public func allShapes() -> [ColliderShape] {
        var shapes: [ColliderShape] = [primaryShape()]
        shapes.append(contentsOf: additionalShapes)
        return shapes
    }

    public mutating func setShapes(_ shapes: [ColliderShape]) {
        let resolved = shapes.isEmpty ? [ColliderShape()] : shapes
        let primary = resolved[0]
        isEnabled = primary.isEnabled
        shapeType = primary.shapeType
        boxHalfExtents = primary.boxHalfExtents
        sphereRadius = primary.sphereRadius
        capsuleHalfHeight = primary.capsuleHalfHeight
        capsuleRadius = primary.capsuleRadius
        offset = primary.offset
        rotationOffset = primary.rotationOffset
        isTrigger = primary.isTrigger
        collisionLayerOverride = primary.collisionLayerOverride
        physicsMaterial = primary.physicsMaterial
        additionalShapes = Array(resolved.dropFirst())
    }
}

public struct LayerComponent {
    public var index: Int32

    public init(index: Int32 = LayerCatalog.defaultLayerIndex) {
        self.index = index
    }
}

public struct ScriptComponent {
    public enum RuntimeState: UInt32 {
        case unloaded = 0
        case loaded = 1
        case error = 2
        case disabled = 3
    }

    public var enabled: Bool
    public var scriptAssetHandle: AssetHandle?
    public var typeName: String
    public var fieldData: Data
    public var fieldDataVersion: UInt32
    public var serializedFields: [String: ScriptFieldValue]
    public var fieldMetadata: [String: ScriptFieldMetadata]
    public var runtimeState: RuntimeState
    public var instanceHandle: UInt64
    public var hasInstance: Bool
    public var lastError: String

    public init(enabled: Bool = true,
                scriptAssetHandle: AssetHandle? = nil,
                typeName: String = "",
                fieldData: Data = Data(),
                fieldDataVersion: UInt32 = 1,
                serializedFields: [String: ScriptFieldValue] = [:],
                fieldMetadata: [String: ScriptFieldMetadata] = [:],
                runtimeState: RuntimeState = .unloaded,
                instanceHandle: UInt64 = 0,
                hasInstance: Bool = false,
                lastError: String = "") {
        self.enabled = enabled
        self.scriptAssetHandle = scriptAssetHandle
        self.typeName = typeName
        self.fieldData = fieldData
        self.fieldDataVersion = fieldDataVersion
        self.serializedFields = serializedFields
        self.fieldMetadata = fieldMetadata
        self.runtimeState = runtimeState
        self.instanceHandle = instanceHandle
        self.hasInstance = hasInstance
        self.lastError = lastError
    }
}

public enum ScriptFieldType: String, Codable, CaseIterable {
    case bool
    case int
    case float
    case vec2
    case vec3
    case color3
    case string
    case entity
    case prefab

    // Backward-compat aliases used by older serialized data.
    case number
    case boolean
}

public struct ScriptFieldMetadata: Equatable {
    public var name: String
    public var type: ScriptFieldType
    public var defaultValue: ScriptFieldValue
    public var minValue: Float?
    public var maxValue: Float?
    public var step: Float?
    public var tooltip: String

    public init(name: String,
                type: ScriptFieldType,
                defaultValue: ScriptFieldValue,
                minValue: Float? = nil,
                maxValue: Float? = nil,
                step: Float? = nil,
                tooltip: String = "") {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.tooltip = tooltip
    }
}

public enum ScriptFieldValue: Equatable {
    case bool(Bool)
    case int(Int32)
    case float(Float)
    case vec2(SIMD2<Float>)
    case vec3(SIMD3<Float>)
    case color3(SIMD3<Float>)
    case string(String)
    case entity(UUID?)
    case prefab(AssetHandle?)
}

extension ScriptFieldValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case bool
        case int
        case float
        case number
        case boolean
        case string
        case vec2
        case vec3
        case color3
        case entity
        case prefab
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScriptFieldType.self, forKey: .type)
        switch type {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        case .int:
            self = .int(try container.decode(Int32.self, forKey: .int))
        case .float:
            self = .float(try container.decode(Float.self, forKey: .float))
        case .vec2:
            let values = try container.decode([Float].self, forKey: .vec2)
            let x = values.count > 0 ? values[0] : 0.0
            let y = values.count > 1 ? values[1] : 0.0
            self = .vec2(SIMD2<Float>(x, y))
        case .number:
            self = .float(try container.decode(Float.self, forKey: .number))
        case .boolean:
            self = .bool(try container.decode(Bool.self, forKey: .boolean))
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .vec3:
            let values = try container.decode([Float].self, forKey: .vec3)
            let x = values.count > 0 ? values[0] : 0.0
            let y = values.count > 1 ? values[1] : 0.0
            let z = values.count > 2 ? values[2] : 0.0
            self = .vec3(SIMD3<Float>(x, y, z))
        case .color3:
            let values = try container.decode([Float].self, forKey: .color3)
            let x = values.count > 0 ? values[0] : 1.0
            let y = values.count > 1 ? values[1] : 1.0
            let z = values.count > 2 ? values[2] : 1.0
            self = .color3(SIMD3<Float>(x, y, z))
        case .entity:
            if let raw = try container.decodeIfPresent(String.self, forKey: .entity), let uuid = UUID(uuidString: raw) {
                self = .entity(uuid)
            } else {
                self = .entity(nil)
            }
        case .prefab:
            if let raw = try container.decodeIfPresent(String.self, forKey: .prefab),
               let uuid = UUID(uuidString: raw) {
                self = .prefab(AssetHandle(rawValue: uuid))
            } else {
                self = .prefab(nil)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bool(value):
            try container.encode(ScriptFieldType.bool, forKey: .type)
            try container.encode(value, forKey: .bool)
        case let .int(value):
            try container.encode(ScriptFieldType.int, forKey: .type)
            try container.encode(value, forKey: .int)
        case let .float(value):
            try container.encode(ScriptFieldType.float, forKey: .type)
            try container.encode(value, forKey: .float)
        case let .vec2(value):
            try container.encode(ScriptFieldType.vec2, forKey: .type)
            try container.encode([value.x, value.y], forKey: .vec2)
        case let .string(value):
            try container.encode(ScriptFieldType.string, forKey: .type)
            try container.encode(value, forKey: .string)
        case let .vec3(value):
            try container.encode(ScriptFieldType.vec3, forKey: .type)
            try container.encode([value.x, value.y, value.z], forKey: .vec3)
        case let .color3(value):
            try container.encode(ScriptFieldType.color3, forKey: .type)
            try container.encode([value.x, value.y, value.z], forKey: .color3)
        case let .entity(value):
            try container.encode(ScriptFieldType.entity, forKey: .type)
            try container.encode(value?.uuidString, forKey: .entity)
        case let .prefab(value):
            try container.encode(ScriptFieldType.prefab, forKey: .type)
            try container.encode(value?.rawValue.uuidString, forKey: .prefab)
        }
    }
}

public struct CharacterControllerComponent {
    public var isEnabled: Bool
    public var height: Float
    public var radius: Float
    public var stepOffset: Float
    public var slopeLimit: Float
    public var moveSpeed: Float
    public var sprintMultiplier: Float
    public var jumpSpeed: Float
    public var useGravityOverride: Bool
    public var gravity: Float
    public var groundProbeDistance: Float
    public var maxSlope: Float
    public var groundSnapDistance: Float
    public var lookSensitivity: Float
    public var minPitchDegrees: Float
    public var maxPitchDegrees: Float
    public var pushStrength: Float
    public var visualEntityId: UUID?
    public var cameraPivotEntityId: UUID?
    public var debugDraw: Bool

    // Runtime state
    public var moveInput: SIMD2<Float>
    public var lookInput: SIMD2<Float>
    public var wantsSprint: Bool
    public var verticalVelocity: Float
    public var velocity: SIMD3<Float>
    public var isGrounded: Bool
    public var groundedStickyFrames: Int
    public var lastGroundNormal: SIMD3<Float>
    public var yawRadians: Float
    public var pitchRadians: Float
    public var lookInitialized: Bool
    public var debugProbeStart: SIMD3<Float>
    public var debugProbeEnd: SIMD3<Float>
    public var debugProbeHitPoint: SIMD3<Float>
    public var debugProbeHadHit: Bool
    public var debugSweepStart: SIMD3<Float>
    public var debugSweepEnd: SIMD3<Float>
    public var debugStepUpEnd: SIMD3<Float>
    public var debugStepForwardEnd: SIMD3<Float>
    public var debugStepDidApply: Bool
    public var debugDepenetrationEnd: SIMD3<Float>
    public var debugPenetrationDepth: Float
    public var debugSnapStart: SIMD3<Float>
    public var debugSnapEnd: SIMD3<Float>
    public var debugSnapDidApply: Bool
    public var debugPushEnd: SIMD3<Float>
    public var debugPushDidApply: Bool
    public var debugSweepNormal: SIMD3<Float>
    public var debugSweepDidCollide: Bool

    public init(isEnabled: Bool = true,
                height: Float = 1.8,
                radius: Float = 0.35,
                stepOffset: Float = 0.25,
                slopeLimit: Float = 45.0,
                moveSpeed: Float = 4.0,
                sprintMultiplier: Float = 1.5,
                jumpSpeed: Float = 5.5,
                useGravityOverride: Bool = false,
                gravity: Float = -9.81,
                groundProbeDistance: Float = 0.25,
                maxSlope: Float = 45.0,
                groundSnapDistance: Float = 0.1,
                lookSensitivity: Float = 0.01,
                minPitchDegrees: Float = -80.0,
                maxPitchDegrees: Float = 80.0,
                pushStrength: Float = 10.0,
                visualEntityId: UUID? = nil,
                cameraPivotEntityId: UUID? = nil,
                debugDraw: Bool = false,
                moveInput: SIMD2<Float> = .zero,
                lookInput: SIMD2<Float> = .zero,
                wantsSprint: Bool = false,
                verticalVelocity: Float = 0.0,
                velocity: SIMD3<Float> = .zero,
                isGrounded: Bool = false,
                groundedStickyFrames: Int = 0,
                lastGroundNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                yawRadians: Float = 0.0,
                pitchRadians: Float = 0.0,
                lookInitialized: Bool = false,
                debugProbeStart: SIMD3<Float> = .zero,
                debugProbeEnd: SIMD3<Float> = .zero,
                debugProbeHitPoint: SIMD3<Float> = .zero,
                debugProbeHadHit: Bool = false,
                debugSweepStart: SIMD3<Float> = .zero,
                debugSweepEnd: SIMD3<Float> = .zero,
                debugStepUpEnd: SIMD3<Float> = .zero,
                debugStepForwardEnd: SIMD3<Float> = .zero,
                debugStepDidApply: Bool = false,
                debugDepenetrationEnd: SIMD3<Float> = .zero,
                debugPenetrationDepth: Float = 0.0,
                debugSnapStart: SIMD3<Float> = .zero,
                debugSnapEnd: SIMD3<Float> = .zero,
                debugSnapDidApply: Bool = false,
                debugPushEnd: SIMD3<Float> = .zero,
                debugPushDidApply: Bool = false,
                debugSweepNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                debugSweepDidCollide: Bool = false) {
        self.isEnabled = isEnabled
        self.height = height
        self.radius = radius
        self.stepOffset = stepOffset
        self.slopeLimit = slopeLimit
        self.moveSpeed = moveSpeed
        self.sprintMultiplier = sprintMultiplier
        self.jumpSpeed = jumpSpeed
        self.useGravityOverride = useGravityOverride
        self.gravity = gravity
        self.groundProbeDistance = groundProbeDistance
        self.maxSlope = maxSlope
        self.groundSnapDistance = groundSnapDistance
        self.lookSensitivity = lookSensitivity
        self.minPitchDegrees = minPitchDegrees
        self.maxPitchDegrees = maxPitchDegrees
        self.pushStrength = pushStrength
        self.visualEntityId = visualEntityId
        self.cameraPivotEntityId = cameraPivotEntityId
        self.debugDraw = debugDraw
        self.moveInput = moveInput
        self.lookInput = lookInput
        self.wantsSprint = wantsSprint
        self.verticalVelocity = verticalVelocity
        self.velocity = velocity
        self.isGrounded = isGrounded
        self.groundedStickyFrames = groundedStickyFrames
        self.lastGroundNormal = lastGroundNormal
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
        self.lookInitialized = lookInitialized
        self.debugProbeStart = debugProbeStart
        self.debugProbeEnd = debugProbeEnd
        self.debugProbeHitPoint = debugProbeHitPoint
        self.debugProbeHadHit = debugProbeHadHit
        self.debugSweepStart = debugSweepStart
        self.debugSweepEnd = debugSweepEnd
        self.debugStepUpEnd = debugStepUpEnd
        self.debugStepForwardEnd = debugStepForwardEnd
        self.debugStepDidApply = debugStepDidApply
        self.debugDepenetrationEnd = debugDepenetrationEnd
        self.debugPenetrationDepth = debugPenetrationDepth
        self.debugSnapStart = debugSnapStart
        self.debugSnapEnd = debugSnapEnd
        self.debugSnapDidApply = debugSnapDidApply
        self.debugPushEnd = debugPushEnd
        self.debugPushDidApply = debugPushDidApply
        self.debugSweepNormal = debugSweepNormal
        self.debugSweepDidCollide = debugSweepDidCollide
    }
}

public enum PrefabOverrideType: String, Codable, CaseIterable {
    case name
    case hierarchy
    case layer
    case meshRenderer
    case material
    case rigidbody
    case collider
    case light
    case lightOrbit
    case camera
    case script
    case sky
    case skyLight
    case skyLightTag
    case skySunTag
}

public struct PrefabOverrideComponent {
    public var overridden: Set<PrefabOverrideType>

    public init(overridden: Set<PrefabOverrideType> = []) {
        self.overridden = overridden
    }

    public func contains(_ type: PrefabOverrideType) -> Bool {
        return overridden.contains(type)
    }
}

public struct PrefabInstanceComponent {
    public var prefabHandle: AssetHandle
    public var prefabEntityId: UUID
    public var instanceId: UUID

    public init(prefabHandle: AssetHandle, prefabEntityId: UUID, instanceId: UUID = UUID()) {
        self.prefabHandle = prefabHandle
        self.prefabEntityId = prefabEntityId
        self.instanceId = instanceId
    }
}

public struct MeshRendererComponent {
    public var meshHandle: AssetHandle?
    public var materialHandle: AssetHandle?
    public var submeshMaterialHandles: [AssetHandle?]?
    public var material: MetalCupMaterial?
    public var albedoMapHandle: AssetHandle?
    public var normalMapHandle: AssetHandle?
    public var metallicMapHandle: AssetHandle?
    public var roughnessMapHandle: AssetHandle?
    public var mrMapHandle: AssetHandle?
    public var ormMapHandle: AssetHandle?
    public var aoMapHandle: AssetHandle?
    public var emissiveMapHandle: AssetHandle?

    public init(
        meshHandle: AssetHandle?,
        materialHandle: AssetHandle? = nil,
        submeshMaterialHandles: [AssetHandle?]? = nil,
        material: MetalCupMaterial? = nil,
        albedoMapHandle: AssetHandle? = nil,
        normalMapHandle: AssetHandle? = nil,
        metallicMapHandle: AssetHandle? = nil,
        roughnessMapHandle: AssetHandle? = nil,
        mrMapHandle: AssetHandle? = nil,
        ormMapHandle: AssetHandle? = nil,
        aoMapHandle: AssetHandle? = nil,
        emissiveMapHandle: AssetHandle? = nil
    ) {
        self.meshHandle = meshHandle
        self.materialHandle = materialHandle
        self.submeshMaterialHandles = submeshMaterialHandles
        self.material = material
        self.albedoMapHandle = albedoMapHandle
        self.normalMapHandle = normalMapHandle
        self.metallicMapHandle = metallicMapHandle
        self.roughnessMapHandle = roughnessMapHandle
        self.mrMapHandle = mrMapHandle
        self.ormMapHandle = ormMapHandle
        self.aoMapHandle = aoMapHandle
        self.emissiveMapHandle = emissiveMapHandle
    }
}

public struct MaterialComponent {
    public var materialHandle: AssetHandle?

    public init(materialHandle: AssetHandle? = nil) {
        self.materialHandle = materialHandle
    }
}

public enum ProjectionType: UInt32 {
    case perspective = 0
    case orthographic = 1
}

public struct CameraComponent {
    public var fovDegrees: Float
    public var orthoSize: Float
    public var nearPlane: Float
    public var farPlane: Float
    public var projectionType: ProjectionType
    public var isPrimary: Bool
    public var isEditor: Bool

    public init(
        fovDegrees: Float = 45.0,
        orthoSize: Float = 10.0,
        nearPlane: Float = 0.1,
        farPlane: Float = 1000.0,
        projectionType: ProjectionType = .perspective,
        isPrimary: Bool = true,
        isEditor: Bool = true
    ) {
        self.fovDegrees = fovDegrees
        self.orthoSize = orthoSize
        self.nearPlane = nearPlane
        self.farPlane = farPlane
        self.projectionType = projectionType
        self.isPrimary = isPrimary
        self.isEditor = isEditor
    }
}

public enum LightType {
    case point
    case spot
    case directional
}

public struct LightComponent {
    public var type: LightType
    public var data: LightData
    /// Direction the light rays travel (from the light toward the scene).
    /// For directional lights, runtime derives this from TransformComponent.rotation.
    /// This value is retained for backward compatibility/fallback serialization.
    public var direction: SIMD3<Float>
    public var range: Float
    public var innerConeCos: Float
    public var outerConeCos: Float
    public var castsShadows: Bool

    public init(
        type: LightType = .point,
        data: LightData = LightData(),
        direction: SIMD3<Float> = SIMD3<Float>(0, -1, 0),
        range: Float = 0.0,
        innerConeCos: Float = 0.95,
        outerConeCos: Float = 0.9,
        castsShadows: Bool = false
    ) {
        self.type = type
        self.data = data
        self.direction = direction
        self.range = range
        self.innerConeCos = innerConeCos
        self.outerConeCos = outerConeCos
        self.castsShadows = castsShadows
    }
}

public struct LightOrbitComponent {
    public var centerEntityId: UUID?
    public var radius: Float
    public var speed: Float
    public var height: Float
    public var phase: Float
    public var affectsDirection: Bool

    public init(
        centerEntityId: UUID? = nil,
        radius: Float = 1.0,
        speed: Float = 1.0,
        height: Float = 0.0,
        phase: Float = 0.0,
        affectsDirection: Bool = true
    ) {
        self.centerEntityId = centerEntityId
        self.radius = radius
        self.speed = speed
        self.height = height
        self.phase = phase
        self.affectsDirection = affectsDirection
    }
}

public struct SkyComponent {
    public var environmentMapHandle: AssetHandle?

    public init(environmentMapHandle: AssetHandle? = nil) {
        self.environmentMapHandle = environmentMapHandle
    }
}

public enum SkyMode: UInt32 {
    case hdri = 0
    case procedural = 1
}

public struct SkyLightComponent: Equatable {
    public var mode: SkyMode
    public var enabled: Bool
    public var intensity: Float
    public var skyTint: SIMD3<Float>
    public var turbidity: Float
    public var azimuthDegrees: Float
    public var elevationDegrees: Float
    public var sunSizeDegrees: Float
    public var zenithTint: SIMD3<Float>
    public var horizonTint: SIMD3<Float>
    public var gradientStrength: Float
    public var hazeDensity: Float
    public var hazeFalloff: Float
    public var hazeHeight: Float
    public var ozoneStrength: Float
    public var ozoneTint: SIMD3<Float>
    public var sunHaloSize: Float
    public var sunHaloIntensity: Float
    public var sunHaloSoftness: Float
    public var cloudsEnabled: Bool
    public var cloudsCoverage: Float
    public var cloudsSoftness: Float
    public var cloudsScale: Float
    public var cloudsSpeed: Float
    public var cloudsWindDirection: SIMD2<Float>
    public var cloudsHeight: Float
    public var cloudsThickness: Float
    public var cloudsBrightness: Float
    public var cloudsSunInfluence: Float
    public var hdriHandle: AssetHandle?
    public var iblEnvironmentHandle: AssetHandle?
    public var iblIrradianceHandle: AssetHandle?
    public var iblPrefilteredHandle: AssetHandle?
    public var iblBrdfHandle: AssetHandle?
    public var needsRebuild: Bool
    public var rebuildRequested: Bool
    public var realtimeUpdate: Bool
    public var lastRebuildTime: Double

    public init(
        mode: SkyMode = .hdri,
        enabled: Bool = true,
        intensity: Float = 1.0,
        skyTint: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0),
        turbidity: Float = 2.0,
        azimuthDegrees: Float = 0.0,
        elevationDegrees: Float = 30.0,
        sunSizeDegrees: Float = 0.535,
        zenithTint: SIMD3<Float> = SIMD3<Float>(0.24, 0.45, 0.95),
        horizonTint: SIMD3<Float> = SIMD3<Float>(0.95, 0.75, 0.55),
        gradientStrength: Float = 1.0,
        hazeDensity: Float = 0.35,
        hazeFalloff: Float = 2.2,
        hazeHeight: Float = 0.0,
        ozoneStrength: Float = 0.35,
        ozoneTint: SIMD3<Float> = SIMD3<Float>(0.55, 0.7, 1.0),
        sunHaloSize: Float = 2.5,
        sunHaloIntensity: Float = 0.5,
        sunHaloSoftness: Float = 1.2,
        cloudsEnabled: Bool = false,
        cloudsCoverage: Float = 0.35,
        cloudsSoftness: Float = 0.6,
        cloudsScale: Float = 1.0,
        cloudsSpeed: Float = 0.02,
        cloudsWindDirection: SIMD2<Float> = SIMD2<Float>(1.0, 0.0),
        cloudsHeight: Float = 0.25,
        cloudsThickness: Float = 0.35,
        cloudsBrightness: Float = 1.0,
        cloudsSunInfluence: Float = 1.0,
        hdriHandle: AssetHandle? = nil,
        iblEnvironmentHandle: AssetHandle? = nil,
        iblIrradianceHandle: AssetHandle? = nil,
        iblPrefilteredHandle: AssetHandle? = nil,
        iblBrdfHandle: AssetHandle? = nil,
        needsRebuild: Bool = true,
        rebuildRequested: Bool = false,
        realtimeUpdate: Bool = true,
        lastRebuildTime: Double = 0.0
    ) {
        self.mode = mode
        self.enabled = enabled
        self.intensity = intensity
        self.skyTint = skyTint
        self.turbidity = turbidity
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
        self.sunSizeDegrees = sunSizeDegrees
        self.zenithTint = zenithTint
        self.horizonTint = horizonTint
        self.gradientStrength = gradientStrength
        self.hazeDensity = hazeDensity
        self.hazeFalloff = hazeFalloff
        self.hazeHeight = hazeHeight
        self.ozoneStrength = ozoneStrength
        self.ozoneTint = ozoneTint
        self.sunHaloSize = sunHaloSize
        self.sunHaloIntensity = sunHaloIntensity
        self.sunHaloSoftness = sunHaloSoftness
        self.cloudsEnabled = cloudsEnabled
        self.cloudsCoverage = cloudsCoverage
        self.cloudsSoftness = cloudsSoftness
        self.cloudsScale = cloudsScale
        self.cloudsSpeed = cloudsSpeed
        self.cloudsWindDirection = cloudsWindDirection
        self.cloudsHeight = cloudsHeight
        self.cloudsThickness = cloudsThickness
        self.cloudsBrightness = cloudsBrightness
        self.cloudsSunInfluence = cloudsSunInfluence
        self.hdriHandle = hdriHandle
        self.iblEnvironmentHandle = iblEnvironmentHandle
        self.iblIrradianceHandle = iblIrradianceHandle
        self.iblPrefilteredHandle = iblPrefilteredHandle
        self.iblBrdfHandle = iblBrdfHandle
        self.needsRebuild = needsRebuild
        self.rebuildRequested = rebuildRequested
        self.realtimeUpdate = realtimeUpdate
        self.lastRebuildTime = lastRebuildTime
    }
}

public struct SkyLightTag {
    public init() {}
}

public struct SkySunTag {
    public init() {}
}
