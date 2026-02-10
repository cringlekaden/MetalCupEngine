//
//  LightManager.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

public class LightManager {
    
    private var _lightData: [LightData] = []
    
    func setLights(_ lightData: [LightData]) {
        _lightData = lightData
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        var lightDatas = _lightData
        var lightCount = lightDatas.count
        renderCommandEncoder.setFragmentBytes(&lightCount, length: Int32.size, index: 3)
        renderCommandEncoder.setFragmentBytes(&lightDatas, length: LightData.stride(lightCount), index: 4)
    }
}
