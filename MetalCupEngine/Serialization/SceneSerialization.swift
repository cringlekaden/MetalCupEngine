/// SceneSerialization.swift
/// Defines the SceneSerialization types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public enum SceneSchema {
    public static let currentVersion: Int = 1
}

public struct SceneDocument: Codable {
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var entities: [EntityDocument]
    public var rendererSettingsOverride: RendererSettingsDTO?

    public init(
        schemaVersion: Int = SceneSchema.currentVersion,
        id: UUID,
        name: String,
        entities: [EntityDocument],
        rendererSettingsOverride: RendererSettingsDTO? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.entities = entities
        self.rendererSettingsOverride = rendererSettingsOverride
    }
}

public struct EntityDocument: Codable {
    public var id: UUID
    public var components: ComponentsDocument

    public init(id: UUID, components: ComponentsDocument) {
        self.id = id
        self.components = components
    }
}

public struct ComponentsDocument: Codable {
    public var name: NameComponentDTO?
    public var transform: TransformComponentDTO?
    public var meshRenderer: MeshRendererComponentDTO?
    public var materialComponent: MaterialComponentDTO?
    public var light: LightComponentDTO?
    public var lightOrbit: LightOrbitComponentDTO?
    public var camera: CameraComponentDTO?
    public var sky: SkyComponentDTO?
    public var skyLight: SkyLightComponentDTO?
    public var skyLightTag: TagComponentDTO?
    public var skySunTag: TagComponentDTO?

    public init(
        name: NameComponentDTO? = nil,
        transform: TransformComponentDTO? = nil,
        meshRenderer: MeshRendererComponentDTO? = nil,
        materialComponent: MaterialComponentDTO? = nil,
        light: LightComponentDTO? = nil,
        lightOrbit: LightOrbitComponentDTO? = nil,
        camera: CameraComponentDTO? = nil,
        sky: SkyComponentDTO? = nil,
        skyLight: SkyLightComponentDTO? = nil,
        skyLightTag: TagComponentDTO? = nil,
        skySunTag: TagComponentDTO? = nil
    ) {
        self.name = name
        self.transform = transform
        self.meshRenderer = meshRenderer
        self.materialComponent = materialComponent
        self.light = light
        self.lightOrbit = lightOrbit
        self.camera = camera
        self.sky = sky
        self.skyLight = skyLight
        self.skyLightTag = skyLightTag
        self.skySunTag = skySunTag
    }
}

public struct TagComponentDTO: Codable {
    public var schemaVersion: Int

    public init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
    }
}

public struct NameComponentDTO: Codable {
    public var schemaVersion: Int
    public var name: String

    public init(schemaVersion: Int = 1, name: String) {
        self.schemaVersion = schemaVersion
        self.name = name
    }
}

public struct TransformComponentDTO: Codable {
    public var schemaVersion: Int
    public var position: Vector3DTO
    public var rotation: Vector3DTO
    public var scale: Vector3DTO

