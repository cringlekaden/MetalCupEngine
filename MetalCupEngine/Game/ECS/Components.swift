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

    public init(isEnabled: Bool = true,
                shapeType: ColliderShapeType = .box,
                boxHalfExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5),
                sphereRadius: Float = 0.5,
                capsuleHalfHeight: Float = 0.5,
                capsuleRadius: Float = 0.5,
                offset: SIMD3<Float> = .zero,
                rotationOffset: SIMD3<Float> = .zero,
                isTrigger: Bool = false) {
        self.isEnabled = isEnabled
        self.shapeType = shapeType
        self.boxHalfExtents = boxHalfExtents
        self.sphereRadius = sphereRadius
        self.capsuleHalfHeight = capsuleHalfHeight
        self.capsuleRadius = capsuleRadius
        self.offset = offset
        self.rotationOffset = rotationOffset
        self.isTrigger = isTrigger
    }
}

public struct LayerComponent {
    public var index: Int32

    public init(index: Int32 = LayerCatalog.defaultLayerIndex) {
        self.index = index
    }
}

public enum PrefabOverrideType: String, Codable, CaseIterable {
    case name
    case layer
    case meshRenderer
    case material
    case rigidbody
    case collider
    case light
    case lightOrbit
    case camera
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
