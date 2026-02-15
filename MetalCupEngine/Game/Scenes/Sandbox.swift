/// Sandbox.swift
/// Defines the Sandbox types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import MetalKit
import simd

class Sandbox: EngineScene {
    
    private var leftMouseDown = false
    private var mouseDelta = SIMD2<Float>(0, 0)
    
    var pbrTest: Entity?
    var groundPlane: Entity?
    var pointLightEntity: Entity?
    var pointLightEntityB: Entity?
    var spotLightEntity: Entity?
    var spotLightEntityB: Entity?
    var directionalLightEntity: Entity?
    var pointLightMarker: Entity?
    var pointLightMarkerB: Entity?
    var spotLightMarker: Entity?
    var spotLightMarkerB: Entity?
    
    override func buildScene() {
        let cameraEntity = ecs.createEntity(name: "Editor Camera")
        ecs.add(TransformComponent(position: SIMD3<Float>(0, 3, 10)), to: cameraEntity)
        ecs.add(CameraComponent(isPrimary: true, isEditor: true), to: cameraEntity)

        let skyEntity = ecs.createEntity(name: "Sky")
        var sky = SkyLightComponent()
        sky.mode = .procedural
        sky.hdriHandle = nil
        sky.needsRegenerate = true
        ecs.add(sky, to: skyEntity)
        ecs.add(SkyLightTag(), to: skyEntity)

        pointLightEntity = createPointLight()
        pointLightEntityB = createPointLightB()
        spotLightEntity = createSpotLight()
        spotLightEntityB = createSpotLightB()
        directionalLightEntity = createDirectionalLight()

        createGroundPlane()
        if let handle = AssetManager.handle(forSourcePath: "Resources/Helmet.usdz"),
           AssetManager.mesh(handle: handle) != nil {
            let entity = ecs.createEntity(name: "Damaged Helmet")
            var transform = TransformComponent()
            transform.scale = SIMD3<Float>(repeating: 3)
            transform.position.y = 5
            ecs.add(transform, to: entity)
            var material = MetalCupMaterial()
            material.emissiveScalar = 25.0
            ecs.add(MeshRendererComponent(meshHandle: handle, material: material), to: entity)
            pbrTest = entity
        }
        if let handle = AssetManager.handle(forSourcePath: "Resources/PBR_test.usdz"),
           AssetManager.mesh(handle: handle) != nil {
            let entity = ecs.createEntity(name: "PBR Test")
            var transform = TransformComponent()
            transform.scale = SIMD3<Float>(repeating: 3)
            transform.position = SIMD3<Float>(-8, 7, 0)
            ecs.add(transform, to: entity)
            ecs.add(MeshRendererComponent(meshHandle: handle), to: entity)
        }

        applyLightOrbits(centerEntity: pbrTest)
    }
    
    override func doUpdate() {
        leftMouseDown = Mouse.IsMouseButtonPressed(button: .left)
        let isLeftDown = leftMouseDown
        let polledDelta = SIMD2<Float>(Mouse.GetDX(), Mouse.GetDY())
        let frameMouseDelta = mouseDelta + polledDelta
        if isLeftDown, let pbrTest, var transform = ecs.get(TransformComponent.self, for: pbrTest) {
            transform.rotation.x += frameMouseDelta.y * Time.DeltaTime
            transform.rotation.y += frameMouseDelta.x * Time.DeltaTime
            ecs.add(transform, to: pbrTest)
        }
        // consume per-frame delta
        mouseDelta = .zero
    }
    
    override func onEvent(_ event: Event) {
        switch event {
        case let e as MouseButtonPressedEvent:
            if e.button == 0 { leftMouseDown = true }
        case let e as MouseButtonReleasedEvent:
            if e.button == 0 { leftMouseDown = false }
        case let e as MouseMovedEvent:
            mouseDelta += e.delta
        default:
            break
        }
        super.onEvent(event)
    }