    public init(schemaVersion: Int = 1, position: Vector3DTO, rotation: Vector3DTO, scale: Vector3DTO) {
        self.schemaVersion = schemaVersion
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public struct MeshRendererComponentDTO: Codable {
    public var schemaVersion: Int
    public var meshHandle: AssetHandle?
    public var materialHandle: AssetHandle?
    public var material: MaterialDTO?
    public var albedoMapHandle: AssetHandle?
    public var normalMapHandle: AssetHandle?
    public var metallicMapHandle: AssetHandle?
    public var roughnessMapHandle: AssetHandle?
    public var mrMapHandle: AssetHandle?
    public var aoMapHandle: AssetHandle?
    public var emissiveMapHandle: AssetHandle?

    public init(
        schemaVersion: Int = 1,
        meshHandle: AssetHandle?,
        materialHandle: AssetHandle?,
        material: MaterialDTO?,
        albedoMapHandle: AssetHandle?,
        normalMapHandle: AssetHandle?,
        metallicMapHandle: AssetHandle?,
        roughnessMapHandle: AssetHandle?,
        mrMapHandle: AssetHandle?,
        aoMapHandle: AssetHandle?,
        emissiveMapHandle: AssetHandle?
    ) {
        self.schemaVersion = schemaVersion
        self.meshHandle = meshHandle
        self.materialHandle = materialHandle
        self.material = material
        self.albedoMapHandle = albedoMapHandle
        self.normalMapHandle = normalMapHandle
        self.metallicMapHandle = metallicMapHandle
        self.roughnessMapHandle = roughnessMapHandle
        self.mrMapHandle = mrMapHandle
        self.aoMapHandle = aoMapHandle
        self.emissiveMapHandle = emissiveMapHandle
    }
}

public struct MaterialComponentDTO: Codable {
    public var schemaVersion: Int
    public var materialHandle: AssetHandle?

    public init(schemaVersion: Int = 1, materialHandle: AssetHandle?) {
        self.schemaVersion = schemaVersion
        self.materialHandle = materialHandle
    }
}

public struct LightComponentDTO: Codable {
    public var schemaVersion: Int
    public var type: LightTypeDTO
    public var data: LightDataDTO
    public var direction: Vector3DTO
    public var range: Float
    public var innerConeCos: Float
    public var outerConeCos: Float

    public init(
        schemaVersion: Int = 1,
        type: LightTypeDTO,
        data: LightDataDTO,
        direction: Vector3DTO,
        range: Float,
        innerConeCos: Float,
        outerConeCos: Float
    ) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.data = data
        self.direction = direction
        self.range = range
        self.innerConeCos = innerConeCos
        self.outerConeCos = outerConeCos
    }
}

public struct LightOrbitComponentDTO: Codable {
    public var schemaVersion: Int
    public var centerEntityId: UUID?
    public var radius: Float
    public var speed: Float
    public var height: Float
    public var phase: Float
    public var affectsDirection: Bool

    public init(
        schemaVersion: Int = 1,
        centerEntityId: UUID?,
        radius: Float,
        speed: Float,
        height: Float,
        phase: Float,
        affectsDirection: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.centerEntityId = centerEntityId
        self.radius = radius
        self.speed = speed
        self.height = height
        self.phase = phase
        self.affectsDirection = affectsDirection
    }

    public init(component: LightOrbitComponent) {
        self.schemaVersion = 1
        self.centerEntityId = component.centerEntityId
        self.radius = component.radius
        self.speed = component.speed
        self.height = component.height
        self.phase = component.phase
        self.affectsDirection = component.affectsDirection
    }

    public func toComponent() -> LightOrbitComponent {
        return LightOrbitComponent(
            centerEntityId: centerEntityId,
            radius: radius,
            speed: speed,
            height: height,
            phase: phase,
            affectsDirection: affectsDirection
        )
    }
}

public struct CameraComponentDTO: Codable {
    public var schemaVersion: Int
    public var fovDegrees: Float
    public var nearPlane: Float
    public var farPlane: Float
    public var projectionType: UInt32
    public var isPrimary: Bool
    public var isEditor: Bool

    public init(schemaVersion: Int = 1, component: CameraComponent) {
        self.schemaVersion = schemaVersion
        self.fovDegrees = component.fovDegrees
        self.nearPlane = component.nearPlane
        self.farPlane = component.farPlane
        self.projectionType = component.projectionType.rawValue
        self.isPrimary = component.isPrimary
        self.isEditor = component.isEditor
    }

    public func toComponent() -> CameraComponent {
        return CameraComponent(
            fovDegrees: fovDegrees,
            nearPlane: nearPlane,
            farPlane: farPlane,
            projectionType: ProjectionType(rawValue: projectionType) ?? .perspective,
            isPrimary: isPrimary,
            isEditor: isEditor
        )
    }
}

public struct SkyComponentDTO: Codable {
    public var schemaVersion: Int
    public var environmentMapHandle: AssetHandle?

    public init(schemaVersion: Int = 1, environmentMapHandle: AssetHandle?) {
        self.schemaVersion = schemaVersion
        self.environmentMapHandle = environmentMapHandle
    }
}

public struct SkyLightComponentDTO: Codable {
    public var schemaVersion: Int
    public var mode: UInt32
    public var enabled: Bool
    public var intensity: Float
    public var skyTint: Vector3DTO
    public var turbidity: Float
    public var azimuthDegrees: Float
    public var elevationDegrees: Float
    public var hdriHandle: AssetHandle?
    public var realtimeUpdate: Bool

