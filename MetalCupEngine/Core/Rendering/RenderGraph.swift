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
    let resourceRegistry: RenderResourceRegistry
    let delegate: RendererDelegate?
    let sceneSnapshot: RenderFrameSnapshot?
    let frameContext: RendererFrameContext
    let profiler: RendererProfiler
}

protocol RenderGraphPass {
    var name: String { get }
    var gpuPass: RendererProfiler.GpuPass? { get }
    var inputs: [RenderPassResourceUsage] { get }
    var outputs: [RenderPassResourceUsage] { get }
    var allowedDoubleWriteOutputs: Set<RenderResourceHandle> { get }
    func execute(frame: RenderGraphFrame)
}

extension RenderGraphPass {
    var gpuPass: RendererProfiler.GpuPass? { nil }
    var inputs: [RenderPassResourceUsage] { [] }
    var outputs: [RenderPassResourceUsage] { [] }
    var allowedDoubleWriteOutputs: Set<RenderResourceHandle> { [] }
}

final class RenderGraph {
    private let passes: [RenderGraphPass]

    init() {
        passes = [
            ShadowPass(),
            DepthPrepassPass(),
            CullingDepthFallbackPass(),
            LightCullingPass(),
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
        var outputWriters: [RenderResourceHandle: (name: String, allowsSubsequentWrites: Bool)] = [:]
        var bloomStart: CFTimeInterval?
        for pass in passes {
            validateContracts(pass: pass, frame: frame, outputWriters: &outputWriters)
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
                    resourceRegistry: frame.resourceRegistry,
                    delegate: frame.delegate,
                    sceneSnapshot: frame.sceneSnapshot,
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

    private func validateContracts(pass: RenderGraphPass,
                                   frame: RenderGraphFrame,
                                   outputWriters: inout [RenderResourceHandle: (name: String, allowsSubsequentWrites: Bool)]) {
#if DEBUG
        for input in pass.inputs {
            if !frame.resourceRegistry.contains(input.handle), outputWriters[input.handle] == nil {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' missing input \(input.handle.debugName).",
                    category: .renderer
                )
            }
            validateResourceUsage(pass: pass, usage: input, frame: frame)
            if let expectedFormat = input.expectedTextureFormat,
               let metadata = textureMetadata(for: input.handle, registry: frame.resourceRegistry),
               metadata.pixelFormat != expectedFormat {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' input \(input.handle.debugName) expected \(expectedFormat.rawValue), got \(metadata.pixelFormat.rawValue).",
                    category: .renderer
                )
            }
        }

        for output in pass.outputs {
            if let previous = outputWriters[output.handle] {
                let currentAllows = pass.allowedDoubleWriteOutputs.contains(output.handle)
                let allowed = previous.allowsSubsequentWrites || currentAllows
                if !allowed {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: double-write \(output.handle.debugName) by '\(previous.name)' then '\(pass.name)'.",
                    category: .renderer
                )
                }
            }
            outputWriters[output.handle] = (
                name: pass.name,
                allowsSubsequentWrites: pass.allowedDoubleWriteOutputs.contains(output.handle)
            )
            validateResourceUsage(pass: pass, usage: output, frame: frame)
            if let expectedFormat = output.expectedTextureFormat,
               let metadata = textureMetadata(for: output.handle, registry: frame.resourceRegistry),
               metadata.pixelFormat != expectedFormat {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' output \(output.handle.debugName) expected \(expectedFormat.rawValue), got \(metadata.pixelFormat.rawValue).",
                    category: .renderer
                )
            }
        }
#endif
    }

    private func textureMetadata(for handle: RenderResourceHandle,
                                 registry: RenderResourceRegistry) -> RenderTextureMetadata? {
        switch handle {
        case .texture(let textureHandle):
            return registry.textureMetadata(textureHandle.key)
        case .namedTexture(let key):
            return registry.namedTextureMetadata(key)
        case .buffer:
            return nil
        }
    }

    private func validateResourceUsage(pass: RenderGraphPass,
                                       usage: RenderPassResourceUsage,
                                       frame: RenderGraphFrame) {
        switch usage.handle {
        case .buffer(let handle):
            guard let metadata = frame.resourceRegistry.bufferMetadata(handle.key) else { return }
            if !usage.requiredBufferUsage.isSubset(of: metadata.usage) {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' buffer \(usage.handle.debugName) requires usage \(usage.requiredBufferUsage.rawValue), got \(metadata.usage.rawValue).",
                    category: .renderer
                )
            }
            if !usage.allowedBufferStorageModes.isEmpty && !usage.allowedBufferStorageModes.contains(metadata.storageMode) {
                let allowedModes = usage.allowedBufferStorageModes.map { $0.rawValue }.sorted()
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' buffer \(usage.handle.debugName) storage mode \(metadata.storageMode.rawValue) not in allowed modes \(allowedModes).",
                    category: .renderer
                )
            }
        case .texture, .namedTexture:
            guard let requiredUsage = usage.requiredTextureUsage,
                  let metadata = textureMetadata(for: usage.handle, registry: frame.resourceRegistry) else { return }
            if !metadata.usage.contains(requiredUsage) {
                frame.engineContext.log.logWarning(
                    "RenderGraph contract: pass '\(pass.name)' texture \(usage.handle.debugName) missing required usage flags \(requiredUsage.rawValue).",
                    category: .renderer
                )
            }
        }
    }
}
