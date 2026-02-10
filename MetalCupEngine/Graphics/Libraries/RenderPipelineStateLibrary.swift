//
//  RenderPipelineState.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

public enum RenderPipelineStateType {
    case HDRBasic
    case HDRInstanced
    case Skybox
    case Final
    case Cubemap
    case IrradianceMap
    case PrefilteredMap
    case BRDF
    case BloomExtract
    case BloomDownsample
    case BloomBlurH
    case BloomBlurV
    case ProceduralSkyCubemap
}

public class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    public func build() {
        if !_library.isEmpty { return }
        _library[.HDRBasic] = HDRBasicRenderPipelineState()
        _library[.HDRInstanced] = HDRInstancedRenderPipelineState()
        _library[.Skybox] = SkyboxRenderPipelineState()
        _library[.Final] = FinalRenderPipelineState()
        _library[.Cubemap] = CubemapRenderPipelineState()
        _library[.IrradianceMap] = IrradianceMapRenderPipelineState()
        _library[.PrefilteredMap] = PrefilteredMapRenderPipelineState()
        _library[.BRDF] = BRDFRenderPipelineState()
        _library[.BloomExtract] = BloomExtractRenderPipelineState()
        _library[.BloomDownsample] = BloomDownsampleRenderPipelineState()
        _library[.BloomBlurH] = BloomBlurHRenderPipelineState()
        _library[.BloomBlurV] = BloomBlurVRenderPipelineState()
        _library[.ProceduralSkyCubemap] = ProceduralSkyCubemapRenderPipelineState()
    }
    
    override subscript(_ type: RenderPipelineStateType)->MTLRenderPipelineState {
        return _library[type]!.renderPipelineState
    }
}

class RenderPipelineState {
    
    var renderPipelineState: MTLRenderPipelineState!
    
    init(renderPipelineDescriptor: MTLRenderPipelineDescriptor) {
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch let error as NSError {
            print("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error)")
        }
    }
}

class HDRBasicRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BasicVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class HDRInstancedRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.InstancedVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class SkyboxRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class CubemapRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.CubemapFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class ProceduralSkyCubemapRenderPipelineState: RenderPipelineState {

    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.ProceduralSkyFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class IrradianceMapRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.IrradianceFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class PrefilteredMapRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.PrefilteredFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BRDFRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .rg16Float
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FSQuadVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BRDFFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BloomExtractRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BloomExtractFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BloomDownsampleRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BloomDownsampleFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BloomBlurHRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BlurHFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BloomBlurVRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BlurVFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class FinalRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}