    public init(
        schemaVersion: Int = 1,
        mode: UInt32,
        enabled: Bool,
        intensity: Float,
        skyTint: Vector3DTO,
        turbidity: Float,
        azimuthDegrees: Float,
        elevationDegrees: Float,
        hdriHandle: AssetHandle?,
        realtimeUpdate: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.enabled = enabled
        self.intensity = intensity
        self.skyTint = skyTint
        self.turbidity = turbidity
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
        self.hdriHandle = hdriHandle
        self.realtimeUpdate = realtimeUpdate
    }
}

public struct RendererSettingsDTO: Codable {
    public var schemaVersion: Int
    public var bloomThreshold: Float
    public var bloomKnee: Float
    public var bloomIntensity: Float
    public var bloomUpsampleScale: Float
    public var bloomDirtIntensity: Float
    public var bloomEnabled: UInt32
    public var bloomMaxMips: UInt32
    public var blurPasses: UInt32
    public var tonemap: UInt32
    public var exposure: Float
    public var gamma: Float
    public var iblEnabled: UInt32
    public var iblIntensity: Float
    public var iblResolutionOverride: UInt32
    public var perfFlags: UInt32
    public var normalFlipYGlobal: UInt32
    public var iblFireflyClamp: Float
    public var iblFireflyClampEnabled: UInt32
    public var iblSampleMultiplier: Float
    public var iblSpecularLodExponent: Float
    public var iblSpecularLodBias: Float
    public var iblSpecularGrazingLodBias: Float
    public var iblSpecularMinRoughness: Float
    public var specularAAStrength: Float
    public var normalMapMipBias: Float
    public var normalMapMipBiasGrazing: Float
    public var shadingDebugMode: UInt32
    public var iblQualityPreset: UInt32
    public var outlineEnabled: UInt32
    public var outlineThickness: UInt32
    public var outlineOpacity: Float
    public var outlineColor: Vector3DTO
    public var gridEnabled: UInt32
    public var gridOpacity: Float
    public var gridFadeDistance: Float
    public var gridMajorLineEvery: Float

