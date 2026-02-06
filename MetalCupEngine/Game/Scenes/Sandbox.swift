//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

class Sandbox: EngineScene {
    
    private var leftMouseDown = false
    private var mouseDelta = SIMD2<Float>(0, 0)
    
    var debugCamera = DebugCamera()
    var pbrTest: GameObject?
    
    override func buildScene() {
        debugCamera.setPosition(0,3,10)
        addCamera(debugCamera)
        let light = PointLight()
        light.setLightColor(1,1,1)
        light.setPosition(5,5,5)
        light.setBrightness(5)
        addLight(light)
        if let handle = AssetManager.handle(forSourcePath: "Resources/Helmet.usdz"),
           let mesh = AssetManager.mesh(handle: handle) {
            let obj = GameObject(name: "Damaged Helmet", mesh: mesh)
            obj.setCullMode(.none)
            obj.setScale(3)
            addChild(obj)
            pbrTest = obj
        }
    }
    
    override func doUpdate() {
        leftMouseDown = Mouse.IsMouseButtonPressed(button: .left)
        let isLeftDown = leftMouseDown
        let polledDelta = SIMD2<Float>(Mouse.GetDX(), Mouse.GetDY())
        let frameMouseDelta = mouseDelta + polledDelta
        if isLeftDown, let pbrTest {
            pbrTest.rotateX(frameMouseDelta.y * GameTime.DeltaTime)
            pbrTest.rotateY(frameMouseDelta.x * GameTime.DeltaTime)
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
}
