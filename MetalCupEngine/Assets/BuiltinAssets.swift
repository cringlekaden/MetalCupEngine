/// BuiltinAssets.swift
/// Defines the BuiltinAssets types and helpers for the engine.
/// Created by Kaden Cringle.

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
    public static let editorPlaneMesh = AssetHandle(string: "00000000-0000-0000-0000-000000000007")

    // Renderer targets
    public static let baseColorRender = AssetHandle(string: "00000000-0000-0000-0000-000000000101")
    public static let finalColorRender = AssetHandle(string: "00000000-0000-0000-0000-000000000102")
    public static let baseDepthRender = AssetHandle(string: "00000000-0000-0000-0000-000000000103")
    public static let bloomPing = AssetHandle(string: "00000000-0000-0000-0000-000000000104")
    public static let bloomPong = AssetHandle(string: "00000000-0000-0000-0000-000000000105")
    public static let pickIdRender = AssetHandle(string: "00000000-0000-0000-0000-000000000106")
    public static let pickDepthRender = AssetHandle(string: "00000000-0000-0000-0000-000000000107")
    public static let outlineMask = AssetHandle(string: "00000000-0000-0000-0000-000000000108")
    public static let gridColor = AssetHandle(string: "00000000-0000-0000-0000-000000000109")

    // IBL textures
    public static let environmentCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000201")
    public static let irradianceCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000202")
    public static let prefilteredCubemap = AssetHandle(string: "00000000-0000-0000-0000-000000000203")
    public static let brdfLut = AssetHandle(string: "00000000-0000-0000-0000-000000000204")

    public static func registerMeshes(assetManager: AssetManager, device: MTLDevice, graphics: Graphics) {
        assetManager.registerRuntimeMesh(handle: noneMesh, mesh: NoMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: cubeMesh, mesh: CubeMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: cubemapMesh, mesh: CubemapMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: skyboxMesh, mesh: CubemapMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: fullscreenQuadMesh, mesh: FullscreenQuadMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: planeMesh, mesh: PlaneMesh(device: device, graphics: graphics, assetManager: assetManager))
        assetManager.registerRuntimeMesh(handle: editorPlaneMesh, mesh: EditorPlaneMesh(device: device, graphics: graphics, assetManager: assetManager))
    }

    public static func registerIBLTextures(assetManager: AssetManager, preferences: Preferences, device: MTLDevice, environmentSize: Int, irradianceSize: Int, prefilteredSize: Int, brdfLutSize: Int) {
        func mipCount(for size: Int) -> Int {
            guard size > 0 else { return 1 }
            return Int(floor(log2(Double(size)))) + 1
        }

        let environmentDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            size: environmentSize,
            mipmapped: true
        )
        environmentDescriptor.mipmapLevelCount = mipCount(for: environmentSize)
        environmentDescriptor.usage = [.renderTarget, .shaderRead]
        environmentDescriptor.storageMode = .private
        if let texture = device.makeTexture(descriptor: environmentDescriptor) {
            texture.label = "IBL.EnvironmentCubemap"
            assetManager.registerRuntimeTexture(handle: environmentCubemap, texture: texture)
        }

        let irradianceDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            size: irradianceSize,
            mipmapped: false
        )
        irradianceDescriptor.usage = [.renderTarget, .shaderRead]
        irradianceDescriptor.storageMode = .private
        if let texture = device.makeTexture(descriptor: irradianceDescriptor) {
            texture.label = "IBL.IrradianceCubemap"
            assetManager.registerRuntimeTexture(handle: irradianceCubemap, texture: texture)
        }

        let prefilteredDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            size: prefilteredSize,
            mipmapped: true
        )
        prefilteredDescriptor.mipmapLevelCount = mipCount(for: prefilteredSize)
        prefilteredDescriptor.usage = [.renderTarget, .shaderRead]
        prefilteredDescriptor.storageMode = .private
        if let texture = device.makeTexture(descriptor: prefilteredDescriptor) {
            texture.label = "IBL.PrefilteredCubemap"
            assetManager.registerRuntimeTexture(handle: prefilteredCubemap, texture: texture)
        }

        let brdfLUTDescriptor = MTLTextureDescriptor()
        brdfLUTDescriptor.textureType = .type2D
        brdfLUTDescriptor.pixelFormat = .rg16Float
        brdfLUTDescriptor.width = brdfLutSize
        brdfLUTDescriptor.height = brdfLutSize
        brdfLUTDescriptor.mipmapLevelCount = 1
        brdfLUTDescriptor.usage = [.renderTarget, .shaderRead]
        brdfLUTDescriptor.storageMode = .private
        if let texture = device.makeTexture(descriptor: brdfLUTDescriptor) {
            texture.label = "IBL.BRDFLUT"
            assetManager.registerRuntimeTexture(handle: brdfLut, texture: texture)
        }

    }

    public static func registerFallbackIBLTextures(assetManager: AssetManager, preferences: Preferences, device: MTLDevice) {
        if assetManager.texture(handle: environmentCubemap) == nil,
           let env = makeSolidCubemap(device: device, preferences: preferences, color: SIMD4<Float>(0, 0, 0, 1), label: "Fallback Environment") {
            assetManager.registerRuntimeTexture(handle: environmentCubemap, texture: env)
        }
        if assetManager.texture(handle: irradianceCubemap) == nil,
           let irradiance = makeSolidCubemap(device: device, preferences: preferences, color: SIMD4<Float>(0.5, 0.5, 0.5, 1), label: "Fallback Irradiance") {
            assetManager.registerRuntimeTexture(handle: irradianceCubemap, texture: irradiance)
        }
        if assetManager.texture(handle: prefilteredCubemap) == nil,
           let prefiltered = makeSolidCubemap(device: device, preferences: preferences, color: SIMD4<Float>(0, 0, 0, 1), label: "Fallback Prefiltered") {
            assetManager.registerRuntimeTexture(handle: prefilteredCubemap, texture: prefiltered)
        }
    }

    private static func makeSolidCubemap(device: MTLDevice, preferences: Preferences, color: SIMD4<Float>, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            size: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
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