    private func createGroundPlane() {
        let meshHandle = BuiltinAssets.planeMesh
        guard AssetManager.mesh(handle: meshHandle) != nil else { return }
        let entity = ecs.createEntity(name: "Ground")
        var transform = TransformComponent()
        transform.scale = SIMD3<Float>(repeating: 100)
        ecs.add(transform, to: entity)

        let albedo = AssetManager.handle(forSourcePath: "mortar-stonework/thick-mortar-stonework_albedo.png")
        let normal = AssetManager.handle(forSourcePath: "mortar-stonework/thick-mortar-stonework_normal-ogl.png")
        let metallic = AssetManager.handle(forSourcePath: "mortar-stonework/thick-mortar-stonework_metallic.png")
        let roughness = AssetManager.handle(forSourcePath: "mortar-stonework/thick-mortar-stonework_roughness.png")
        let ao = AssetManager.handle(forSourcePath: "mortar-stonework/thick-mortar-stonework_ao.png")

        var flags = MetalCupMaterialFlags()
        if albedo != nil { flags.insert(.hasBaseColorMap) }
        if normal != nil { flags.insert(.hasNormalMap) }
        if metallic != nil { flags.insert(.hasMetallicMap) }
        if roughness != nil { flags.insert(.hasRoughnessMap) }
        if ao != nil { flags.insert(.hasAOMap) }
        var material = MetalCupMaterial()
        material.flags = flags.rawValue

        ecs.add(
            MeshRendererComponent(
                meshHandle: meshHandle,
                material: material,
                albedoMapHandle: albedo,
                normalMapHandle: normal,
                metallicMapHandle: metallic,
                roughnessMapHandle: roughness,
                aoMapHandle: ao
            ),
            to: entity
        )
        groundPlane = entity
    }

    private func createPointLight() -> Entity {
        let entity = ecs.createEntity(name: "Point Light")
        var light = LightComponent(type: .point)
        light.data.color = SIMD3<Float>(1.0, 0.25, 0.25)
        light.data.brightness = 18
        light.range = 18
        let startPosition = SIMD3<Float>(6, 4, 4)
        ecs.add(TransformComponent(position: startPosition), to: entity)
        ecs.add(light, to: entity)
        pointLightMarker = addLightMarker(color: light.data.color, position: startPosition)
        return entity
    }

    private func createPointLightB() -> Entity {
        let entity = ecs.createEntity(name: "Point Light B")
        var light = LightComponent(type: .point)
        light.data.color = SIMD3<Float>(0.2, 0.6, 1.0)
        light.data.brightness = 14
        light.range = 16
        let startPosition = SIMD3<Float>(-6, 3, -4)
        ecs.add(TransformComponent(position: startPosition), to: entity)
        ecs.add(light, to: entity)
        pointLightMarkerB = addLightMarker(color: light.data.color, position: startPosition)
        return entity
    }

    private func createSpotLight() -> Entity {
        let entity = ecs.createEntity(name: "Spot Light")
        var light = LightComponent(type: .spot)
        light.data.color = SIMD3<Float>(1.0, 0.85, 0.35)
        light.data.brightness = 22
        light.range = 22
        light.innerConeCos = cos(Float(12).toRadians)
        light.outerConeCos = cos(Float(22).toRadians)
        let startPosition = SIMD3<Float>(0, 9, 0)
        ecs.add(TransformComponent(position: startPosition), to: entity)
        ecs.add(light, to: entity)
        spotLightMarker = addLightMarker(color: light.data.color, position: startPosition)
        return entity
    }

    private func createSpotLightB() -> Entity {
        let entity = ecs.createEntity(name: "Spot Light B")
        var light = LightComponent(type: .spot)
        light.data.color = SIMD3<Float>(0.6, 1.0, 0.6)
        light.data.brightness = 18
        light.range = 18
        light.innerConeCos = cos(Float(18).toRadians)
        light.outerConeCos = cos(Float(30).toRadians)
        let startPosition = SIMD3<Float>(4, 6, -8)
        ecs.add(TransformComponent(position: startPosition), to: entity)
        ecs.add(light, to: entity)
        spotLightMarkerB = addLightMarker(color: light.data.color, position: startPosition)
        return entity
    }

