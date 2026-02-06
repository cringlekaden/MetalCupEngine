//
//  AssetManager.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import Foundation
import MetalKit

public final class AssetManager {
    private static var textureCache: [AssetHandle: MTLTexture] = [:]
    private static var meshCache: [AssetHandle: MCMesh] = [:]
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
        switch metadata?.type {
        case .environment:
            options[.SRGB] = false
            options[.generateMipmaps] = false
        case .texture:
            options[.SRGB] = true
            options[.generateMipmaps] = true
        default:
            break
        }
        do {
            let texture = try loader.newTexture(URL: url, options: options)
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
            default:
                break
            }
        }
    }

    public static func clearCache() {
        textureCache = textureCache.filter { runtimeTextureHandles.contains($0.key) }
        meshCache = meshCache.filter { runtimeMeshHandles.contains($0.key) }
    }
}
