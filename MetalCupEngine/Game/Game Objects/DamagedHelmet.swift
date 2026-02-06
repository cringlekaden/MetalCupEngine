//
//  DamagedHelmet.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/31/26.
//

import MetalKit

class DamagedHelmet: GameObject {
    
    init() {
        let handle = AssetManager.handle(forSourcePath: "Resources/Helmet.usdz")
        super.init(name: "Damaged Helmet", meshHandle: handle)
        setCullMode(.none)
    }
}
