//
//  DamagedHelmet.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/31/26.
//

import MetalKit

class DamagedHelmet: GameObject {
    
    init() {
        super.init(name: "Damaged Helmet", meshType: .DamagedHelmet)
        setCullMode(.none)
    }
}
