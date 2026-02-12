//
//  BuiltinAssets.swift
//  MetalCup
//
//  Created by Kaden Cringle on 2/5/26.
//

import Foundation
import MetalKit

public enum BuiltinAssets {
    // Meshes
    public static let noneMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000001")
    public static let cubeMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000002")
    public static let cubemapMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000003")
    public static let skyboxMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000004")
    public static let fullscreenQuadMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000005")
    public static let planeMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000006")

    // Renderer targets
    public static let baseColorRender = AssetHandle(string: "00000000-0000-0000-0000-000000000101")
    public static let finalColorRender = AssetHandle(string: "00000000-0000-0000-0000-000000000102")
    public static let baseDepthRender = AssetHandle(string: "00000000-0000-0000-0000-000000000103")
    public static let bloomPing = AssetHandle(string: "00000000-0000-0000-0000-000000000104")
    public static let bloomPong = AssetHandle(string: "00000000-0000-0000-0000-000000000105")

    // IBL textures
    public static let environmentCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000201")
    public static let irradianceCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000202")
    public static let prefilteredCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000203")
    public static let brdfLut = AssetHandle(string: "00000000-0000-0000-0000-000000000204")

    public static func registerMeshes() {
        AssetManager.registerRuntimeMesh(handle: noneMesh, mesh: NoMesh())
        AssetManager.registerRuntimeMesh(handle: cubeMesh, mesh: CubeMesh())
        AssetManager.registerRuntimeMesh(handle: cubemapMesh, mesh: CubemapMesh())
        AssetManager.registerRuntimeMesh(handle: skyboxMesh, mesh: CubemapMesh())
        AssetManager.registerRuntimeMesh(handle: fullscreenQuadMesh, mesh: FullscreenQuadMesh())
        AssetManager.registerRuntimeMesh(handle: planeMesh, mesh: PlaneMesh())
    }

    public static func registerIBLTextures(environmentSize: Int, irradianceSize: Int, prefilteredSize: Int, brdfLutSize: Int) {
        let environmentDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            size: environmentSize,
            mipmapped: true
        )
        environmentDescriptor.usage = [.renderTarget, .shaderRead]
        environmentDescriptor.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: environmentDescriptor) {
            texture.label = "IBL.EnvironmentCubemap"
            AssetManager.registerRuntimeTexture(handle: environmentCubemap, texture: texture)
        }

        let irradianceDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            size: irradianceSize,
            mipmapped: false
        )
        irradianceDescriptor.usage = [.renderTarget, .shaderRead]
        irradianceDescriptor.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: irradianceDescriptor) {
            texture.label = "IBL.IrradianceCubemap"
            AssetManager.registerRuntimeTexture(handle: irradianceCubemap, texture: texture)
        }

        let prefilteredDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            size: prefilteredSize,
            mipmapped: true
        )
        prefilteredDescriptor.usage = [.renderTarget, .shaderRead]
        prefilteredDescriptor.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: prefilteredDescriptor) {
            texture.label = "IBL.PrefilteredCubemap"
            AssetManager.registerRuntimeTexture(handle: prefilteredCubemap, texture: texture)
        }

        let brdfLUTDescriptor = MTLTextureDescriptor()
        brdfLUTDescriptor.textureType = .type2D
        brdfLUTDescriptor.pixelFormat = .rg16Float
        brdfLUTDescriptor.width = brdfLutSize
        brdfLUTDescriptor.height = brdfLutSize
        brdfLUTDescriptor.mipmapLevelCount = 1
        brdfLUTDescriptor.usage = [.renderTarget, .shaderRead]
        brdfLUTDescriptor.storageMode = .private
        if let texture = Engine.Device.makeTexture(descriptor: brdfLUTDescriptor) {
            texture.label = "IBL.BRDFLUT"
            AssetManager.registerRuntimeTexture(handle: brdfLut, texture: texture)
        }
    }

    public static func registerFallbackIBLTextures() {
        if let env = makeSolidCubemap(color: SIMD4<Float>(0, 0, 0, 1), label: "Fallback Environment") {
            AssetManager.registerRuntimeTexture(handle: environmentCubemap, texture: env)
        }
        if let irradiance = makeSolidCubemap(color: SIMD4<Float>(0.5, 0.5, 0.5, 1), label: "Fallback Irradiance") {
            AssetManager.registerRuntimeTexture(handle: irradianceCubemap, texture: irradiance)
        }
        if let prefiltered = makeSolidCubemap(color: SIMD4<Float>(0, 0, 0, 1), label: "Fallback Prefiltered") {
            AssetManager.registerRuntimeTexture(handle: prefilteredCubemap, texture: prefiltered)
        }
    }

    private static func makeSolidCubemap(color: SIMD4<Float>, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            size: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = Engine.Device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label

        let pixel: [Float16] = [
            Float16(color.x),
            Float16(color.y),
            Float16(color.z),
            Float16(color.w)
        ]
        pixel.withUnsafeBytes { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1))
            let bytesPerRow = MemoryLayout<Float16>.stride * 4
            let bytesPerImage = bytesPerRow
            for slice in 0..<6 {
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    slice: slice,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: bytesPerRow,
                    bytesPerImage: bytesPerImage
                )
            }
        }
        return texture
    }
}
