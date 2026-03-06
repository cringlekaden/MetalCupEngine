/// RenderGraph.swift
/// Lightweight render graph orchestration for frame execution.
/// Created by Kaden Cringle

import MetalKit

struct RenderPlan {
    let viewSignature: UInt64
    let enabledPassNames: Set<String>
    let forwardPlusEnabled: Bool
    let cullingDepthSource: ForwardPlusCullingDepthSource
    let cullingDepthBinding: RenderResourceHandle?
    let sceneDepthLoadAction: MTLLoadAction
    let bloomEnabled: Bool
    let pickingEnabled: Bool
    let showEditorOverlays: Bool
    let gridEnabled: Bool
    let debugDrawEnabled: Bool

    static func unplanned(viewSignature: UInt64) -> RenderPlan {
        RenderPlan(
            viewSignature: viewSignature,
            enabledPassNames: [],
            forwardPlusEnabled: false,
            cullingDepthSource: .none,
            cullingDepthBinding: nil,
            sceneDepthLoadAction: .clear,
            bloomEnabled: false,
            pickingEnabled: false,
            showEditorOverlays: false,
            gridEnabled: false,
            debugDrawEnabled: false
        )
    }

    func runs(_ pass: RenderGraphPass) -> Bool {
        enabledPassNames.contains(pass.name)
    }
}

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
    let frameInFlightIndex: Int
    let viewSignature: UInt64
    let settingsRevision: UInt64
    let renderPlan: RenderPlan

    func with(commandBuffer: MTLCommandBuffer? = nil,
              renderPlan: RenderPlan? = nil) -> RenderGraphFrame {
        RenderGraphFrame(
            renderer: renderer,
            engineContext: engineContext,
            view: view,
            sceneView: sceneView,
            commandBuffer: commandBuffer ?? self.commandBuffer,
            resources: resources,
            resourceRegistry: resourceRegistry,
            delegate: delegate,
            sceneSnapshot: sceneSnapshot,
            frameContext: frameContext,
            profiler: profiler,
            frameInFlightIndex: frameInFlightIndex,
            viewSignature: viewSignature,
            settingsRevision: settingsRevision,
            renderPlan: renderPlan ?? self.renderPlan
        )
    }
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
    private enum PassName {
        static let depthPrepass = "DepthPrepassPass"
        static let cullingDepthFallback = "CullingDepthFallbackPass"
        static let forwardPlusTileBin = "ForwardPlusTileBinPass"
        static let lightCulling = "LightCullingPass"
        static let scene = "ScenePass"
        static let picking = "PickingPass"
        static let gridOverlay = "GridOverlayPass"
        static let debugDraw = "DebugDrawPass"
        static let bloomExtract = "BloomExtractPass"
        static let bloomBlur = "BloomBlurPass"
    }

    init() {
        passes = [
            ShadowPass(),
            DepthPrepassPass(),
            CullingDepthFallbackPass(),
            ForwardPlusTileBinPass(),
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
        let plan = buildRenderPlan(frame: frame)
        let plannedFrame = frame.with(renderPlan: plan)
        var outputWriters: [RenderResourceHandle: (name: String, allowsSubsequentWrites: Bool)] = [:]
        var bloomStart: CFTimeInterval?
        for pass in passes {
            guard plan.runs(pass) else { continue }
            validateContracts(pass: pass, frame: plannedFrame, outputWriters: &outputWriters)
            if pass.name == PassName.lightCulling {
                enforceForwardPlusDepthContract(frame: plannedFrame, pass: pass)
            }
            if pass.name == PassName.bloomExtract {
                bloomStart = CACurrentMediaTime()
            }
            if let commandBufferProvider {
                guard let commandBuffer = commandBufferProvider(pass) else { continue }
                let passFrame = plannedFrame.with(commandBuffer: commandBuffer)
                pass.execute(frame: passFrame)
                applyPostPassSideEffects(pass: pass, frame: passFrame, plan: plan)
                passCommitted?(pass, commandBuffer)
                commandBuffer.commit()
            } else {
                pass.execute(frame: plannedFrame)
                applyPostPassSideEffects(pass: pass, frame: plannedFrame, plan: plan)
            }
            if pass.name == PassName.bloomBlur, let start = bloomStart {
                plannedFrame.profiler.record(.bloom, seconds: CACurrentMediaTime() - start)
            }
        }
    }

    private func buildRenderPlan(frame: RenderGraphFrame) -> RenderPlan {
        let settings = frame.frameContext.rendererSettings()
        var enabledPassNames = Set(passes.map(\.name))
        let depthPrepassEnabled = frame.frameContext.useDepthPrepass()
        let showEditorOverlays = RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView)
        if depthPrepassEnabled {
            enabledPassNames.remove(PassName.cullingDepthFallback)
        } else {
            enabledPassNames.remove(PassName.depthPrepass)
        }

        let hasSelection = settings.outlineEnabled != 0
            && RenderPassHelpers.shouldRenderEditorOverlays(frame.frameContext, fallback: frame.sceneView)
            && !frame.sceneView.selectedEntityIds.isEmpty
        let pickingEnabled = frame.engineContext.pickingSystem.hasPendingRequest() || hasSelection
        if !pickingEnabled {
            enabledPassNames.remove(PassName.picking)
        }

        let bloomEnabled = settings.bloomEnabled != 0
        if !bloomEnabled {
            enabledPassNames.remove(PassName.bloomExtract)
            enabledPassNames.remove(PassName.bloomBlur)
        }

        let gridEnabled = settings.gridEnabled != 0 && showEditorOverlays
        if !gridEnabled {
            enabledPassNames.remove(PassName.gridOverlay)
        }

        let debugDrawEnabled = frame.engineContext.physicsSettings.debugDrawEnabled
            && (showEditorOverlays || (frame.engineContext.physicsSettings.debugDrawInPlay && !frame.sceneView.isEditorView))
        if !debugDrawEnabled {
            enabledPassNames.remove(PassName.debugDraw)
        }

        var forwardPlusEnabled = settings.hasPerfFlag(.forwardPlusEnabled) && frame.frameContext.isForwardPlusAllowed()
        var cullingDepthSource: ForwardPlusCullingDepthSource = .none
        var cullingDepthBinding: RenderResourceHandle?
        if forwardPlusEnabled {
            if frame.resourceRegistry.texture(.baseDepth) == nil {
#if DEBUG
                let message = "Forward+ planning requires baseDepth for view \(frame.viewSignature)."
                assertionFailure(message)
                fatalError(message)
#else
                forwardPlusEnabled = false
                frame.frameContext.setForwardPlusAllowed(false)
                frame.frameContext.diagnostics.incrementForwardPlusMissingDepthFrames()
#endif
            } else {
                cullingDepthSource = depthPrepassEnabled ? .prepass : .fallback
                cullingDepthBinding = .namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth)
            }
        }

        if !forwardPlusEnabled {
            enabledPassNames.remove(PassName.forwardPlusTileBin)
            enabledPassNames.remove(PassName.lightCulling)
            enabledPassNames.remove(PassName.cullingDepthFallback)
        }

        return RenderPlan(
            viewSignature: frame.viewSignature,
            enabledPassNames: enabledPassNames,
            forwardPlusEnabled: forwardPlusEnabled,
            cullingDepthSource: cullingDepthSource,
            cullingDepthBinding: cullingDepthBinding,
            sceneDepthLoadAction: depthPrepassEnabled ? .load : .clear,
            bloomEnabled: bloomEnabled,
            pickingEnabled: pickingEnabled,
            showEditorOverlays: showEditorOverlays,
            gridEnabled: gridEnabled,
            debugDrawEnabled: debugDrawEnabled
        )
    }

    private func applyPostPassSideEffects(pass: RenderGraphPass, frame: RenderGraphFrame, plan: RenderPlan) {
        let shouldPublishDepthSource: Bool = {
            switch plan.cullingDepthSource {
            case .prepass:
                return pass.name == PassName.depthPrepass
            case .fallback:
                return pass.name == PassName.cullingDepthFallback
            case .none:
                return false
            }
        }()
        guard shouldPublishDepthSource,
              let depth = frame.resourceRegistry.texture(.baseDepth) else { return }
        frame.resourceRegistry.registerNamedTexture(
            RenderNamedResourceKey.forwardPlusCullingDepth,
            texture: depth,
            lifetime: .transientPerFrame
        )
        frame.frameContext.markForwardPlusCullingDepthProduced(source: plan.cullingDepthSource)
    }

    private func enforceForwardPlusDepthContract(frame: RenderGraphFrame,
                                                 pass: RenderGraphPass) {
        let forwardPlusEnabled = frame.renderPlan.forwardPlusEnabled
        guard forwardPlusEnabled else { return }

        let expectedHandle = frame.renderPlan.cullingDepthBinding
            ?? RenderResourceHandle.namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth)
        let hasDeclaredInput = pass.inputs.contains { $0.handle == expectedHandle }
        let producerCount = frame.frameContext.forwardPlusCullingDepthProducerCount()
        let hasDepthTexture = frame.resourceRegistry.namedTexture(RenderNamedResourceKey.forwardPlusCullingDepth) != nil
        let valid = hasDeclaredInput && producerCount == 1 && hasDepthTexture
        guard !valid else { return }

        let expectedSource = frame.renderPlan.cullingDepthSource
        let message = "Forward+ cullingDepth contract invalid for view \(frame.viewSignature): declaredInput=\(hasDeclaredInput) producerCount=\(producerCount) plannedSource=\(expectedSource) hasTexture=\(hasDepthTexture)."
#if DEBUG
        assertionFailure(message)
        fatalError(message)
#else
        frame.engineContext.log.logWarning(message, category: .renderer)
        frame.frameContext.setForwardPlusAllowed(false)
        frame.frameContext.diagnostics.forwardPlus.cullingDepthSource = .none
        frame.frameContext.diagnostics.incrementForwardPlusMissingDepthFrames()
#endif
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
