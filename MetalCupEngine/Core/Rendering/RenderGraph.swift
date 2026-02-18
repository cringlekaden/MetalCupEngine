/// RenderGraph.swift
/// Lightweight render graph orchestration for frame execution.
/// Created by Kaden Cringle

import MetalKit

struct RenderGraphFrame {
    let view: MTKView
    let sceneView: SceneView
    let commandBuffer: MTLCommandBuffer
    let resources: RenderResources
    let delegate: RendererDelegate?
}

protocol RenderGraphPass {
    var name: String { get }
    func execute(frame: RenderGraphFrame)
}

final class RenderGraph {
    private let passes: [RenderGraphPass]

    init() {
        passes = [
            DepthPrepassPass(),
            ScenePass(),
            GridOverlayPass(),
            PickingPass(),
            SelectionOutlinePass(),
            BloomExtractPass(),
            BloomBlurPass(),
            FinalCompositePass()
        ]
    }

    func execute(frame: RenderGraphFrame) {
        var bloomStart: CFTimeInterval?
        for pass in passes {
            if pass is BloomExtractPass {
                bloomStart = CACurrentMediaTime()
            }
            pass.execute(frame: frame)
            if pass is BloomBlurPass, let start = bloomStart {
                Renderer.profiler.record(.bloom, seconds: CACurrentMediaTime() - start)
            }
        }
    }
}
