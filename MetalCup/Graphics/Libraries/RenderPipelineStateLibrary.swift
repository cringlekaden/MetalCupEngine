//
//  RenderPipelineState.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

public enum RenderPipelineStateType {
    case Basic
    case Instanced
    case Skybox
    case Final
    case Cubemap
    case IrradianceMap
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func fillLibrary() {
        _library[.Basic] = BasicRenderPipelineState()
        _library[.Instanced] = InstancedRenderPipelineState()
        _library[.Skybox] = SkyboxRenderPipelineState()
        _library[.Final] = FinalRenderPipelineState()
        _library[.Cubemap] = CubemapRenderPipelineState()
        _library[.IrradianceMap] = IrradianceMapRenderPipelineState()
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BasicVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Basic]
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class InstancedRenderPipelineState: RenderPipelineState {
    
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultCubemapPixelFormat
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
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.defaultCubemapPixelFormat
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
