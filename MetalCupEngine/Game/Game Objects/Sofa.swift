//
//  Sofa.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//

import MetalKit

class Sofa: GameObject {
    
    init() {
        let handle = AssetManager.handle(forSourcePath: "Resources/sofa_03_2k/sofa_03_2k.obj")
        super.init(name: "Sofa", meshHandle: handle)
        setCullMode(.none)
    }
}
