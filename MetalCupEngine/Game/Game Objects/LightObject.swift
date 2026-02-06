//
//  LightObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class LightObject: GameObject {
    
    var lightData = LightData()
    
    init(name: String) {
        super.init(name: name, meshHandle: nil)
    }
    
    override init(name: String, meshHandle: AssetHandle?) {
        super.init(name: name, meshHandle: meshHandle)
    }
    
    override func update() {
        self.lightData.position = self.getPosition()
        super.update()
    }
}

extension LightObject {
    public func setLightColor(_ r: Float, _ g: Float, _ b: Float) { setLightColor(SIMD3<Float>(r, g, b)) }
    public func setLightColor(_ color: SIMD3<Float>) { self.lightData.color = color }
    public func getLightColor() -> SIMD3<Float> { return self.lightData.color }
    public func setAmbientIntensity(_ intensity: Float) { self.lightData.ambientIntensity = intensity }
    public func getAmbientIntensity() -> Float { return self.lightData.ambientIntensity }
    public func setDiffuseIntensity(_ intensity: Float) { self.lightData.diffuseIntensity = intensity }
    public func getDiffuseIntensity() -> Float { return self.lightData.diffuseIntensity }
    public func setSpecularIntensity(_ intensity: Float) { self.lightData.specularIntensity = intensity }
    public func getSpecularIntensity() -> Float { return self.lightData.specularIntensity }
    public func setBrightness(_ brightness: Float) { self.lightData.brightness = brightness }
    public func getBrightness() -> Float { return self.lightData.brightness }
}
