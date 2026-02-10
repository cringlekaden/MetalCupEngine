import Foundation
import simd

public enum SkySystem {
    public static func sunDirection(azimuthDegrees: Float, elevationDegrees: Float) -> SIMD3<Float> {
        let azimuth = azimuthDegrees * Float.pi / 180.0
        let elevation = elevationDegrees * Float.pi / 180.0
        let cosEl = cos(elevation)
        let dir = SIMD3<Float>(
            cosEl * sin(azimuth),
            -sin(elevation),
            cosEl * cos(azimuth)
        )
        return simd_normalize(dir)
    }

    public static func update(scene: SceneECS) {
        guard let (_, sky) = scene.activeSkyLight() else {
            disableSkySunIfNeeded(in: scene)
            return
        }
        guard sky.enabled, sky.mode == .procedural else {
            disableSkySunIfNeeded(in: scene)
            return
        }

        let sunDir = sunDirection(azimuthDegrees: sky.azimuthDegrees, elevationDegrees: sky.elevationDegrees)
        let sunEntity = scene.firstEntity(with: SkySunTag.self) ?? createSunLight(in: scene, name: "Sun")

        var light = scene.get(LightComponent.self, for: sunEntity) ?? LightComponent(type: .directional)
        light.type = .directional
        light.direction = sunDir
        light.data.color = SIMD3<Float>(repeating: 1.0)
        light.data.brightness = max(sky.intensity, 0.0)
        light.data.diffuseIntensity = 1.0
        light.data.specularIntensity = 1.0
        scene.add(light, to: sunEntity)

        if scene.get(TransformComponent.self, for: sunEntity) == nil {
            scene.add(TransformComponent(), to: sunEntity)
        }
        if scene.get(NameComponent.self, for: sunEntity) == nil {
            scene.add(NameComponent(name: "Sun"), to: sunEntity)
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
