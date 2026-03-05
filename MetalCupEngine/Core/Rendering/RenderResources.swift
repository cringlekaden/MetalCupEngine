/// RenderResources.swift
/// Render target registry and resize handling for the renderer.
/// Created by Kaden Cringle

import MetalKit

enum RenderResourceLifetime: String {
    case transientPerFrame
    case persistent
}

enum RenderNamedResourceKey {
    static let forwardPlusCullingDepth = "forwardPlus.cullingDepth"
    static let forwardPlusTileLightGrid = "forwardPlus.tileLightGrid"
    static let forwardPlusTileLightIndexList = "forwardPlus.tileLightIndexList"
    static let forwardPlusTileLightIndexCount = "forwardPlus.tileLightIndexCount"
    static let forwardPlusActiveTileList = "forwardPlus.activeTileList"
    static let forwardPlusActiveTileCount = "forwardPlus.activeTileCount"
    static let forwardPlusActiveDispatchArgs = "forwardPlus.activeDispatchArgs"
    static let forwardPlusTileParams = "forwardPlus.tileParams"
    static let forwardPlusStats = "forwardPlus.stats"
    static let forwardPlusLightGrid = "forwardPlus.lightGrid"
    static let forwardPlusLightIndexList = "forwardPlus.lightIndexList"
    static let forwardPlusLightIndexCount = "forwardPlus.lightIndexCount"
    static let forwardPlusClusterParams = "forwardPlus.clusterParams"
}

struct RenderTextureMetadata {
    let size: SIMD2<Int>
    let pixelFormat: MTLPixelFormat
    let usage: MTLTextureUsage
    let lifetime: RenderResourceLifetime
}

struct RenderBufferMetadata {
    let length: Int
    let lifetime: RenderResourceLifetime
    let storageMode: MTLStorageMode
    let usage: RenderBufferUsage
}

struct RenderBufferUsage: OptionSet {
    let rawValue: UInt8

    static let computeRead = RenderBufferUsage(rawValue: 1 << 0)
    static let computeWrite = RenderBufferUsage(rawValue: 1 << 1)
}

struct RenderTextureHandle: Hashable {
    let key: RenderResourceTexture
}

struct RenderBufferHandle: Hashable {
    let key: String
}

struct RenderTransientBufferKey: Hashable {
    let resourceName: String
    let frameInFlightIndex: Int
    let viewSignature: UInt64
    let sizeSignature: UInt64
    let settingsRevision: UInt64
}

enum RenderResourceHandle: Hashable {
    case texture(RenderTextureHandle)
    case namedTexture(String)
    case buffer(RenderBufferHandle)

    var debugName: String {
        switch self {
        case .texture(let texture):
            return "texture.\(String(describing: texture.key))"
        case .namedTexture(let key):
            return "texture.\(key)"
        case .buffer(let buffer):
            return "buffer.\(buffer.key)"
        }
    }
}

struct RenderPassResourceUsage {
    let handle: RenderResourceHandle
    let expectedTextureFormat: MTLPixelFormat?
    let requiredTextureUsage: MTLTextureUsage?
    let requiredBufferUsage: RenderBufferUsage
    let allowedBufferStorageModes: Set<MTLStorageMode>

    static func texture(_ key: RenderResourceTexture, expectedFormat: MTLPixelFormat? = nil) -> RenderPassResourceUsage {
        RenderPassResourceUsage(
            handle: .texture(RenderTextureHandle(key: key)),
            expectedTextureFormat: expectedFormat,
            requiredTextureUsage: nil,
            requiredBufferUsage: [],
            allowedBufferStorageModes: []
        )
    }

    static func namedTexture(_ key: String,
                             expectedFormat: MTLPixelFormat? = nil,
                             requiredUsage: MTLTextureUsage? = nil) -> RenderPassResourceUsage {
        RenderPassResourceUsage(
            handle: .namedTexture(key),
            expectedTextureFormat: expectedFormat,
            requiredTextureUsage: requiredUsage,
            requiredBufferUsage: [],
            allowedBufferStorageModes: []
        )
    }

