//
//  PointLight.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class PointLight: LightObject {
    
    init() {
        super.init(name: "Point Light", meshType: .Sphere)
        self.setMaterialColor(1,1,1,1)
        self.setScale(0.2)
    }
}
