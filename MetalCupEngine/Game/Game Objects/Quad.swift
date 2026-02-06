//
//  Quad.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

class Quad: GameObject {
    
    init() {
        let handle = AssetManager.handle(forSourcePath: "Resources/quad/quad.obj")
        super.init(name: "Quad", meshHandle: handle)
        useAlbedoMapTexture(BuiltinAssets.baseColorRender)
    }
}
