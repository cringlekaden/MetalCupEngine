/// RenderOutputs.swift
/// Describes renderer outputs produced for a frame.
/// Created by Kaden Cringle.

import MetalKit

public struct RenderOutputs {
    public var color: MTLTexture?
    public var depth: MTLTexture?
    public var pickingId: MTLTexture?

    public init(color: MTLTexture? = nil,
                depth: MTLTexture? = nil,
                pickingId: MTLTexture? = nil) {
        self.color = color
        self.depth = depth
        self.pickingId = pickingId
    }
}
