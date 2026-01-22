//
//  PointLight.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class PointLight: LightObject {
    
    init() {
        super.init(meshType: .Sphere, name: "Point Light")
        self.setMaterialColor(SIMD4<Float>(0.5,0.5,0,1))
        self.setScale(0.2)
    }
}
