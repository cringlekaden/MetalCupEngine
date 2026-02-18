/// LightManager.swift
/// Defines the LightManager types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public class LightManager {
    
    private var _lightData: [LightData] = []
    
    func setLights(_ lightData: [LightData]) {
        _lightData = lightData
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        let buffers = RendererFrameContext.shared.uploadLightData(_lightData)
        guard let countBuffer = buffers.countBuffer else { return }
        renderCommandEncoder.setFragmentBuffer(countBuffer, offset: 0, index: FragmentBufferIndex.lightCount)
        if let dataBuffer = buffers.dataBuffer {
            renderCommandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: FragmentBufferIndex.lightData)
        }
    }
}
