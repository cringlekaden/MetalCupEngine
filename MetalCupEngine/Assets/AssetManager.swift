/// AssetManager.swift
/// Defines the AssetManager types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import MetalKit
import ImageIO
import CoreGraphics

/// Engine-side runtime cache for GPU assets resolved via an AssetDatabase.
public final class AssetManager {
    private struct TextureFailureRecord {
        let reason: String
        let lastModified: TimeInterval
    }

    private struct DecodedImageInfo {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let channelCount: Int
        let alphaInfo: String
    }

    private var textureCache: [AssetHandle: MTLTexture] = [:]
    private var textureFailureCacheByPath: [String: TextureFailureRecord] = [:]
    private var textureFailureLoggedPaths: Set<String> = []
    private var meshCache: [AssetHandle: MCMesh] = [:]
    private var materialCache: [AssetHandle: MaterialAsset] = [:]
    private var materialCacheModified: [AssetHandle: TimeInterval] = [:]
    private var runtimeTextureHandles = Set<AssetHandle>()
    private var runtimeMeshHandles = Set<AssetHandle>()
    private let cacheLock = NSLock()

    public weak var assetDatabase: AssetDatabase?
    private let device: MTLDevice
    private let graphics: Graphics
    private let textureWorkQueue: MTLCommandQueue?
    private let errorTexture: MTLTexture

