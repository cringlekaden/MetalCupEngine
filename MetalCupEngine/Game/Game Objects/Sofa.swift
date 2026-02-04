//
//  Sofa.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//

import MetalKit

class Sofa: GameObject {
    
    init() {
        super.init(name: "Sofa", meshType: .Sofa)
        setCullMode(.none)
    }
}
