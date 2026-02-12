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
        var lightCount = Int32(_lightData.count)
        renderCommandEncoder.setFragmentBytes(&lightCount, length: Int32.size, index: FragmentBufferIndex.lightCount)
        if _lightData.isEmpty {
            var fallback = LightData()
            renderCommandEncoder.setFragmentBytes(&fallback, length: LightData.stride, index: FragmentBufferIndex.lightData)
            return
        }
        _lightData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            renderCommandEncoder.setFragmentBytes(baseAddress, length: bytes.count, index: FragmentBufferIndex.lightData)
        }
    }
}
