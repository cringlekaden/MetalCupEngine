import Testing
@testable import MetalCupEngine

struct LightShadowPersistenceTests {
    @Test
    func castsShadowsPersistsThroughSceneSerialization() {
        let scene = EngineScene(
            name: "TestScene",
            environmentMapHandle: nil,
            prefabSystem: nil,
            engineContext: nil,
            shouldBuildScene: false
        )
        let entity = scene.ecs.createEntity(name: "Light")
        let light = LightComponent(
            type: .directional,
            data: LightData(),
            direction: SIMD3<Float>(0, -1, 0),
            range: 0.0,
            innerConeCos: 0.95,
            outerConeCos: 0.9,
            castsShadows: false
        )
        scene.ecs.add(light, to: entity)

        let document = scene.toDocument(rendererSettingsOverride: nil)

        let reloaded = EngineScene(
            name: "ReloadedScene",
            environmentMapHandle: nil,
            prefabSystem: nil,
            engineContext: nil,
            shouldBuildScene: false
        )
        reloaded.apply(document: document)

        let reloadedEntity = reloaded.ecs.entity(with: entity.id)
        #expect(reloadedEntity != nil)
        if let reloadedEntity {
            let reloadedLight = reloaded.ecs.get(LightComponent.self, for: reloadedEntity)
            #expect(reloadedLight?.castsShadows == false)
        }
    }
}
