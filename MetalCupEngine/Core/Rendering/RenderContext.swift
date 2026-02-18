/// RenderContext.swift
/// Captures per-frame render inputs and target resources.
/// Created by Kaden Cringle.

import MetalKit

public struct RenderContext {
    public var viewportSize: SIMD2<Float>
    public var renderEncoder: MTLRenderCommandEncoder?
    public var colorTarget: MTLTexture?
    public var depthTarget: MTLTexture?
    public var idTarget: MTLTexture?

    public init(viewportSize: SIMD2<Float> = .zero,
                renderEncoder: MTLRenderCommandEncoder? = nil,
                colorTarget: MTLTexture? = nil,
                depthTarget: MTLTexture? = nil,
                idTarget: MTLTexture? = nil) {
        self.viewportSize = viewportSize
        self.renderEncoder = renderEncoder
        self.colorTarget = colorTarget
        self.depthTarget = depthTarget
        self.idTarget = idTarget
    }
}