    public init(schemaVersion: Int = 1, settings: RendererSettings) {
        self.schemaVersion = schemaVersion
        self.bloomThreshold = settings.bloomThreshold
        self.bloomKnee = settings.bloomKnee
        self.bloomIntensity = settings.bloomIntensity
        self.bloomUpsampleScale = settings.bloomUpsampleScale
        self.bloomDirtIntensity = settings.bloomDirtIntensity
        self.bloomEnabled = settings.bloomEnabled
        self.bloomMaxMips = settings.bloomMaxMips
        self.blurPasses = settings.blurPasses
        self.tonemap = settings.tonemap
        self.exposure = settings.exposure
        self.gamma = settings.gamma
        self.iblEnabled = settings.iblEnabled
        self.iblIntensity = settings.iblIntensity
        self.iblResolutionOverride = settings.iblResolutionOverride
        self.perfFlags = settings.perfFlags
        self.normalFlipYGlobal = settings.normalFlipYGlobal
        self.iblFireflyClamp = settings.iblFireflyClamp
        self.iblFireflyClampEnabled = settings.iblFireflyClampEnabled
        self.iblSampleMultiplier = settings.iblSampleMultiplier
        self.iblSpecularLodExponent = settings.iblSpecularLodExponent
        self.iblSpecularLodBias = settings.iblSpecularLodBias
        self.iblSpecularGrazingLodBias = settings.iblSpecularGrazingLodBias
        self.iblSpecularMinRoughness = settings.iblSpecularMinRoughness
        self.specularAAStrength = settings.specularAAStrength
        self.normalMapMipBias = settings.normalMapMipBias
        self.normalMapMipBiasGrazing = settings.normalMapMipBiasGrazing
        self.shadingDebugMode = settings.shadingDebugMode
        self.iblQualityPreset = settings.iblQualityPreset
        self.outlineEnabled = settings.outlineEnabled
        self.outlineThickness = settings.outlineThickness
        self.outlineOpacity = settings.outlineOpacity
        self.outlineColor = Vector3DTO(settings.outlineColor)
        self.gridEnabled = settings.gridEnabled
        self.gridOpacity = settings.gridOpacity
        self.gridFadeDistance = settings.gridFadeDistance
        self.gridMajorLineEvery = settings.gridMajorLineEvery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RendererSettings()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        bloomThreshold = try container.decodeIfPresent(Float.self, forKey: .bloomThreshold) ?? defaults.bloomThreshold
        bloomKnee = try container.decodeIfPresent(Float.self, forKey: .bloomKnee) ?? defaults.bloomKnee
        bloomIntensity = try container.decodeIfPresent(Float.self, forKey: .bloomIntensity) ?? defaults.bloomIntensity
        bloomUpsampleScale = try container.decodeIfPresent(Float.self, forKey: .bloomUpsampleScale) ?? defaults.bloomUpsampleScale
        bloomDirtIntensity = try container.decodeIfPresent(Float.self, forKey: .bloomDirtIntensity) ?? defaults.bloomDirtIntensity
        bloomEnabled = try container.decodeIfPresent(UInt32.self, forKey: .bloomEnabled) ?? defaults.bloomEnabled
        bloomMaxMips = try container.decodeIfPresent(UInt32.self, forKey: .bloomMaxMips) ?? defaults.bloomMaxMips
        blurPasses = try container.decodeIfPresent(UInt32.self, forKey: .blurPasses) ?? defaults.blurPasses
        tonemap = try container.decodeIfPresent(UInt32.self, forKey: .tonemap) ?? defaults.tonemap
        exposure = try container.decodeIfPresent(Float.self, forKey: .exposure) ?? defaults.exposure
        gamma = try container.decodeIfPresent(Float.self, forKey: .gamma) ?? defaults.gamma
        iblEnabled = try container.decodeIfPresent(UInt32.self, forKey: .iblEnabled) ?? defaults.iblEnabled
        iblIntensity = try container.decodeIfPresent(Float.self, forKey: .iblIntensity) ?? defaults.iblIntensity
        iblResolutionOverride = try container.decodeIfPresent(UInt32.self, forKey: .iblResolutionOverride) ?? defaults.iblResolutionOverride
        perfFlags = try container.decodeIfPresent(UInt32.self, forKey: .perfFlags) ?? defaults.perfFlags
        normalFlipYGlobal = try container.decodeIfPresent(UInt32.self, forKey: .normalFlipYGlobal) ?? defaults.normalFlipYGlobal
        iblFireflyClamp = try container.decodeIfPresent(Float.self, forKey: .iblFireflyClamp) ?? defaults.iblFireflyClamp
        iblFireflyClampEnabled = try container.decodeIfPresent(UInt32.self, forKey: .iblFireflyClampEnabled) ?? defaults.iblFireflyClampEnabled
        iblSampleMultiplier = try container.decodeIfPresent(Float.self, forKey: .iblSampleMultiplier) ?? defaults.iblSampleMultiplier
        iblSpecularLodExponent = try container.decodeIfPresent(Float.self, forKey: .iblSpecularLodExponent) ?? defaults.iblSpecularLodExponent
        iblSpecularLodBias = try container.decodeIfPresent(Float.self, forKey: .iblSpecularLodBias) ?? defaults.iblSpecularLodBias
        iblSpecularGrazingLodBias = try container.decodeIfPresent(Float.self, forKey: .iblSpecularGrazingLodBias) ?? defaults.iblSpecularGrazingLodBias
        iblSpecularMinRoughness = try container.decodeIfPresent(Float.self, forKey: .iblSpecularMinRoughness) ?? defaults.iblSpecularMinRoughness
        specularAAStrength = try container.decodeIfPresent(Float.self, forKey: .specularAAStrength) ?? defaults.specularAAStrength
        normalMapMipBias = try container.decodeIfPresent(Float.self, forKey: .normalMapMipBias) ?? defaults.normalMapMipBias
        normalMapMipBiasGrazing = try container.decodeIfPresent(Float.self, forKey: .normalMapMipBiasGrazing) ?? defaults.normalMapMipBiasGrazing
        shadingDebugMode = try container.decodeIfPresent(UInt32.self, forKey: .shadingDebugMode) ?? defaults.shadingDebugMode
        iblQualityPreset = try container.decodeIfPresent(UInt32.self, forKey: .iblQualityPreset) ?? defaults.iblQualityPreset
        outlineEnabled = try container.decodeIfPresent(UInt32.self, forKey: .outlineEnabled) ?? defaults.outlineEnabled
        outlineThickness = try container.decodeIfPresent(UInt32.self, forKey: .outlineThickness) ?? defaults.outlineThickness
        outlineOpacity = try container.decodeIfPresent(Float.self, forKey: .outlineOpacity) ?? defaults.outlineOpacity
        outlineColor = try container.decodeIfPresent(Vector3DTO.self, forKey: .outlineColor) ?? Vector3DTO(defaults.outlineColor)
        gridEnabled = try container.decodeIfPresent(UInt32.self, forKey: .gridEnabled) ?? defaults.gridEnabled
        gridOpacity = try container.decodeIfPresent(Float.self, forKey: .gridOpacity) ?? defaults.gridOpacity
        gridFadeDistance = try container.decodeIfPresent(Float.self, forKey: .gridFadeDistance) ?? defaults.gridFadeDistance
        gridMajorLineEvery = try container.decodeIfPresent(Float.self, forKey: .gridMajorLineEvery) ?? defaults.gridMajorLineEvery
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(bloomThreshold, forKey: .bloomThreshold)
        try container.encode(bloomKnee, forKey: .bloomKnee)
        try container.encode(bloomIntensity, forKey: .bloomIntensity)
        try container.encode(bloomUpsampleScale, forKey: .bloomUpsampleScale)
        try container.encode(bloomDirtIntensity, forKey: .bloomDirtIntensity)
        try container.encode(bloomEnabled, forKey: .bloomEnabled)
        try container.encode(bloomMaxMips, forKey: .bloomMaxMips)
        try container.encode(blurPasses, forKey: .blurPasses)
        try container.encode(tonemap, forKey: .tonemap)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(gamma, forKey: .gamma)
        try container.encode(iblEnabled, forKey: .iblEnabled)
        try container.encode(iblIntensity, forKey: .iblIntensity)
        try container.encode(iblResolutionOverride, forKey: .iblResolutionOverride)
        try container.encode(perfFlags, forKey: .perfFlags)
        try container.encode(normalFlipYGlobal, forKey: .normalFlipYGlobal)
        try container.encode(iblFireflyClamp, forKey: .iblFireflyClamp)
        try container.encode(iblFireflyClampEnabled, forKey: .iblFireflyClampEnabled)
        try container.encode(iblSampleMultiplier, forKey: .iblSampleMultiplier)
        try container.encode(iblSpecularLodExponent, forKey: .iblSpecularLodExponent)
        try container.encode(iblSpecularLodBias, forKey: .iblSpecularLodBias)
        try container.encode(iblSpecularGrazingLodBias, forKey: .iblSpecularGrazingLodBias)
        try container.encode(iblSpecularMinRoughness, forKey: .iblSpecularMinRoughness)
        try container.encode(specularAAStrength, forKey: .specularAAStrength)
        try container.encode(normalMapMipBias, forKey: .normalMapMipBias)
        try container.encode(normalMapMipBiasGrazing, forKey: .normalMapMipBiasGrazing)
        try container.encode(shadingDebugMode, forKey: .shadingDebugMode)
        try container.encode(iblQualityPreset, forKey: .iblQualityPreset)
        try container.encode(outlineEnabled, forKey: .outlineEnabled)
        try container.encode(outlineThickness, forKey: .outlineThickness)
        try container.encode(outlineOpacity, forKey: .outlineOpacity)
        try container.encode(outlineColor, forKey: .outlineColor)
        try container.encode(gridEnabled, forKey: .gridEnabled)
        try container.encode(gridOpacity, forKey: .gridOpacity)
        try container.encode(gridFadeDistance, forKey: .gridFadeDistance)
        try container.encode(gridMajorLineEvery, forKey: .gridMajorLineEvery)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case bloomThreshold
        case bloomKnee
        case bloomIntensity
        case bloomUpsampleScale
        case bloomDirtIntensity
        case bloomEnabled
        case bloomMaxMips
        case blurPasses
        case tonemap
        case exposure
        case gamma
        case iblEnabled
        case iblIntensity
        case iblResolutionOverride
        case perfFlags
        case normalFlipYGlobal
        case iblFireflyClamp
        case iblFireflyClampEnabled
        case iblSampleMultiplier
        case iblSpecularLodExponent
        case iblSpecularLodBias
        case iblSpecularGrazingLodBias
        case iblSpecularMinRoughness
        case specularAAStrength
        case normalMapMipBias
        case normalMapMipBiasGrazing
        case shadingDebugMode
        case iblQualityPreset
        case outlineEnabled
        case outlineThickness
        case outlineOpacity
        case outlineColor
        case gridEnabled
        case gridOpacity
        case gridFadeDistance
        case gridMajorLineEvery
    }

