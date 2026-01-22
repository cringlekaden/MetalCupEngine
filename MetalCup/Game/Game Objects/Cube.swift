//
//  Cube.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

class Cube: GameObject {
    
    init() {
        super.init(name: "Cube", meshType: .CubeCustom)
    }
    
    override func doUpdate() {
        self.rotateX(GameTime.DeltaTime)
        self.rotateY(GameTime.DeltaTime)
    }
}
