//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

class Sandbox: Scene {
    
    var debugCamera = DebugCamera()
    var cruiser = Cruiser()
    var leftSun = PointLight()
    var middleSun = PointLight()
    var rightSun = PointLight()
    
    override func buildScene() {
        debugCamera.setPosition(0,0,6)
        addCamera(debugCamera)
        leftSun.setPosition(-1, 1, 0)
        //leftSun.setMaterialIsLit(false)
        leftSun.setMaterialColor(1,0,0,1)
        leftSun.setLightColor(1,0,0)
        addLight(leftSun)
        middleSun.setPosition(0, 1, 0)
        //middleSun.setMaterialIsLit(false)
        middleSun.setBrightness(0.3)
        middleSun.setMaterialColor(1,1,1,1)
        middleSun.setLightColor(1,1,1)
        addLight(middleSun)
        rightSun.setPosition(1, 1, 0)
        //rightSun.setMaterialIsLit(false)
        rightSun.setMaterialColor(0,0,1,1)
        rightSun.setLightColor(0,0,1)
        addLight(rightSun)
        cruiser.setMaterialAmbient(0.01)
        cruiser.setRotationX(0.3)
        addChild(cruiser)
    }
    
    override func doUpdate() {
        if(Mouse.IsMouseButtonPressed(button: .left)){
            cruiser.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
            cruiser.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
        }
    }
}