    public func makeRendererSettings() -> RendererSettings {
        var settings = RendererSettings()
        settings.bloomThreshold = bloomThreshold
        settings.bloomKnee = bloomKnee
        settings.bloomIntensity = bloomIntensity
        settings.bloomUpsampleScale = bloomUpsampleScale
        settings.bloomDirtIntensity = bloomDirtIntensity
        settings.bloomEnabled = bloomEnabled
        settings.bloomMaxMips = bloomMaxMips
        settings.blurPasses = blurPasses
        settings.tonemap = tonemap
        settings.exposure = exposure
        settings.gamma = gamma
        settings.iblEnabled = iblEnabled
        settings.iblIntensity = iblIntensity
        settings.iblResolutionOverride = iblResolutionOverride
        settings.perfFlags = perfFlags
        settings.normalFlipYGlobal = normalFlipYGlobal
        settings.iblFireflyClamp = iblFireflyClamp
        settings.iblFireflyClampEnabled = iblFireflyClampEnabled
        settings.iblSampleMultiplier = iblSampleMultiplier
        settings.iblSpecularLodExponent = iblSpecularLodExponent
        settings.iblSpecularLodBias = iblSpecularLodBias
        settings.iblSpecularGrazingLodBias = iblSpecularGrazingLodBias
        settings.iblSpecularMinRoughness = iblSpecularMinRoughness
        settings.specularAAStrength = specularAAStrength
        settings.normalMapMipBias = normalMapMipBias
        settings.normalMapMipBiasGrazing = normalMapMipBiasGrazing
        settings.shadingDebugMode = shadingDebugMode
        settings.iblQualityPreset = iblQualityPreset
        settings.outlineEnabled = outlineEnabled
        settings.outlineThickness = outlineThickness
        settings.outlineOpacity = outlineOpacity
        settings.outlineColor = outlineColor.toSIMD()
        settings.gridEnabled = gridEnabled
        settings.gridOpacity = gridOpacity
        settings.gridFadeDistance = gridFadeDistance
        settings.gridMajorLineEvery = gridMajorLineEvery
        return settings
    }
}

public struct Vector3DTO: Codable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ value: SIMD3<Float>) {
        self.x = value.x
        self.y = value.y
        self.z = value.z
    }

    public func toSIMD() -> SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

