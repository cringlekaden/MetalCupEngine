//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import Foundation
import MetalKit
import simd

class Sandbox: EngineScene {
    
    private var leftMouseDown = false
    private var mouseDelta = SIMD2<Float>(0, 0)
    
    var debugCamera = DebugCamera()
    var pbrTest: Entity?
    var groundPlane: Entity?
    var pointLightEntity: Entity?
    var pointLightEntityB: Entity?
    var spotLightEntity: Entity?
    var spotLightEntityB: Entity?
    var directionalLightEntity: Entity?
    private var lightMarkers: [Entity] = []
    
    override func buildScene() {
        debugCamera.setPosition(0,3,10)
        addCamera(debugCamera)

        let skyEntity = ecs.createEntity(name: "Sky")
        var sky = SkyLightComponent()
        sky.mode = .hdri
        sky.hdriHandle = environmentMapHandle
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
    }
    
    override func doUpdate() {
        updateLights()
        leftMouseDown = Mouse.IsMouseButtonPressed(button: .left)
        let isLeftDown = leftMouseDown
        let polledDelta = SIMD2<Float>(Mouse.GetDX(), Mouse.GetDY())
        let frameMouseDelta = mouseDelta + polledDelta
        if isLeftDown, let pbrTest, var transform = ecs.get(TransformComponent.self, for: pbrTest) {
            transform.rotation.x += frameMouseDelta.y * GameTime.DeltaTime
            transform.rotation.y += frameMouseDelta.x * GameTime.DeltaTime
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
        addLightMarker(color: light.data.color, position: startPosition)
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
        addLightMarker(color: light.data.color, position: startPosition)
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
        addLightMarker(color: light.data.color, position: startPosition)
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
        addLightMarker(color: light.data.color, position: startPosition)
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

    private func updateLights() {
        let t = GameTime.TotalGameTime

        if let pointLightEntity, var transform = ecs.get(TransformComponent.self, for: pointLightEntity) {
            let radius: Float = 7
            transform.position = SIMD3<Float>(cos(t * 0.8) * radius, 4.5, sin(t * 0.8) * radius)
            ecs.add(transform, to: pointLightEntity)
            updateMarker(index: 0, position: transform.position)
        }

        if let pointLightEntityB, var transform = ecs.get(TransformComponent.self, for: pointLightEntityB) {
            let radius: Float = 5
            transform.position = SIMD3<Float>(cos(t * 1.1 + 1.5) * radius, 3.5, sin(t * 1.1 + 1.5) * radius)
            ecs.add(transform, to: pointLightEntityB)
            updateMarker(index: 1, position: transform.position)
        }

        if let spotLightEntity,
           var transform = ecs.get(TransformComponent.self, for: spotLightEntity),
           var light = ecs.get(LightComponent.self, for: spotLightEntity) {
            let radius: Float = 9
            transform.position = SIMD3<Float>(cos(t * 0.6) * radius, 8.5, sin(t * 0.6) * radius)
            light.direction = normalize(SIMD3<Float>(-transform.position.x, -2.0, -transform.position.z))
            ecs.add(transform, to: spotLightEntity)
            ecs.add(light, to: spotLightEntity)
            updateMarker(index: 2, position: transform.position)
        }

        if let spotLightEntityB,
           var transform = ecs.get(TransformComponent.self, for: spotLightEntityB),
           var light = ecs.get(LightComponent.self, for: spotLightEntityB) {
            let radius: Float = 6
            transform.position = SIMD3<Float>(cos(t * 0.9 + 2.2) * radius, 6.5, sin(t * 0.9 + 2.2) * radius)
            light.direction = normalize(SIMD3<Float>(-transform.position.x, -1.6, -transform.position.z))
            ecs.add(transform, to: spotLightEntityB)
            ecs.add(light, to: spotLightEntityB)
            updateMarker(index: 3, position: transform.position)
        }

        if let directionalLightEntity,
           ecs.get(SkySunTag.self, for: directionalLightEntity) == nil,
           var light = ecs.get(LightComponent.self, for: directionalLightEntity) {
            let angle = t * 0.15
            light.direction = normalize(SIMD3<Float>(cos(angle) * 0.7, -1, sin(angle) * 0.7))
            ecs.add(light, to: directionalLightEntity)
        }
    }

    private func addLightMarker(color: SIMD3<Float>, position: SIMD3<Float>) {
        guard let meshHandle = AssetManager.handle(forSourcePath: "sphere/sphere.obj"),
              AssetManager.mesh(handle: meshHandle) != nil else { return }
        let entity = ecs.createEntity(name: "Light Marker")
        var transform = TransformComponent(position: position, scale: SIMD3<Float>(repeating: 0.2))
        ecs.add(transform, to: entity)
        var material = MetalCupMaterial()
        material.baseColor = color
        material.emissiveColor = color
        material.emissiveScalar = 2.0
        material.flags = (MetalCupMaterialFlags.isUnlit.rawValue | MetalCupMaterialFlags.hasBaseColorMap.rawValue)
        ecs.add(MeshRendererComponent(meshHandle: meshHandle, material: material), to: entity)
        lightMarkers.append(entity)
    }

    private func updateMarker(index: Int, position: SIMD3<Float>) {
        guard index >= 0, index < lightMarkers.count else { return }
        let entity = lightMarkers[index]
        if var transform = ecs.get(TransformComponent.self, for: entity) {
            transform.position = position
            ecs.add(transform, to: entity)
        }
    }
}
