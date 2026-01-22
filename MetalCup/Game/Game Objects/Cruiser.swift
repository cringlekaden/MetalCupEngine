//
//  Cruiser.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class Cruiser: GameObject {
    
    init() {
        super.init(name: "Cruiser", meshType: .Cruiser)
        setTexture(textureType: .Cruiser)
    }
}
