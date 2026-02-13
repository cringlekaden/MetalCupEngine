/// AssetManager.swift
/// Defines the AssetManager types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import MetalKit

/// Engine-side runtime cache for GPU assets resolved via an AssetDatabase.
public final class AssetManager {
    private static var textureCache: [AssetHandle: MTLTexture] = [:]
    private static var meshCache: [AssetHandle: MCMesh] = [:]
    private static var materialCache: [AssetHandle: MaterialAsset] = [:]
    private static var materialCacheModified: [AssetHandle: TimeInterval] = [:]
    private static var runtimeTextureHandles = Set<AssetHandle>()
    private static var runtimeMeshHandles = Set<AssetHandle>()

    public static func handle(forSourcePath sourcePath: String) -> AssetHandle? {
        guard let database = Engine.assetDatabase else { return nil }
        if let direct = database.metadata(forSourcePath: sourcePath)?.handle {
            return direct
        }
        let normalized = sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasPrefix("Resources/") {
            let stripped = String(normalized.dropFirst("Resources/".count))
            if let handle = database.metadata(forSourcePath: stripped)?.handle {
                return handle
            }
        }
        if normalized.hasPrefix("Assets/") {
            let stripped = String(normalized.dropFirst("Assets/".count))
            if let handle = database.metadata(forSourcePath: stripped)?.handle {
                return handle
            }
        }
        let filename = URL(fileURLWithPath: normalized).lastPathComponent
        for metadata in database.allMetadata() {
            if URL(fileURLWithPath: metadata.sourcePath).lastPathComponent == filename {
                return metadata.handle
            }
        }
        return nil
    }

    public static func texture(handle: AssetHandle) -> MTLTexture? {
        if let cached = textureCache[handle] {
            return cached
        }
        guard let database = Engine.assetDatabase,
              let url = database.assetURL(for: handle) else { return nil }
        let loader = MTKTextureLoader(device: Engine.Device)
        let metadata = database.metadata(for: handle)
        var options: [MTKTextureLoader.Option: Any] = [.origin: MTKTextureLoader.Origin.topLeft]
        let sourcePath = metadata?.sourcePath ?? url.lastPathComponent
        switch metadata?.type {
        case .environment:
            options[.SRGB] = false
            options[.generateMipmaps] = false
        case .texture:
            options[.SRGB] = AssetManager.isColorTexture(path: sourcePath)
            let shouldMipmap = AssetManager.shouldGenerateMipmaps(path: sourcePath)
            options[.generateMipmaps] = shouldMipmap
            options[.allocateMipmaps] = shouldMipmap
        default:
            break
        }
        do {
            let texture = try loader.newTexture(URL: url, options: options)
            if metadata?.type == .texture,
               AssetManager.shouldGenerateMipmaps(path: sourcePath) {
                ensureMipmaps(texture)
            }
            textureCache[handle] = texture
            return texture
        } catch {
            print("ERROR::ASSET::TEXTURE::__\(url.lastPathComponent)__::\(error)")
            return nil
        }
    }

    public static func mesh(handle: AssetHandle) -> MCMesh? {
        if let cached = meshCache[handle] {
            return cached
        }
        guard let url = Engine.assetDatabase?.assetURL(for: handle) else { return nil }
        let mesh = MCMesh(assetURL: url)
        meshCache[handle] = mesh
        return mesh
    }

    public static func material(handle: AssetHandle) -> MaterialAsset? {
        guard let database = Engine.assetDatabase,
              let url = database.assetURL(for: handle) else { return nil }
        let lastModified = database.metadata(for: handle)?.lastModified ?? 0
        if let cached = materialCache[handle],
           materialCacheModified[handle] == lastModified {
            return cached
        }

        if let material = MaterialAssetSerializer.load(from: url, fallbackHandle: handle) {
            let wasCached = materialCache[handle] != nil
            materialCache[handle] = material
            materialCacheModified[handle] = lastModified
            let action = wasCached ? "RELOAD" : "LOAD"
            print("INFO::ASSET::MATERIAL::\(action)::\(url.lastPathComponent)")
            return material
        }
        return nil
    }

    public static func registerRuntimeTexture(handle: AssetHandle, texture: MTLTexture) {
        textureCache[handle] = texture
        runtimeTextureHandles.insert(handle)
    }

    public static func registerRuntimeMesh(handle: AssetHandle, mesh: MCMesh) {
        meshCache[handle] = mesh
        runtimeMeshHandles.insert(handle)
    }

    public static func preload(from database: AssetDatabase) {
        for metadata in database.allMetadata() {
            switch metadata.type {
            case .texture, .environment:
                _ = texture(handle: metadata.handle)
            case .model:
                _ = mesh(handle: metadata.handle)
            case .material:
                _ = material(handle: metadata.handle)
            default:
                break
            }
        }
    }

    public static func clearCache() {
        textureCache = textureCache.filter { runtimeTextureHandles.contains($0.key) }
        meshCache = meshCache.filter { runtimeMeshHandles.contains($0.key) }
        materialCache.removeAll()
        materialCacheModified.removeAll()
    }

    public static func isColorTexture(path: String) -> Bool {
        let name = path.lowercased()
        if name.contains("normal")
            || name.contains("rough")
            || name.contains("metal")
            || name.contains("ao")
            || name.contains("occlusion")
            || name.contains("height")
            || name.contains("mask") {
            return false
        }
        if name.contains("albedo")
            || name.contains("diff")
            || name.contains("basecolor")
            || name.contains("emissive") {
            return true
        }
        return true
    }

    public static func shouldGenerateMipmaps(path: String) -> Bool {
        let name = path.lowercased()
        if isColorTexture(path: name) {
            return true
        }
        if name.contains("normal")
            || name.contains("rough")
            || name.contains("metal")
            || name.contains("metallic") {
            return true
        }
        return false
    }

    public static func shouldFlipNormalY(path: String) -> Bool {
        let name = path.lowercased()
        return name.contains("normal-ogl") || name.contains("_ogl") || name.contains("opengl") || name.contains("nor_gl")
    }

    private static func ensureMipmaps(_ texture: MTLTexture) {
        guard texture.mipmapLevelCount > 1 else { return }
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Generate Mipmaps"
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
        }
    }
}