    static func buffer(_ key: String,
                       requiredUsage: RenderBufferUsage = [],
                       allowedStorageModes: Set<MTLStorageMode> = [.shared, .private]) -> RenderPassResourceUsage {
        RenderPassResourceUsage(
            handle: .buffer(RenderBufferHandle(key: key)),
            expectedTextureFormat: nil,
            requiredTextureUsage: nil,
            requiredBufferUsage: requiredUsage,
            allowedBufferStorageModes: allowedStorageModes
        )
    }
}

final class RenderResourceRegistry {
    private struct TextureEntry {
        let texture: MTLTexture
        let metadata: RenderTextureMetadata
    }

    private struct BufferEntry {
        let buffer: MTLBuffer
        let metadata: RenderBufferMetadata
    }

    private var textures: [RenderTextureHandle: TextureEntry] = [:]
    private var namedTextures: [String: TextureEntry] = [:]
    private var buffers: [RenderBufferHandle: BufferEntry] = [:]

    func registerTexture(_ key: RenderResourceTexture,
                         texture: MTLTexture,
                         lifetime: RenderResourceLifetime) {
        let handle = RenderTextureHandle(key: key)
        textures[handle] = TextureEntry(
            texture: texture,
            metadata: RenderTextureMetadata(
                size: SIMD2<Int>(texture.width, texture.height),
                pixelFormat: texture.pixelFormat,
                usage: texture.usage,
                lifetime: lifetime
            )
        )
    }

    func registerBuffer(_ key: String,
                        buffer: MTLBuffer,
                        lifetime: RenderResourceLifetime,
                        usage: RenderBufferUsage = []) {
        let handle = RenderBufferHandle(key: key)
#if DEBUG
        if !usage.isEmpty {
            let mode = buffer.storageMode
            MC_ASSERT(mode == .shared || mode == .private,
                      "RenderResourceRegistry: buffer '\(key)' is marked for compute use but has unsupported storage mode \(mode.rawValue).")
        }
#endif
        buffers[handle] = BufferEntry(
            buffer: buffer,
            metadata: RenderBufferMetadata(
                length: buffer.length,
                lifetime: lifetime,
                storageMode: buffer.storageMode,
                usage: usage
            )
        )
    }

    func registerNamedTexture(_ key: String,
                              texture: MTLTexture,
                              lifetime: RenderResourceLifetime) {
        namedTextures[key] = TextureEntry(
            texture: texture,
            metadata: RenderTextureMetadata(
                size: SIMD2<Int>(texture.width, texture.height),
                pixelFormat: texture.pixelFormat,
                usage: texture.usage,
                lifetime: lifetime
            )
        )
    }

    func texture(_ key: RenderResourceTexture) -> MTLTexture? {
        textures[RenderTextureHandle(key: key)]?.texture
    }

    func textureMetadata(_ key: RenderResourceTexture) -> RenderTextureMetadata? {
        textures[RenderTextureHandle(key: key)]?.metadata
    }

    func namedTexture(_ key: String) -> MTLTexture? {
        namedTextures[key]?.texture
    }

    func namedTextureMetadata(_ key: String) -> RenderTextureMetadata? {
        namedTextures[key]?.metadata
    }

    func buffer(_ key: String) -> MTLBuffer? {
        buffers[RenderBufferHandle(key: key)]?.buffer
    }

    func bufferMetadata(_ key: String) -> RenderBufferMetadata? {
        buffers[RenderBufferHandle(key: key)]?.metadata
    }

    func contains(_ handle: RenderResourceHandle) -> Bool {
        switch handle {
        case .texture(let texture):
            return textures[texture] != nil
        case .namedTexture(let key):
            return namedTextures[key] != nil
        case .buffer(let buffer):
            return buffers[buffer] != nil
        }
    }
}