    private func createDirectionalLight() -> Entity {
        let entity = ecs.createEntity(name: "Directional Light")
        var light = LightComponent(type: .directional)
        light.data.color = SIMD3<Float>(0.75, 0.85, 1.0)
        light.data.brightness = 0.6
        light.direction = SIMD3<Float>(-0.6, -1.0, -0.3)
        ecs.add(light, to: entity)
        ecs.add(SkySunTag(), to: entity)
        return entity
    }

    private func addLightMarker(color: SIMD3<Float>, position: SIMD3<Float>) -> Entity? {
        guard let meshHandle = AssetManager.handle(forSourcePath: "sphere/sphere.obj"),
              AssetManager.mesh(handle: meshHandle) != nil else { return nil }
        let entity = ecs.createEntity(name: "Light Marker")
        let transform = TransformComponent(position: position, scale: SIMD3<Float>(repeating: 0.2))
        ecs.add(transform, to: entity)
        var material = MetalCupMaterial()
        material.baseColor = color
        material.emissiveColor = color
        material.emissiveScalar = 2.0
        material.flags = (MetalCupMaterialFlags.isUnlit.rawValue | MetalCupMaterialFlags.hasBaseColorMap.rawValue)
        ecs.add(MeshRendererComponent(meshHandle: meshHandle, material: material), to: entity)
        return entity
    }

    private func applyLightOrbits(centerEntity: Entity?) {
        applyLightOrbit(
            to: pointLightEntity,
            center: centerEntity,
            radius: 7,
            speed: 0.8,
            height: 4.5,
            phase: 0.0
        )
        applyLightOrbit(
            to: pointLightMarker,
            center: centerEntity,
            radius: 7,
            speed: 0.8,
            height: 4.5,
            phase: 0.0,
            affectsDirection: false
        )
        applyLightOrbit(
            to: pointLightEntityB,
            center: centerEntity,
            radius: 5,
            speed: 1.1,
            height: 3.5,
            phase: 1.5
        )
        applyLightOrbit(
            to: pointLightMarkerB,
            center: centerEntity,
            radius: 5,
            speed: 1.1,
            height: 3.5,
            phase: 1.5,
            affectsDirection: false
        )
        applyLightOrbit(
            to: spotLightEntity,
            center: centerEntity,
            radius: 9,
            speed: 0.6,
            height: 8.5,
            phase: 0.0
        )
        applyLightOrbit(
            to: spotLightMarker,
            center: centerEntity,
            radius: 9,
            speed: 0.6,
            height: 8.5,
            phase: 0.0,
            affectsDirection: false
        )
        applyLightOrbit(
            to: spotLightEntityB,
            center: centerEntity,
            radius: 6,
            speed: 0.9,
            height: 6.5,
            phase: 2.2
        )
        applyLightOrbit(
            to: spotLightMarkerB,
            center: centerEntity,
            radius: 6,
            speed: 0.9,
            height: 6.5,
            phase: 2.2,
            affectsDirection: false
        )
        applyLightOrbit(
            to: directionalLightEntity,
            center: centerEntity,
            radius: 0.7,
            speed: 0.15,
            height: -1.0,
            phase: 0.0
        )
    }

    private func applyLightOrbit(
        to entity: Entity?,
        center: Entity?,
        radius: Float,
        speed: Float,
        height: Float,
        phase: Float,
        affectsDirection: Bool = true
    ) {
        guard let entity else { return }
        let orbit = LightOrbitComponent(
            centerEntityId: center?.id,
            radius: radius,
            speed: speed,
            height: height,
            phase: phase,
            affectsDirection: affectsDirection
        )
        ecs.add(orbit, to: entity)
    }
}
