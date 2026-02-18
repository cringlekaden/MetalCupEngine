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

    func isValid(for size: CGSize) -> Bool {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return false }
        if drawableSize.x != width || drawableSize.y != height { return false }
        let halfResBloom = Renderer.settings.hasPerfFlag(.halfResBloom)
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
        usesHalfResBloom = Renderer.settings.hasPerfFlag(.halfResBloom)

        let baseColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.HDRPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        baseColorDesc.usage = [.renderTarget, .shaderRead]
        baseColorDesc.storageMode = .private
        registerTexture(descriptor: baseColorDesc, handle: .baseColor, label: "RenderTarget.BaseColor")

        let finalColorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.defaultColorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        finalColorDesc.usage = [.renderTarget, .shaderRead]
        finalColorDesc.storageMode = .private
        registerTexture(descriptor: finalColorDesc, handle: .finalColor, label: "RenderTarget.FinalColor")

        let baseDepthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.defaultDepthPixelFormat,
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
            pixelFormat: Preferences.HDRPixelFormat,
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
            pixelFormat: Preferences.defaultDepthPixelFormat,
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
            pixelFormat: Preferences.HDRPixelFormat,
            width: bloomWidth,
            height: bloomHeight,
            mipmapped: true
        )
        bloomDesc.usage = [.renderTarget, .shaderRead]
        bloomDesc.storageMode = .private
        registerTexture(descriptor: bloomDesc, handle: .bloomPing, label: "RenderTarget.BloomPing")
        registerTexture(descriptor: bloomDesc, handle: .bloomPong, label: "RenderTarget.BloomPong")

        Renderer.settings.bloomTexelSize = SIMD2<Float>(1.0 / Float(bloomWidth), 1.0 / Float(bloomHeight))
    }

    func texture(_ texture: RenderResourceTexture) -> MTLTexture? {
        AssetManager.texture(handle: texture.handle)
    }

    private func registerTexture(descriptor: MTLTextureDescriptor, handle: RenderResourceTexture, label: String) {
        guard let texture = Engine.Device.makeTexture(descriptor: descriptor) else {
            MC_CORE_ASSERT(false, "Failed to allocate render target: \(label)")
            return
        }
        texture.label = label
        AssetManager.registerRuntimeTexture(handle: handle.handle, texture: texture)
    }
}

typealias RenderGraphResources = RenderResources
