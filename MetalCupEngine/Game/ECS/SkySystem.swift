/// SkySystem.swift
/// Defines the SkySystem types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public enum SkySystem {
    /// Returns the world-space direction from origin toward the sun disk in the sky.
    public static func sunDirection(azimuthDegrees: Float, elevationDegrees: Float) -> SIMD3<Float> {
        let azimuth = azimuthDegrees * Float.pi / 180.0
        let elevation = elevationDegrees * Float.pi / 180.0
        let cosEl = cos(elevation)
        let dir = SIMD3<Float>(
            cosEl * cos(azimuth),
            sin(elevation),
            cosEl * sin(azimuth)
        )
        return simd_normalize(dir)
    }

    /// Returns the world-space direction that sunlight rays travel (sun -> scene).
    public static func sunRayDirection(azimuthDegrees: Float, elevationDegrees: Float) -> SIMD3<Float> {
        -sunDirection(azimuthDegrees: azimuthDegrees, elevationDegrees: elevationDegrees)
    }

    /// Converts a world-space sun direction into procedural sky shader cubemap space.
    /// The sky cubemap sampling basis uses opposite handedness on Z versus world-space.
    public static func skyShaderSunDirection(fromWorldSunDirection direction: SIMD3<Float>) -> SIMD3<Float> {
        simd_normalize(SIMD3<Float>(direction.x, direction.y, -direction.z))
    }

    public static func requiresIBLRebuild(previous: SkyLightComponent, next: SkyLightComponent) -> Bool {
        if previous.mode != next.mode { return true }
        if previous.hdriHandle != next.hdriHandle { return true }
        return false
    }

    public static func liveSkyParamsMatch(_ lhs: SkyLightComponent, _ rhs: SkyLightComponent) -> Bool {
        return lhs.intensity == rhs.intensity
            && lhs.skyTint == rhs.skyTint
            && lhs.turbidity == rhs.turbidity
            && lhs.azimuthDegrees == rhs.azimuthDegrees
            && lhs.elevationDegrees == rhs.elevationDegrees
            && lhs.sunSizeDegrees == rhs.sunSizeDegrees
            && lhs.zenithTint == rhs.zenithTint
            && lhs.horizonTint == rhs.horizonTint
            && lhs.gradientStrength == rhs.gradientStrength
            && lhs.hazeDensity == rhs.hazeDensity
            && lhs.hazeFalloff == rhs.hazeFalloff
            && lhs.hazeHeight == rhs.hazeHeight
            && lhs.ozoneStrength == rhs.ozoneStrength
            && lhs.ozoneTint == rhs.ozoneTint
            && lhs.sunHaloSize == rhs.sunHaloSize
            && lhs.sunHaloIntensity == rhs.sunHaloIntensity
            && lhs.sunHaloSoftness == rhs.sunHaloSoftness
            && lhs.cloudsEnabled == rhs.cloudsEnabled
            && lhs.cloudsCoverage == rhs.cloudsCoverage
            && lhs.cloudsSoftness == rhs.cloudsSoftness
            && lhs.cloudsScale == rhs.cloudsScale
            && lhs.cloudsSpeed == rhs.cloudsSpeed
            && lhs.cloudsWindDirection == rhs.cloudsWindDirection
            && lhs.cloudsHeight == rhs.cloudsHeight
            && lhs.cloudsThickness == rhs.cloudsThickness
            && lhs.cloudsBrightness == rhs.cloudsBrightness
            && lhs.cloudsSunInfluence == rhs.cloudsSunInfluence
    }

    public static func update(scene: EngineScene) {
        let ecs = scene.ecs
        guard let (_, sky) = ecs.activeSkyLight() else {
            disableSkySunIfNeeded(in: ecs)
            return
        }
        guard sky.enabled, sky.mode == .procedural else {
            disableSkySunIfNeeded(in: ecs)
            return
        }

        // sunDir points from world origin toward the visible sun disc.
        // Directional light rays travel from sun to scene, so ray direction is -sunDir.
        let sunEntity = ecs.firstEntity(with: SkySunTag.self) ?? createSunLight(in: ecs, name: "Sun")
        let lightRayDirection = sunRayDirection(azimuthDegrees: sky.azimuthDegrees,
                                                elevationDegrees: sky.elevationDegrees)

        var light = ecs.get(LightComponent.self, for: sunEntity) ?? LightComponent(type: .directional)
        light.type = .directional
        light.direction = lightRayDirection
        light.data.color = SIMD3<Float>(repeating: 1.0)
        light.data.brightness = max(sky.intensity, 0.0)
        light.data.diffuseIntensity = 1.0
        light.data.specularIntensity = 1.0
        ecs.add(light, to: sunEntity)

        var transform = ecs.get(TransformComponent.self, for: sunEntity) ?? TransformComponent()
        transform.rotation = TransformMath.rotationForDirectionalLight(direction: lightRayDirection)
        _ = scene.transformAuthority.setLocalTransform(entity: sunEntity,
                                                       transform: transform,
                                                       source: .engineSystem)
        if ecs.get(NameComponent.self, for: sunEntity) == nil {
            ecs.add(NameComponent(name: "Sun"), to: sunEntity)
        }
    }

    private static func disableSkySunIfNeeded(in scene: SceneECS) {
        guard let sunEntity = scene.firstEntity(with: SkySunTag.self),
              var light = scene.get(LightComponent.self, for: sunEntity)
        else { return }
        light.data.brightness = 0.0
        scene.add(light, to: sunEntity)
    }

    private static func createSunLight(in scene: SceneECS, name: String) -> Entity {
        let entity = scene.createEntity(name: name)
        scene.add(SkySunTag(), to: entity)
        scene.add(LightComponent(type: .directional), to: entity)
        return entity
    }
}

// Future extensions:
// - Multiple skies: add priority/stacking and blend sky contributions.
// - Separate sun intensity: decouple sky intensity from sun light brightness.
// - Sky LUT caching: cache procedural sky cubemap by params hash.
// - Async IBL generation: move cubemap/irradiance/prefilter to background queue.
