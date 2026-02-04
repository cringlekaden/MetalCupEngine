//
//  Graphics.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

public final class Graphics {
    
    static var _shaderLibrary: ShaderLibrary!
    public static var Shaders: ShaderLibrary { return _shaderLibrary }
    static var _vertexDescriptorLibrary: VertexDescriptorLibrary!
    public static var VertexDescriptors: VertexDescriptorLibrary { return _vertexDescriptorLibrary }
    static var _renderPipelineStateLibrary: RenderPipelineStateLibrary!
    public static var RenderPipelineStates: RenderPipelineStateLibrary { return _renderPipelineStateLibrary }
    static var _depthStencilStateLibrary: DepthStencilStateLibrary!
    public static var DepthStencilStates: DepthStencilStateLibrary { return _depthStencilStateLibrary }
    static var _samplerStateLibrary: SamplerStateLibrary!
    public static var SamplerStates: SamplerStateLibrary { return _samplerStateLibrary }
    
    public static func initialize() {
        self._shaderLibrary = ShaderLibrary()
        self._vertexDescriptorLibrary = VertexDescriptorLibrary()
        self._renderPipelineStateLibrary = RenderPipelineStateLibrary()
        self._depthStencilStateLibrary = DepthStencilStateLibrary()
        self._samplerStateLibrary = SamplerStateLibrary()
    }
}
