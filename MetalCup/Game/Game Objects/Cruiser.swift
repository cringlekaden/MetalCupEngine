//
//  Cruiser.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class Cruiser: GameObject {
    
    init() {
        super.init(meshType: .Cruiser)
        super.setName("Cruiser")
        setTexture(textureType: .Cruiser)
//        setColor(SIMD4<Float>(0,1,0.5,1))
    }
}
