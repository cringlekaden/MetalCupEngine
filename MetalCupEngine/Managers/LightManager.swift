//
//  LightManager.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

public class LightManager {
    
    private var _lights: [LightObject] = []
    
    func addLight(_ light: LightObject) {
        _lights.append(light)
    }
    
    func getLightData()->[LightData] {
        _lights.map(\.lightData)
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var lightDatas = getLightData()
        var lightCount = lightDatas.count
        renderCommandEncoder.setFragmentBytes(&lightCount, length: Int32.size, index: 3)
        renderCommandEncoder.setFragmentBytes(&lightDatas, length: LightData.stride(lightCount), index: 4)
    }
}
