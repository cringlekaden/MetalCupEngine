//
//  Sphere.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//

class Sphere: GameObject {
    
    init() {
        let handle = AssetManager.handle(forSourcePath: "Resources/sphere/sphere.obj")
        super.init(name: "Sphere", meshHandle: handle)
    }
}
