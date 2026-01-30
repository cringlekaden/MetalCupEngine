//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

class Sandbox: Scene {
    
    var debugCamera = DebugCamera()
    var sphere = Sphere()
    var sofa = Sofa()
    
    override func buildScene() {
        debugCamera.setPosition(0,3,10)
        addCamera(debugCamera)
        sphere.setScale(1.5)
        sphere.setPosition(1, 0, 0)
        addChild(sphere)
        sofa.setPosition(0, -5, 0)
        sofa.setScale(5)
        addChild(sofa)
        let light = PointLight()
        light.setLightColor(0,0,0)
        addLight(light)
    }
    
    override func doUpdate() {
        if(Mouse.IsMouseButtonPressed(button: .left)){
            sofa.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
            sofa.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
        }
    }
}
