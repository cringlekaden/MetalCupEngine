/// Graphics.swift
/// Defines the Graphics types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public final class Graphics {
    public let shaders: ShaderLibrary
    public let vertexDescriptors: VertexDescriptorLibrary
    public let renderPipelineStates: RenderPipelineStateLibrary
    public let depthStencilStates: DepthStencilStateLibrary
    public let samplerStates: SamplerStateLibrary

    public init(resourceRegistry: ResourceRegistry, device: MTLDevice, preferences: Preferences) {
        self.shaders = ShaderLibrary(resourceRegistry: resourceRegistry, device: device, fallbackLibrary: resourceRegistry.defaultLibrary)
        self.vertexDescriptors = VertexDescriptorLibrary()
        self.renderPipelineStates = RenderPipelineStateLibrary(
            shaders: shaders,
            vertexDescriptors: vertexDescriptors,
            preferences: preferences,
            device: device
        )
        self.depthStencilStates = DepthStencilStateLibrary(device: device)
        self.samplerStates = SamplerStateLibrary(device: device)
        self.shaders.registerDefaults()
    }

    public func build() {
        renderPipelineStates.build()
    }
}