enum RenderResourceTexture {
    case baseColor
    case finalColor
    case baseDepth
    case bloomPing
    case bloomPong
    case outlineMask
    case gridColor
    case pickId
    case pickDepth

    var handle: AssetHandle {
        switch self {
        case .baseColor:
            return BuiltinAssets.baseColorRender
        case .finalColor:
            return BuiltinAssets.finalColorRender
        case .baseDepth:
            return BuiltinAssets.baseDepthRender
        case .bloomPing:
            return BuiltinAssets.bloomPing
        case .bloomPong:
            return BuiltinAssets.bloomPong
        case .outlineMask:
            return BuiltinAssets.outlineMask
        case .gridColor:
            return BuiltinAssets.gridColor
        case .pickId:
            return BuiltinAssets.pickIdRender
        case .pickDepth:
            return BuiltinAssets.pickDepthRender
        }
    }
}

final class RenderResources {
    private var drawableSize = SIMD2<Int>(0, 0)
    private var bloomResolutionScale: UInt32 = BloomResolutionScale.quarter.rawValue
    private let preferences: Preferences
    private let settingsProvider: () -> RendererSettings
    private let settingsUpdater: (RendererSettings) -> Void
    private let assetManager: AssetManager
    private let device: MTLDevice
    private var transientBuffers: [RenderTransientBufferKey: MTLBuffer] = [:]

    init(preferences: Preferences, settingsProvider: @escaping () -> RendererSettings, settingsUpdater: @escaping (RendererSettings) -> Void, assetManager: AssetManager, device: MTLDevice) {
        self.preferences = preferences
        self.settingsProvider = settingsProvider
        self.settingsUpdater = settingsUpdater
        self.assetManager = assetManager
        self.device = device
    }

