//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

class Sandbox: Scene {
    
    var debugCamera = DebugCamera()
    var sphere = Sphere()
    var pbrTest = DamagedHelmet()
    
    override func buildScene() {
        debugCamera.setPosition(0,3,10)
        addCamera(debugCamera)
        sphere.setScale(1.5)
        sphere.setPosition(1, 0, 0)
        //addChild(sphere)
        let light = PointLight()
        light.setLightColor(0,0,0)
        addLight(light)
        pbrTest.setScale(3)
        addChild(pbrTest)
    }
    
    override func doUpdate() {
        if(Mouse.IsMouseButtonPressed(button: .left)){
            pbrTest.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
            pbrTest.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
        }
    }
}
