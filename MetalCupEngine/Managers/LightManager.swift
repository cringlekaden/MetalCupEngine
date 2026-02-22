/// LightManager.swift
/// Defines the LightManager types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public class LightManager {
    
    private var _lightData: [LightData] = []
    
    func setLights(_ lightData: [LightData]) {
        _lightData = lightData
    }
    
    func setLightData(_ renderCommandEncoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        let buffers = frameContext.uploadLightData(_lightData)
        renderCommandEncoder.setFragmentBuffer(buffers.countBuffer, offset: 0, index: FragmentBufferIndex.lightCount)
        renderCommandEncoder.setFragmentBuffer(buffers.dataBuffer, offset: 0, index: FragmentBufferIndex.lightData)
    }
}
