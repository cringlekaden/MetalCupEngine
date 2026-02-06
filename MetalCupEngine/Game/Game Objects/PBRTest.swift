//
//  PBRTest.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/30/26.
//

import MetalKit

class PBRTest: GameObject {
    
    init() {
        let handle = AssetManager.handle(forSourcePath: "Resources/PBR_test.usdz")
        super.init(name: "PBRTest", meshHandle: handle)
    }
}