    func isValid(for size: CGSize) -> Bool {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return false }
        if drawableSize.x != width || drawableSize.y != height { return false }
        let currentScale = normalizedBloomScale(settingsProvider().bloomResolutionScale)
        if bloomResolutionScale != currentScale { return false }
        return texture(.baseColor) != nil
            && texture(.finalColor) != nil
            && texture(.baseDepth) != nil
            && texture(.bloomPing) != nil
            && texture(.bloomPong) != nil
            && texture(.outlineMask) != nil
            && texture(.gridColor) != nil
            && texture(.pickId) != nil
            && texture(.pickDepth) != nil
    }

    func rebuild(drawableSize size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return }
        drawableSize = SIMD2<Int>(width, height)
        bloomResolutionScale = normalizedBloomScale(settingsProvider().bloomResolutionScale)

        let baseColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        baseColorDesc.usage = [.renderTarget, .shaderRead]
        baseColorDesc.storageMode = .private
        registerTexture(descriptor: baseColorDesc, handle: .baseColor, label: "RenderTarget.BaseColor")

        let finalColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.defaultColorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        finalColorDesc.usage = [.renderTarget, .shaderRead]
        finalColorDesc.storageMode = .private
        registerTexture(descriptor: finalColorDesc, handle: .finalColor, label: "RenderTarget.FinalColor")

        let baseDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.defaultDepthPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        baseDepthDesc.usage = [.renderTarget, .shaderRead]
        baseDepthDesc.storageMode = .private
        registerTexture(descriptor: baseDepthDesc, handle: .baseDepth, label: "RenderTarget.BaseDepth")

        let outlineDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outlineDesc.usage = [.renderTarget, .shaderRead]
        outlineDesc.storageMode = .private
        registerTexture(descriptor: outlineDesc, handle: .outlineMask, label: "RenderTarget.OutlineMask")

        let gridDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        gridDesc.usage = [.renderTarget, .shaderRead]
        gridDesc.storageMode = .private
        registerTexture(descriptor: gridDesc, handle: .gridColor, label: "RenderTarget.GridColor")

        let pickIdDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Uint,
            width: width,
            height: height,
            mipmapped: false
        )
        pickIdDesc.usage = [.renderTarget, .shaderRead]
        pickIdDesc.storageMode = .private
        registerTexture(descriptor: pickIdDesc, handle: .pickId, label: "RenderTarget.PickID")

        let pickDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.defaultDepthPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        pickDepthDesc.usage = [.renderTarget]
        pickDepthDesc.storageMode = .private
        registerTexture(descriptor: pickDepthDesc, handle: .pickDepth, label: "RenderTarget.PickDepth")

        let divisor = Int(bloomResolutionScale)
        let bloomWidth = max(1, width / divisor)
        let bloomHeight = max(1, height / divisor)
        let bloomDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: preferences.HDRPixelFormat,
            width: bloomWidth,
            height: bloomHeight,
            mipmapped: true
        )
        bloomDesc.usage = [.renderTarget, .shaderRead]
        bloomDesc.storageMode = .private
        registerTexture(descriptor: bloomDesc, handle: .bloomPing, label: "RenderTarget.BloomPing")
        registerTexture(descriptor: bloomDesc, handle: .bloomPong, label: "RenderTarget.BloomPong")

        var settings = settingsProvider()
        settings.bloomTexelSize = SIMD2<Float>(1.0 / Float(bloomWidth), 1.0 / Float(bloomHeight))
        settingsUpdater(settings)
    }

    func texture(_ texture: RenderResourceTexture) -> MTLTexture? {
        assetManager.texture(handle: texture.handle)
    }

    func buildRegistry() -> RenderResourceRegistry {
        let registry = RenderResourceRegistry()
        let allTextures: [RenderResourceTexture] = [
            .baseColor,
            .finalColor,
            .baseDepth,
            .bloomPing,
            .bloomPong,
            .outlineMask,
            .gridColor,
            .pickId,
            .pickDepth
        ]
        for key in allTextures {
            guard let texture = texture(key) else { continue }
            registry.registerTexture(key, texture: texture, lifetime: .persistent)
        }
        return registry
    }

    func transientBuffer(resourceName: String,
                         frameInFlightIndex: Int,
                         viewSignature: UInt64,
                         sizeSignature: UInt64,
                         settingsRevision: UInt64,
                         minLength: Int,
                         storageMode: MTLStorageMode,
                         label: String) -> MTLBuffer? {
        let key = RenderTransientBufferKey(
            resourceName: resourceName,
            frameInFlightIndex: frameInFlightIndex,
            viewSignature: viewSignature,
            sizeSignature: sizeSignature,
            settingsRevision: settingsRevision
        )
        if let existing = transientBuffers[key],
           existing.length >= minLength,
           existing.storageMode == storageMode {
            return existing
        }

        transientBuffers = transientBuffers.filter { entry in
            let existingKey = entry.key
            if existingKey.resourceName != resourceName { return true }
            if existingKey.frameInFlightIndex != frameInFlightIndex { return true }
            if existingKey.viewSignature != viewSignature { return true }
            if existingKey.sizeSignature == sizeSignature && existingKey.settingsRevision == settingsRevision {
                return true
            }
            return false
        }

        let options: MTLResourceOptions = (storageMode == .private) ? [.storageModePrivate] : [.storageModeShared]
        guard let buffer = device.makeBuffer(length: max(minLength, 1), options: options) else {
            return nil
        }
        buffer.label = label
        transientBuffers[key] = buffer
        return buffer
    }

    private func registerTexture(descriptor: MTLTextureDescriptor, handle: RenderResourceTexture, label: String) {
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            MC_CORE_ASSERT(false, "Failed to allocate render target: \(label)")
            return
        }
        texture.label = label
        assetManager.registerRuntimeTexture(handle: handle.handle, texture: texture)
    }

    private func normalizedBloomScale(_ value: UInt32) -> UInt32 {
        value <= BloomResolutionScale.half.rawValue
            ? BloomResolutionScale.half.rawValue
            : BloomResolutionScale.quarter.rawValue
    }
}

typealias RenderGraphResources = RenderResources
