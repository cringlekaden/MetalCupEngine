//
//  LightObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

class LightObject: GameObject {
    
    var lightData = LightData()
    
    init(name: String) {
        super.init(meshType: .None)
        self.setName(name)
    }
    
    init(meshType: MeshType, name: String) {
        super.init(meshType: meshType)
        self.setName(name)
    }
    
    override func update() {
        self.lightData.position = self.getPosition()
        super.update()
    }
}

extension LightObject {
    public func setLightColor(_ color: SIMD3<Float>) { self.lightData.color = color }
    public func getLightColor() -> SIMD3<Float> { return self.lightData.color }
    public func setAmbientIntensity(_ intensity: Float) { self.lightData.ambientIntensity = intensity }
    public func getAmbientIntensity() -> Float { return self.lightData.ambientIntensity }
    public func setBrightness(_ brightness: Float) { self.lightData.brightness = brightness }
    public func getBrightness() -> Float { return self.lightData.brightness }
}
