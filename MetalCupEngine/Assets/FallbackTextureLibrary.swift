/// FallbackTextureLibrary.swift
/// Centralized fallback textures for deterministic resource binding.
/// Created by Codex.

import MetalKit

public final class FallbackTextureLibrary {
    public let whiteRGBA: MTLTexture
    public let blackRGBA: MTLTexture
    public let flatNormal: MTLTexture
    public let aoMap: MTLTexture
    public let metalRoughness: MTLTexture
    public let emissive: MTLTexture
    public let blackCubemap: MTLTexture
    public let brdfLut: MTLTexture
    public let shadowMap: MTLTexture
    public let depth1x1: MTLTexture

    private let textureIds: Set<ObjectIdentifier>

    public init(device: MTLDevice, preferences: Preferences) {
        whiteRGBA = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(255, 255, 255, 255), label: "Fallback.WhiteRGBA")
        blackRGBA = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(0, 0, 0, 255), label: "Fallback.BlackRGBA")
        flatNormal = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(128, 128, 255, 255), label: "Fallback.FlatNormal")
        aoMap = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(255, 255, 255, 255), label: "Fallback.AO")
        metalRoughness = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(0, 255, 0, 255), label: "Fallback.MetalRoughness")
        emissive = FallbackTextureLibrary.makeRGBA8Texture(device: device, color: SIMD4<UInt8>(0, 0, 0, 255), label: "Fallback.Emissive")
        blackCubemap = FallbackTextureLibrary.makeSolidCubemap(device: device, preferences: preferences, color: SIMD4<Float16>(0, 0, 0, 1), label: "Fallback.BlackCubemap")
        brdfLut = FallbackTextureLibrary.makeBRDFLut(device: device, label: "Fallback.BRDFLUT")
        shadowMap = FallbackTextureLibrary.makeShadowMap(device: device, label: "Fallback.ShadowMap")
        depth1x1 = FallbackTextureLibrary.makeDepthTexture(device: device, label: "Fallback.Depth")

        textureIds = Set([
            ObjectIdentifier(whiteRGBA),
            ObjectIdentifier(blackRGBA),
            ObjectIdentifier(flatNormal),
            ObjectIdentifier(aoMap),
            ObjectIdentifier(metalRoughness),
            ObjectIdentifier(emissive),
            ObjectIdentifier(blackCubemap),
            ObjectIdentifier(brdfLut),
            ObjectIdentifier(shadowMap),
            ObjectIdentifier(depth1x1)
        ])
    }

    public func isFallbackTexture(_ texture: MTLTexture?) -> Bool {
        guard let texture else { return true }
        return textureIds.contains(ObjectIdentifier(texture))
    }

    private static func makeRGBA8Texture(device: MTLDevice, color: SIMD4<UInt8>, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = 1
        descriptor.height = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create fallback texture: \(label)")
        }
        texture.label = label
        var pixel = color
        withUnsafeBytes(of: &pixel) { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 4)
        }
        return texture
    }

    private static func makeSolidCubemap(device: MTLDevice, preferences: Preferences, color: SIMD4<Float16>, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            size: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create fallback cubemap: \(label)")
        }
        texture.label = label
        var pixel = color
        withUnsafeBytes(of: &pixel) { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            let bytesPerRow = MemoryLayout<Float16>.stride * 4
            for slice in 0..<6 {
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    slice: slice,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: bytesPerRow,
                    bytesPerImage: bytesPerRow
                )
            }
        }
        return texture
    }

    private static func makeBRDFLut(device: MTLDevice, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rg16Float
        descriptor.width = 1
        descriptor.height = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create fallback BRDF LUT")
        }
        texture.label = label
        var pixel = SIMD2<Float16>(1, 0)
        withUnsafeBytes(of: &pixel) { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: MemoryLayout<Float16>.stride * 2)
        }
        return texture
    }

    private static func makeShadowMap(device: MTLDevice, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = 1
        descriptor.height = 1
        descriptor.arrayLength = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create fallback shadow map")
        }
        texture.label = label
        var depth: Float = 1.0
        withUnsafeBytes(of: &depth) { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, slice: 0, withBytes: bytes.baseAddress!, bytesPerRow: MemoryLayout<Float>.stride, bytesPerImage: MemoryLayout<Float>.stride)
        }
        return texture
    }

    private static func makeDepthTexture(device: MTLDevice, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .r32Float
        descriptor.width = 1
        descriptor.height = 1
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create fallback depth texture")
        }
        texture.label = label
        var depth: Float = 1.0
        withUnsafeBytes(of: &depth) { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: MemoryLayout<Float>.stride)
        }
        return texture
    }
}
