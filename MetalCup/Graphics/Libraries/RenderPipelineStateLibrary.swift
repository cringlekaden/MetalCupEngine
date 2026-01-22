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
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func fillLibrary() {
        _library[.Basic] = BasicRenderPipelineState()
        _library[.Instanced] = InstancedRenderPipelineState()
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