    public init(device: MTLDevice, graphics: Graphics) {
        self.device = device
        self.graphics = graphics
        self.textureWorkQueue = device.makeCommandQueue()
        self.errorTexture = AssetManager.makeErrorTexture(device: device)
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
        let sourcePath = metadata?.sourcePath ?? url.lastPathComponent
        let sourceKey = url.standardizedFileURL.path
        let lastModified = metadata?.lastModified ?? 0
        let isTextureAsset = metadata?.type == .texture
        if isTextureAsset {
            cacheLock.lock()
            let failedRecord = textureFailureCacheByPath[sourceKey]
            cacheLock.unlock()
            if let failedRecord, failedRecord.lastModified == lastModified {
                cacheLock.lock()
                textureCache[handle] = errorTexture
                cacheLock.unlock()
                return errorTexture
            }
        }
        var options: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        if let origin = metadata?.importSettings["origin"] {
            if origin == "bottomLeft" {
                options[.origin] = MTKTextureLoader.Origin.bottomLeft
            } else if origin == "topLeft" {
                options[.origin] = MTKTextureLoader.Origin.topLeft
            }
        }
        switch metadata?.type {
        case .environment:
            if let explicitSRGB = AssetManager.explicitSRGBOverride(metadata: metadata), explicitSRGB {
                EngineLoggerContext.log(
                    "Environment texture \(sourcePath) requested sRGB; forcing linear sampling.",
                    level: .warning,
                    category: .assets
                )
            }
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
            textureFailureCacheByPath.removeValue(forKey: sourceKey)
            cacheLock.unlock()
            return texture
        } catch {
            let ext = url.pathExtension.lowercased()
            let shouldUseSRGB = AssetManager.shouldUseSRGB(metadata: metadata, sourcePath: sourcePath)
            let shouldMipmap = metadata?.type == .texture && AssetManager.shouldGenerateMipmaps(path: sourcePath)
            let origin = options[.origin] as? MTKTextureLoader.Origin ?? .topLeft

            if isTextureAsset,
               let (decodedTexture, decodedInfo) = loadTextureWithImageIOFallback(
                    url: url,
                    srgb: shouldUseSRGB,
                    shouldMipmap: shouldMipmap,
                    origin: origin
               ) {
                cacheLock.lock()
                textureCache[handle] = decodedTexture
                textureFailureCacheByPath.removeValue(forKey: sourceKey)
                cacheLock.unlock()
                logTextureFailureOnce(
                    sourceKey: sourceKey,
                    message: "Texture decode fallback used path=\(sourcePath) ext=\(ext) mtkDecodeFailed=true fallbackDecodeSucceeded=true requestedSRGB=\(shouldUseSRGB) detected=\(decodedInfo.width)x\(decodedInfo.height) bpc=\(decodedInfo.bitsPerComponent) bpp=\(decodedInfo.bitsPerPixel) channels=\(decodedInfo.channelCount) alpha=\(decodedInfo.alphaInfo) outputPixelFormat=\(decodedTexture.pixelFormat)",
                    level: .warning
                )
                return decodedTexture
            }

            if isTextureAsset {
                cacheLock.lock()
                textureFailureCacheByPath[sourceKey] = TextureFailureRecord(reason: "\(error)", lastModified: lastModified)
                textureCache[handle] = errorTexture
                cacheLock.unlock()
            }
            logTextureFailureOnce(
                sourceKey: sourceKey,
                message: "Texture load failed path=\(sourcePath) ext=\(ext) mtkDecodeFailed=true fallbackDecodeSucceeded=false requestedSRGB=\(shouldUseSRGB) error=\(error)",
                level: .error
            )
            return isTextureAsset ? errorTexture : nil
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
        textureFailureCacheByPath.removeAll()
        textureFailureLoggedPaths.removeAll()
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

    private static func normalizedSemantic(metadata: AssetMetadata?) -> String? {
        (metadata?.importSettings["semantic"] ?? metadata?.importSettings["meshTextureSemantic"])?.lowercased()
    }

    private static func semanticIsColor(_ semantic: String) -> Bool {
        switch semantic {
        case "basecolor", "albedo", "diffuse", "diff", "emissive":
            return true
        default:
            return false
        }
    }

    private static func semanticIsData(_ semantic: String) -> Bool {
        switch semantic {
        case "normal", "roughness", "metallic", "ao", "occlusion", "height", "mask", "orm", "rma", "arm":
            return true
        default:
            return false
        }
    }

    public static func expectedSRGB(metadata: AssetMetadata?, sourcePath: String) -> Bool {
        if metadata?.type == .environment {
            return false
        }
        if let semantic = normalizedSemantic(metadata: metadata) {
            if semanticIsColor(semantic) {
                return true
            }
            if semanticIsData(semantic) {
                return false
            }
        }
        return isColorTexture(path: sourcePath)
    }

    public static func shouldUseSRGB(metadata: AssetMetadata?, sourcePath: String) -> Bool {
        if metadata?.type == .environment {
            return false
        }
        if let semantic = normalizedSemantic(metadata: metadata),
           semanticIsData(semantic) {
            return false
        }
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
        guard let commandBuffer = textureWorkQueue?.makeCommandBuffer() else { return }
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
        guard let commandBuffer = textureWorkQueue?.makeCommandBuffer(),
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

    private func logTextureFailureOnce(sourceKey: String, message: String, level: MCLogLevel) {
        var shouldLog = false
        cacheLock.lock()
        if !textureFailureLoggedPaths.contains(sourceKey) {
            textureFailureLoggedPaths.insert(sourceKey)
            shouldLog = true
        }
        cacheLock.unlock()
        if shouldLog {
            EngineLoggerContext.log(message, level: level, category: .assets)
        }
    }

    private static func makeErrorTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create error texture.")
        }
        texture.label = "Fallback.ErrorTexture"
        let pixels: [UInt8] = [
            255,   0, 255, 255,   0,   0,   0, 255,
              0,   0,   0, 255, 255,   0, 255, 255
        ]
        pixels.withUnsafeBytes { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 2, height: 2, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: 2 * 4)
        }
        return texture
    }

    private func loadTextureWithImageIOFallback(
        url: URL,
        srgb: Bool,
        shouldMipmap: Bool,
        origin: MTKTextureLoader.Origin
    ) -> (MTLTexture, DecodedImageInfo)? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgbaData = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        if origin == .topLeft {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelFormat: MTLPixelFormat = srgb ? .rgba8Unorm_srgb : .rgba8Unorm
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: shouldMipmap
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Asset.Texture.FallbackDecode.\(url.lastPathComponent)"
        rgbaData.withUnsafeBytes { bytes in
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1))
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: bytesPerRow)
        }
        let finalTexture = shouldMipmap ? ensureMipmaps(texture) : texture
        let alphaInfo = String(describing: cgImage.alphaInfo)
        let bitsPerComponent = cgImage.bitsPerComponent
        let bitsPerPixel = cgImage.bitsPerPixel
        let channelCount = max(1, bitsPerPixel / max(bitsPerComponent, 1))
        let decodedInfo = DecodedImageInfo(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            channelCount: channelCount,
            alphaInfo: alphaInfo
        )
        return (finalTexture, decodedInfo)
    }

}