public enum LightTypeDTO: String, Codable {
    case point
    case spot
    case directional

    public init(from type: LightType) {
        switch type {
        case .point:
            self = .point
        case .spot:
            self = .spot
        case .directional:
            self = .directional
        }
    }

    public func toLightType() -> LightType {
        switch self {
        case .point:
            return .point
        case .spot:
            return .spot
        case .directional:
            return .directional
        }
    }
}

public struct LightDataDTO: Codable {
    public var position: Vector3DTO
    public var type: UInt32
    public var direction: Vector3DTO
    public var range: Float
    public var color: Vector3DTO
    public var brightness: Float
    public var ambientIntensity: Float
    public var diffuseIntensity: Float
    public var specularIntensity: Float
    public var innerConeCos: Float
    public var outerConeCos: Float

    public init(from data: LightData) {
        self.position = Vector3DTO(data.position)
        self.type = data.type
        self.direction = Vector3DTO(data.direction)
        self.range = data.range
        self.color = Vector3DTO(data.color)
        self.brightness = data.brightness
        self.ambientIntensity = data.ambientIntensity
        self.diffuseIntensity = data.diffuseIntensity
        self.specularIntensity = data.specularIntensity
        self.innerConeCos = data.innerConeCos
        self.outerConeCos = data.outerConeCos
    }

    public func toLightData() -> LightData {
        var data = LightData()
        data.position = position.toSIMD()
        data.type = type
        data.direction = direction.toSIMD()
        data.range = range
        data.color = color.toSIMD()
        data.brightness = brightness
        data.ambientIntensity = ambientIntensity
        data.diffuseIntensity = diffuseIntensity
        data.specularIntensity = specularIntensity
        data.innerConeCos = innerConeCos
        data.outerConeCos = outerConeCos
        return data
    }
}

public struct MaterialDTO: Codable {
    public var schemaVersion: Int
    public var baseColor: Vector3DTO
    public var metallicScalar: Float
    public var roughnessScalar: Float
    public var aoScalar: Float
    public var emissiveColor: Vector3DTO
    public var emissiveScalar: Float
    public var alphaCutoff: Float
    public var flags: UInt32
    public var clearcoatFactor: Float
    public var clearcoatRoughness: Float
    public var sheenRoughness: Float
    public var sheenColor: Vector3DTO

