//
//  RenderPipelineState.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

public enum RenderPipelineStateType {
    case Basic
    case HDRBasic
    case HDRInstanced
    case Skybox
    case Final
    case Cubemap
    case IrradianceMap
    case PrefilteredMap
    case BRDF
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func fillLibrary() {
        _library[.Basic] = BasicRenderPipelineState()
        _library[.HDRBasic] = HDRBasicRenderPipelineState()
        _library[.HDRInstanced] = HDRInstancedRenderPipelineState()
        _library[.Skybox] = SkyboxRenderPipelineState()
        _library[.Final] = FinalRenderPipelineState()
        _library[.Cubemap] = CubemapRenderPipelineState()
        _library[.IrradianceMap] = IrradianceMapRenderPipelineState()
        _library[.PrefilteredMap] = PrefilteredMapRenderPipelineState()
        _library[.BRDF] = BRDFRenderPipelineState()
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

class BasicRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.sRGBColorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BasicVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Basic]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class HDRBasicRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRColorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BasicVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Basic]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class HDRInstancedRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRColorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.InstancedVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Basic]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class SkyboxRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRColorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Cubemap]
        renderPipelineDescriptor.rasterSampleCount = 1
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class CubemapRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRCubemapPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.CubemapFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Cubemap]
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRCubemapPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.IrradianceFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Cubemap]
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.HDRCubemapPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.PrefilteredFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Cubemap]
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Assets.Textures[.BRDF_LUT]?.pixelFormat ?? .rg16Float
        renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FSQuadVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BRDFFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Cubemap]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class FinalRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Basic]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}
