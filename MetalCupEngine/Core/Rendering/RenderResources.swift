/// RenderResources.swift
/// Render target registry and resize handling for the renderer.
/// Created by Kaden Cringle

import MetalKit

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
    private var usesHalfResBloom = false
    private let preferences: Preferences
    private let settingsProvider: () -> RendererSettings
    private let settingsUpdater: (RendererSettings) -> Void
    private let assetManager: AssetManager
    private let device: MTLDevice

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
        let halfResBloom = settingsProvider().hasPerfFlag(.halfResBloom)
        if usesHalfResBloom != halfResBloom { return false }
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
        usesHalfResBloom = settingsProvider().hasPerfFlag(.halfResBloom)

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

        let divisor = usesHalfResBloom ? 2 : 1
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

    private func registerTexture(descriptor: MTLTextureDescriptor, handle: RenderResourceTexture, label: String) {
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            MC_CORE_ASSERT(false, "Failed to allocate render target: \(label)")
            return
        }
        texture.label = label
        assetManager.registerRuntimeTexture(handle: handle.handle, texture: texture)
    }
}

typealias RenderGraphResources = RenderResources
