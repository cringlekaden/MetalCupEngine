/// OutlineSystem.swift
/// Encodes the selection outline pass using existing renderer resources.
/// Created by Kaden Cringle.

import MetalKit
import Foundation

public enum OutlineSystem {

    static func encodeSelectionOutline(frame: RenderGraphFrame) {
        guard let outline = frame.resources.texture(.outlineMask) else { return }
        let clearPass = RenderPassBuilder.color(texture: outline, clearColor: MTLClearColorMake(0, 0, 0, 0))
        guard let clearEncoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: clearPass) else { return }
        clearEncoder.label = "Selection Outline Clear"
        clearEncoder.endEncoding()

        if frame.renderer.settings.outlineEnabled == 0 || !RenderPassHelpers.shouldRenderEditorOverlays(frame.sceneView) {
            return
        }
        guard let pickId = frame.resources.texture(.pickId) else { return }
        guard let quadMesh = frame.engineContext.assets.mesh(handle: BuiltinAssets.fullscreenQuadMesh) else { return }
        guard let selectedId = frame.sceneView.selectedEntityIds.first else { return }

        let selectedPickId = frame.engineContext.pickingSystem.pickId(for: selectedId)
        if selectedPickId == 0 { return }

        let pass = RenderPassBuilder.color(texture: outline, clearColor: MTLClearColorMake(0, 0, 0, 0))
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Selection Outline"
        encoder.pushDebugGroup("Selection Outline")
        defer {
            encoder.popDebugGroup()
            encoder.endEncoding()
        }

        RenderPassHelpers.setViewport(encoder, RenderPassHelpers.textureSize(outline))
        encoder.setRenderPipelineState(frame.engineContext.graphics.renderPipelineStates[.SelectionOutline])
        encoder.setCullMode(.none)
        encoder.setFragmentTexture(pickId, index: PostProcessTextureIndex.source)

        var params = OutlineParams()
        params.selectedId = selectedPickId
        let thickness = max(1, min(4, Int(frame.renderer.settings.outlineThickness)))
        params.thickness = UInt32(thickness)
        params.texelSize = SIMD2<Float>(1.0 / Float(pickId.width), 1.0 / Float(pickId.height))
        encoder.setFragmentBytes(&params, length: OutlineParams.stride, index: FragmentBufferIndex.outlineParams)

        quadMesh.drawPrimitives(encoder, frameContext: frame.frameContext)
    }
}
