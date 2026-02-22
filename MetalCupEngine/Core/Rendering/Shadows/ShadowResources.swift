/// ShadowResources.swift
/// Allocates and manages shadow map textures for the renderer.
/// Created by Codex.

import MetalKit

final class ShadowResources {
    private let device: MTLDevice
    private let preferences: Preferences
    private var shadowMap: MTLTexture?
    private var shadowResolution: Int = 0
    private var cascadeCount: Int = 0

    init(device: MTLDevice, preferences: Preferences) {
        self.device = device
        self.preferences = preferences
    }

    func ensureShadowMap(resolution: Int, cascadeCount: Int) -> MTLTexture? {
        let clampedResolution = max(256, resolution)
        let clampedCascades = max(1, min(4, cascadeCount))
        if let shadowMap, shadowResolution == clampedResolution, self.cascadeCount == clampedCascades {
            return shadowMap
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.defaultDepthPixelFormat,
            width: clampedResolution,
            height: clampedResolution,
            mipmapped: false
        )
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = clampedCascades
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "ShadowMap.DepthArray"
        shadowMap = texture
        shadowResolution = clampedResolution
        self.cascadeCount = clampedCascades
        return texture
    }
}
