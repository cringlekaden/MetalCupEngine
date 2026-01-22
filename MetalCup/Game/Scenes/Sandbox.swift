//
//  Sandbox.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

class Sandbox: Scene {
    
    var debugCamera = DebugCamera()
    var cruiser = Cruiser()
    var light1 = PointLight()
    var light2 = PointLight()
    var light3 = PointLight()
    
    override func buildScene() {
        addCamera(debugCamera)
        debugCamera.setPositionZ(6)
        light1.setPosition(SIMD3<Float>(-1,1,0))
        light1.setMaterialColor(SIMD4<Float>(1,0,0,1))
        light1.setLightColor(SIMD3<Float>(1,0,0))
        addLight(light1)
        light2.setPosition(SIMD3<Float>(0,1,0))
        light2.setMaterialColor(SIMD4<Float>(1,1,1,1))
        light2.setLightColor(SIMD3<Float>(1,1,1))
        addLight(light2)
        light3.setPosition(SIMD3<Float>(1,1,0))
        light3.setMaterialColor(SIMD4<Float>(0,0,1,1))
        light3.setLightColor(SIMD3<Float>(0,0,1))
        addLight(light3)
        cruiser.rotateX(0.3)
        light1.setMaterialIsLit(false)
        light2.setMaterialIsLit(false)
        light3.setMaterialIsLit(false)
        addChild(cruiser)
    }
    
    override func doUpdate() {
        if(Mouse.IsMouseButtonPressed(button: .left)) {
            cruiser.rotateX(Mouse.GetDY() * GameTime.DeltaTime * 0.8)
            cruiser.rotateY(Mouse.GetDX() * GameTime.DeltaTime * 0.8)
        }
    }
}
