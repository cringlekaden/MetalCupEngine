/// RenderGraph.swift
/// Lightweight render graph orchestration for frame execution.
/// Created by Kaden Cringle

import MetalKit

struct RenderGraphFrame {
    let renderer: Renderer
    let engineContext: EngineContext
    let view: MTKView
    let sceneView: SceneView
    let commandBuffer: MTLCommandBuffer
    let resources: RenderResources
    let delegate: RendererDelegate?
    let frameContext: RendererFrameContext
    let profiler: RendererProfiler
}

protocol RenderGraphPass {
    var name: String { get }
    var gpuPass: RendererProfiler.GpuPass? { get }
    func execute(frame: RenderGraphFrame)
}

extension RenderGraphPass {
    var gpuPass: RendererProfiler.GpuPass? { nil }
}

final class RenderGraph {
    private let passes: [RenderGraphPass]

    init() {
        passes = [
            ShadowPass(),
            DepthPrepassPass(),
            ScenePass(),
            GridOverlayPass(),
            DebugDrawPass(),
            PickingPass(),
            SelectionOutlinePass(),
            BloomExtractPass(),
            BloomBlurPass(),
            FinalCompositePass()
        ]
    }

    func execute(
        frame: RenderGraphFrame,
        commandBufferProvider: ((RenderGraphPass) -> MTLCommandBuffer?)? = nil,
        passCommitted: ((RenderGraphPass, MTLCommandBuffer) -> Void)? = nil
    ) {
        var bloomStart: CFTimeInterval?
        for pass in passes {
            if pass is BloomExtractPass {
                bloomStart = CACurrentMediaTime()
            }
            if let commandBufferProvider {
                guard let commandBuffer = commandBufferProvider(pass) else { continue }
                let passFrame = RenderGraphFrame(
                    renderer: frame.renderer,
                    engineContext: frame.engineContext,
                    view: frame.view,
                    sceneView: frame.sceneView,
                    commandBuffer: commandBuffer,
                    resources: frame.resources,
                    delegate: frame.delegate,
                    frameContext: frame.frameContext,
                    profiler: frame.profiler
                )
                pass.execute(frame: passFrame)
                passCommitted?(pass, commandBuffer)
                commandBuffer.commit()
            } else {
                pass.execute(frame: frame)
            }
            if pass is BloomBlurPass, let start = bloomStart {
                frame.profiler.record(.bloom, seconds: CACurrentMediaTime() - start)
            }
        }
    }
}