    public init(schemaVersion: Int = 1, material: MetalCupMaterial) {
        self.schemaVersion = schemaVersion
        self.baseColor = Vector3DTO(material.baseColor)
        self.metallicScalar = material.metallicScalar
        self.roughnessScalar = material.roughnessScalar
        self.aoScalar = material.aoScalar
        self.emissiveColor = Vector3DTO(material.emissiveColor)
        self.emissiveScalar = material.emissiveScalar
        self.alphaCutoff = material.alphaCutoff
        self.flags = material.flags
        self.clearcoatFactor = material.clearcoatFactor
        self.clearcoatRoughness = material.clearcoatRoughness
        self.sheenRoughness = material.sheenRoughness
        self.sheenColor = Vector3DTO(material.sheenColor)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        baseColor = try container.decode(Vector3DTO.self, forKey: .baseColor)
        metallicScalar = try container.decode(Float.self, forKey: .metallicScalar)
        roughnessScalar = try container.decode(Float.self, forKey: .roughnessScalar)
        aoScalar = try container.decode(Float.self, forKey: .aoScalar)
        emissiveColor = try container.decode(Vector3DTO.self, forKey: .emissiveColor)
        emissiveScalar = try container.decode(Float.self, forKey: .emissiveScalar)
        alphaCutoff = try container.decodeIfPresent(Float.self, forKey: .alphaCutoff) ?? 0.5
        flags = try container.decode(UInt32.self, forKey: .flags)
        clearcoatFactor = try container.decode(Float.self, forKey: .clearcoatFactor)
        clearcoatRoughness = try container.decode(Float.self, forKey: .clearcoatRoughness)
        sheenRoughness = try container.decode(Float.self, forKey: .sheenRoughness)
        sheenColor = try container.decode(Vector3DTO.self, forKey: .sheenColor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(baseColor, forKey: .baseColor)
        try container.encode(metallicScalar, forKey: .metallicScalar)
        try container.encode(roughnessScalar, forKey: .roughnessScalar)
        try container.encode(aoScalar, forKey: .aoScalar)
        try container.encode(emissiveColor, forKey: .emissiveColor)
        try container.encode(emissiveScalar, forKey: .emissiveScalar)
        try container.encode(alphaCutoff, forKey: .alphaCutoff)
        try container.encode(flags, forKey: .flags)
        try container.encode(clearcoatFactor, forKey: .clearcoatFactor)
        try container.encode(clearcoatRoughness, forKey: .clearcoatRoughness)
        try container.encode(sheenRoughness, forKey: .sheenRoughness)
        try container.encode(sheenColor, forKey: .sheenColor)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case baseColor
        case metallicScalar
        case roughnessScalar
        case aoScalar
        case emissiveColor
        case emissiveScalar
        case alphaCutoff
        case flags
        case clearcoatFactor
        case clearcoatRoughness
        case sheenRoughness
        case sheenColor
    }

    public func toMaterial() -> MetalCupMaterial {
        var material = MetalCupMaterial()
        material.baseColor = baseColor.toSIMD()
        material.metallicScalar = metallicScalar
        material.roughnessScalar = roughnessScalar
        material.aoScalar = aoScalar
        material.emissiveColor = emissiveColor.toSIMD()
        material.emissiveScalar = emissiveScalar
        material.alphaCutoff = alphaCutoff
        material.flags = flags
        material.clearcoatFactor = clearcoatFactor
        material.clearcoatRoughness = clearcoatRoughness
        material.sheenRoughness = sheenRoughness
        material.sheenColor = sheenColor.toSIMD()
        return material
    }
}

public enum SceneSerializer {
    public static func save(scene: EngineScene, to url: URL) throws {
        let document = scene.toDocument(rendererSettingsOverride: RendererSettingsDTO(settings: Renderer.settings))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic])
    }

    public static func load(from url: URL) throws -> SceneDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document = try decoder.decode(SceneDocument.self, from: data)
        return migrateIfNeeded(document)
    }

    private static func migrateIfNeeded(_ document: SceneDocument) -> SceneDocument {
        if document.schemaVersion == SceneSchema.currentVersion {
            return document
        }
        print("WARN::SCENE::MIGRATE::Unsupported schema \(document.schemaVersion) -> \(SceneSchema.currentVersion)")
        return document
    }
}
