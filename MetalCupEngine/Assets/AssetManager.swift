/// AssetManager.swift
/// Defines the AssetManager types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import MetalKit

/// Engine-side runtime cache for GPU assets resolved via an AssetDatabase.
public final class AssetManager {
    private var textureCache: [AssetHandle: MTLTexture] = [:]
    private var meshCache: [AssetHandle: MCMesh] = [:]
    private var materialCache: [AssetHandle: MaterialAsset] = [:]
    private var materialCacheModified: [AssetHandle: TimeInterval] = [:]
    private var runtimeTextureHandles = Set<AssetHandle>()
    private var runtimeMeshHandles = Set<AssetHandle>()
    private let cacheLock = NSLock()

    public weak var assetDatabase: AssetDatabase?
    private let device: MTLDevice
    private let graphics: Graphics

    public init(device: MTLDevice, graphics: Graphics) {
        self.device = device
        self.graphics = graphics
    }

    public func handle(forSourcePath sourcePath: String) -> AssetHandle? {
        guard let database = assetDatabase else { return nil }
        if let direct = database.metadata(forSourcePath: sourcePath)?.handle {
            return direct
        }
        let normalized = sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // TODO: Remove Resources/ compatibility once legacy projects are fully migrated.
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

    public func texture(handle: AssetHandle) -> MTLTexture? {
        cacheLock.lock()
        let cached = textureCache[handle]
        cacheLock.unlock()
        if let cached { return cached }
        guard let database = assetDatabase,
              let url = database.assetURL(for: handle) else { return nil }
        let loader = MTKTextureLoader(device: device)
        let metadata = database.metadata(for: handle)
        var options: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        let sourcePath = metadata?.sourcePath ?? url.lastPathComponent
        if let origin = metadata?.importSettings["origin"] {
            if origin == "bottomLeft" {
                options[.origin] = MTKTextureLoader.Origin.bottomLeft
            } else if origin == "topLeft" {
                options[.origin] = MTKTextureLoader.Origin.topLeft
            }
        }
        switch metadata?.type {
        case .environment:
            options[.SRGB] = false
            options[.generateMipmaps] = false
        case .texture:
            if let explicitSRGB = AssetManager.explicitSRGBOverride(metadata: metadata) {
                let expectedSRGB = AssetManager.expectedSRGB(metadata: metadata, sourcePath: sourcePath)
                if explicitSRGB != expectedSRGB {
                    EngineLoggerContext.log(
                        "Texture sRGB mismatch for \(sourcePath) (\(handle.rawValue.uuidString)): expected \(expectedSRGB), got \(explicitSRGB).",
                        level: .warning,
                        category: .assets
                    )
                }
            }
            options[.SRGB] = AssetManager.shouldUseSRGB(metadata: metadata, sourcePath: sourcePath)
            let shouldMipmap = AssetManager.shouldGenerateMipmaps(path: sourcePath)
            options[.generateMipmaps] = false
            options[.allocateMipmaps] = shouldMipmap
        default:
            break
        }
        do {
            var texture = try loader.newTexture(URL: url, options: options)
            if metadata?.type == .texture,
               AssetManager.shouldGenerateMipmaps(path: sourcePath) {
                texture = ensureMipmaps(texture)
            }
            cacheLock.lock()
            textureCache[handle] = texture
            cacheLock.unlock()
            return texture
        } catch {
            EngineLoggerContext.log(
                "Texture load failed \(url.lastPathComponent): \(error)",
                level: .error,
                category: .assets
            )
            return nil
        }
    }

    public func mesh(handle: AssetHandle) -> MCMesh? {
        cacheLock.lock()
        let cached = meshCache[handle]
        cacheLock.unlock()
        if let cached { return cached }
        guard let url = assetDatabase?.assetURL(for: handle) else { return nil }
        let mesh = MCMesh(assetURL: url, device: device, graphics: graphics, assetManager: self)
        cacheLock.lock()
        meshCache[handle] = mesh
        cacheLock.unlock()
        return mesh
    }

    public func material(handle: AssetHandle) -> MaterialAsset? {
        guard let database = assetDatabase,
              let url = database.assetURL(for: handle) else { return nil }
        let lastModified = database.metadata(for: handle)?.lastModified ?? 0
        cacheLock.lock()
        let cached = materialCache[handle]
        let cachedModified = materialCacheModified[handle]
        cacheLock.unlock()
        if let cached,
           cachedModified == lastModified {
            return cached
        }

        if let material = MaterialSerializer.load(from: url, fallbackHandle: handle) {
            cacheLock.lock()
            let wasCached = materialCache[handle] != nil
            materialCache[handle] = material
            materialCacheModified[handle] = lastModified
            cacheLock.unlock()
            let action = wasCached ? "RELOAD" : "LOAD"
            EngineLoggerContext.log(
                "Material asset \(action): \(url.lastPathComponent)",
                level: .debug,
                category: .assets
            )
            return material
        }
        return nil
    }

    public func registerRuntimeTexture(handle: AssetHandle, texture: MTLTexture) {
        cacheLock.lock()
        textureCache[handle] = texture
        runtimeTextureHandles.insert(handle)
        cacheLock.unlock()
    }

    public func registerRuntimeMesh(handle: AssetHandle, mesh: MCMesh) {
        cacheLock.lock()
        meshCache[handle] = mesh
        runtimeMeshHandles.insert(handle)
        cacheLock.unlock()
    }

    public func preload(from database: AssetDatabase) {
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

    public func clearCache() {
        cacheLock.lock()
        textureCache = textureCache.filter { runtimeTextureHandles.contains($0.key) }
        meshCache = meshCache.filter { runtimeMeshHandles.contains($0.key) }
        materialCache.removeAll()
        materialCacheModified.removeAll()
        cacheLock.unlock()
    }

    public static func isColorTexture(path: String) -> Bool {
        let name = path.lowercased()
        if name.contains("normal")
            || name.contains("rough")
            || name.contains("metal")
            || name.contains("orm")
            || name.contains("rma")
            || name.contains("arm")
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

    public static func explicitSRGBOverride(metadata: AssetMetadata?) -> Bool? {
        guard let raw = metadata?.importSettings["srgb"]?.lowercased() else { return nil }
        if raw == "true" || raw == "1" || raw == "yes" { return true }
        if raw == "false" || raw == "0" || raw == "no" { return false }
        return nil
    }

    public static func expectedSRGB(metadata: AssetMetadata?, sourcePath: String) -> Bool {
        if let semantic = (metadata?.importSettings["semantic"] ?? metadata?.importSettings["meshTextureSemantic"])?.lowercased() {
            switch semantic {
            case "basecolor", "albedo", "diffuse", "diff", "emissive":
                return true
            case "normal", "roughness", "metallic", "ao", "occlusion", "height", "mask", "orm", "rma", "arm":
                return false
            default:
                break
            }
        }
        return isColorTexture(path: sourcePath)
    }

    public static func shouldUseSRGB(metadata: AssetMetadata?, sourcePath: String) -> Bool {
        if let explicit = explicitSRGBOverride(metadata: metadata) {
            return explicit
        }
        return expectedSRGB(metadata: metadata, sourcePath: sourcePath)
    }

    public static func shouldFlipNormalY(path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return name.contains("normal-ogl")
            || name.contains("normal_ogl")
            || name.contains("normal-gl")
            || name.contains("normal_gl")
            || name.contains("nor_gl")
            || name.contains("nor-ogl")
            || name.contains("normal-opengl")
            || name.contains("normal_opengl")
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
        return true
    }

    private func ensureMipmaps(_ texture: MTLTexture) -> MTLTexture {
        if texture.mipmapLevelCount <= 1 {
            if let expanded = makeMipmappedCopy(of: texture) {
                generateMipmaps(expanded)
                return expanded
            }
            return texture
        }
        generateMipmaps(texture)
        return texture
    }

    private func generateMipmaps(_ texture: MTLTexture) {
        if texture.mipmapLevelCount <= 1 {
#if DEBUG
            EngineLoggerContext.log(
                "Skipping mipmap generation for \(texture.label ?? "texture") (mipmapLevelCount=\(texture.mipmapLevelCount)).",
                level: .debug,
                category: .assets
            )
#endif
            return
        }
        guard let commandQueue = device.makeCommandQueue() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
    }

    private func makeMipmappedCopy(of texture: MTLTexture) -> MTLTexture? {
        guard texture.textureType == .type2D else { return nil }
        let levels = max(1, 1 + Int(floor(log2(Double(max(texture.width, texture.height))))))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: true
        )
        descriptor.mipmapLevelCount = levels
        descriptor.usage = texture.usage
        descriptor.storageMode = texture.storageMode
        guard let mipTexture = device.makeTexture(descriptor: descriptor) else { return nil }
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        let size = MTLSize(width: texture.width, height: texture.height, depth: 1)
        blit.copy(from: texture,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: size,
                  to: mipTexture,
                  destinationSlice: 0,
                  destinationLevel: 0,
                  destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return mipTexture
    }

}
