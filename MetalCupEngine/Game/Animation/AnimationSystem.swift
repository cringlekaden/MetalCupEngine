/// AnimationSystem.swift
/// Minimal animation scaffolding for update-time evaluation and render snapshot prep.
/// Created by Kaden Cringle.

import Foundation
import simd
import QuartzCore

public struct AnimationSnapshotPayload {
    public struct BonePaletteRange {
        public let startIndex: Int
        public let count: Int

        public init(startIndex: Int, count: Int) {
            self.startIndex = startIndex
            self.count = count
        }
    }

    public struct SkinnedEntry {
        public let entity: Entity
        public let skeletonHandle: AssetHandle?
        public let clipHandle: AssetHandle?
        public let playbackTime: Float
        public let isPlaying: Bool
        public let evaluatedJointCount: Int
        public let bonePaletteRange: BonePaletteRange?

        public init(entity: Entity,
                    skeletonHandle: AssetHandle?,
                    clipHandle: AssetHandle?,
                    playbackTime: Float,
                    isPlaying: Bool,
                    evaluatedJointCount: Int,
                    bonePaletteRange: BonePaletteRange?) {
            self.entity = entity
            self.skeletonHandle = skeletonHandle
            self.clipHandle = clipHandle
            self.playbackTime = playbackTime
            self.isPlaying = isPlaying
            self.evaluatedJointCount = evaluatedJointCount
            self.bonePaletteRange = bonePaletteRange
        }
    }

    public let skinnedEntries: [SkinnedEntry]
    public let bonePaletteMatrices: [matrix_float4x4]

    public init(skinnedEntries: [SkinnedEntry], bonePaletteMatrices: [matrix_float4x4]) {
        self.skinnedEntries = skinnedEntries
        self.bonePaletteMatrices = bonePaletteMatrices
    }
}

public final class AnimationSystem {
    private struct BonePaletteBuildResult {
        let matrices: [matrix_float4x4]
        let bindPolicy: String
        let importedInverseBindCount: Int
        let nonFiniteMatrixCount: Int
    }

    private var loggedRuntimeSummaryKeys: Set<String> = []
    private var loggedRuntimeIssueKeys: Set<String> = []
    private var animationGraphDebugLoggingEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["MCE_ANIM_GRAPH_DEBUG"] == "1"
#else
        false
#endif
    }
    private struct TimingAverages {
        var updateMS: Double = 0
        var graphEvalMS: Double = 0
        var samplePoseMS: Double = 0
        var blendMS: Double = 0
        var localToGlobalMS: Double = 0
        var paletteMS: Double = 0
        var frameCount: Int = 0
    }
    private var timingAverages = TimingAverages()
    private var loggedTriggerDiagnosticsKeys: Set<String> = []
    private var lastStateMachineSignatureByKey: [String: String] = [:]
    private var loggedBlend2DDiagnosticsKeys: Set<String> = []
    private struct ClipDiagnosticState {
        var lastClipHandle: AssetHandle?
        var pendingSummaryClipHandle: AssetHandle?
    }
    private var clipDiagnosticStateByEntity: [UUID: ClipDiagnosticState] = [:]

    public struct SnapshotPreparation {
        public let skinnedEntityCount: Int
        public let payload: AnimationSnapshotPayload?

        public init(skinnedEntityCount: Int = 0, payload: AnimationSnapshotPayload? = nil) {
            self.skinnedEntityCount = skinnedEntityCount
            self.payload = payload
        }
    }

    public init() {}

    public func update(scene: EngineScene, dt: Float) {
        guard let assets = scene.engineContext?.assets else { return }
        let updateStart = CACurrentMediaTime()
        scene.ecs.viewDeterministic(AnimatorComponent.self) { entity, animator in
            var updated = animator
            let entityId = entity.id
            let skinnedMesh = scene.ecs.get(SkinnedMeshComponent.self, for: entity)
            let skeleton = skinnedMesh?.skeletonHandle.flatMap { assets.skeleton(handle: $0) }
            let useGraphMode = updated.evaluationMode == .graph && updated.graphHandle != nil
            if useGraphMode {
                evaluateGraphMode(scene: scene,
                                  assets: assets,
                                  entity: entity,
                                  dt: dt,
                                  skinnedMesh: skinnedMesh,
                                  skeleton: skeleton,
                                  animator: &updated)
                clipDiagnosticStateByEntity[entityId] = ClipDiagnosticState(lastClipHandle: nil, pendingSummaryClipHandle: nil)
            } else {
                evaluateClipMode(scene: scene,
                                 entity: entity,
                                 dt: dt,
                                 skinnedMesh: skinnedMesh,
                                 skeleton: skeleton,
                                 animator: &updated)
            }
            scene.ecs.add(updated, to: entity)
        }
        let updateElapsedMS = (CACurrentMediaTime() - updateStart) * 1000.0
        timingAverages.updateMS += updateElapsedMS
        timingAverages.frameCount += 1
        if timingAverages.frameCount >= 120 {
            let divisor = max(Double(timingAverages.frameCount), 1.0)
            logRuntimeIssueOnce(
                key: "animationPerfSummary",
                level: .debug,
                message: """
                AnimationSystem perf summary(avg over \(timingAverages.frameCount) frames)
                updateMS=\(timingAverages.updateMS / divisor)
                graphEvalMS=\(timingAverages.graphEvalMS / divisor)
                samplePoseMS=\(timingAverages.samplePoseMS / divisor)
                blendMS=\(timingAverages.blendMS / divisor)
                localToGlobalMS=\(timingAverages.localToGlobalMS / divisor)
                paletteMS=\(timingAverages.paletteMS / divisor)
                """
            )
            timingAverages = TimingAverages()
        }
    }

    public func prepareSnapshot(scene: EngineScene, layerFilterMask: LayerMask) -> SnapshotPreparation {
        guard let assets = scene.engineContext?.assets else {
            return SnapshotPreparation()
        }
        var skinnedEntries: [AnimationSnapshotPayload.SkinnedEntry] = []
        var bonePaletteMatrices: [matrix_float4x4] = []
        let skinnedCount = scene.ecs.viewTransformMeshRendererArray().reduce(into: 0) { count, entry in
            let layer = scene.ecs.get(LayerComponent.self, for: entry.0)?.index ?? LayerCatalog.defaultLayerIndex
            guard layerFilterMask.contains(layerIndex: layer) else { return }
            if let skinnedMesh = scene.ecs.get(SkinnedMeshComponent.self, for: entry.0) {
                let animator = scene.ecs.get(AnimatorComponent.self, for: entry.0)
                let paletteRange: AnimationSnapshotPayload.BonePaletteRange?
                if let skeletonHandle = skinnedMesh.skeletonHandle,
                   let skeleton = assets.skeleton(handle: skeletonHandle) {
                    let poseState = animator?.poseRuntimeState
                    let localPose = poseState?.localPose ?? []
                    let globalPose = poseState?.globalPose ?? []
                    let paletteStart = bonePaletteMatrices.count
                    let paletteStartTime = CACurrentMediaTime()
                    let paletteResult = makeBonePalette(skeleton: skeleton, globalPose: globalPose, assets: assets)
                    timingAverages.paletteMS += (CACurrentMediaTime() - paletteStartTime) * 1000.0
                    bonePaletteMatrices.append(contentsOf: paletteResult.matrices)
                    paletteRange = paletteResult.matrices.isEmpty
                        ? nil
                        : AnimationSnapshotPayload.BonePaletteRange(startIndex: paletteStart, count: paletteResult.matrices.count)
                    let activeClipHandle = animator?.clipHandle
                    let forceSummary = shouldForceRuntimeSummary(entityId: entry.0.id, clipHandle: activeClipHandle)
                    logRuntimeSummaryOnce(
                        engineContext: scene.engineContext,
                        entity: entry.0,
                        animator: animator,
                        skinnedMesh: skinnedMesh,
                        skeleton: skeleton,
                        clip: activeClipHandle.flatMap { assets.animationClip(handle: $0) },
                        mesh: scene.ecs.get(MeshRendererComponent.self, for: entry.0)?.meshHandle.flatMap { assets.mesh(handle: $0) },
                        localPose: localPose,
                        globalPose: globalPose,
                        evaluatedJointCount: globalPose.count,
                        bindPolicy: paletteResult.bindPolicy,
                        importedInverseBindCount: paletteResult.importedInverseBindCount,
                        nonFinitePaletteMatrixCount: paletteResult.nonFiniteMatrixCount,
                        forceLog: forceSummary
                    )
                    if forceSummary {
                        markRuntimeSummaryForcedHandled(entityId: entry.0.id, clipHandle: activeClipHandle)
                    }
                } else {
                    paletteRange = nil
                }
                skinnedEntries.append(
                    AnimationSnapshotPayload.SkinnedEntry(
                        entity: entry.0,
                        skeletonHandle: skinnedMesh.skeletonHandle,
                        clipHandle: animator?.clipHandle,
                        playbackTime: animator?.playbackTime ?? 0.0,
                        isPlaying: animator?.isPlaying ?? false,
                        evaluatedJointCount: animator?.poseRuntimeState?.globalPose.count ?? 0,
                        bonePaletteRange: paletteRange
                    )
                )
                count += 1
            }
        }
        let payload = skinnedEntries.isEmpty
            ? nil
            : AnimationSnapshotPayload(skinnedEntries: skinnedEntries, bonePaletteMatrices: bonePaletteMatrices)
        return SnapshotPreparation(skinnedEntityCount: skinnedCount, payload: payload)
    }

    private func makeBonePalette(skeleton: SkeletonAsset,
                                 globalPose: [TransformComponent],
                                 assets: AssetManager? = nil) -> BonePaletteBuildResult {
        let jointCount = min(skeleton.joints.count, globalPose.count)
        guard jointCount > 0 else {
            return BonePaletteBuildResult(matrices: [], bindPolicy: "none", importedInverseBindCount: 0, nonFiniteMatrixCount: 0)
        }

        let bindLocalPose: [TransformComponent] = skeleton.joints.map { joint in
            TransformComponent(position: joint.bindLocalPosition,
                               rotation: joint.bindLocalRotation,
                               scale: joint.bindLocalScale)
        }
        let bindGlobalMatrices = globalMatrices(from: bindLocalPose, skeleton: skeleton, assets: assets)

        var palette = Array(repeating: matrix_identity_float4x4, count: jointCount)
        var importedInverseBindCount = 0
        var nonFiniteMatrixCount = 0
        for jointIndex in 0..<jointCount {
            let pose = globalPose[jointIndex]
            let animatedGlobal = TransformMath.makeMatrix(position: pose.position,
                                                          rotation: pose.rotation,
                                                          scale: pose.scale)
            let inverseBind: matrix_float4x4
            if let imported = skeleton.joints[jointIndex].inverseBindGlobalMatrix,
               matrixIsFinite(imported) {
                inverseBind = imported
                importedInverseBindCount += 1
            } else {
                inverseBind = simd_inverse(bindGlobalMatrices[jointIndex])
            }
            let matrix = animatedGlobal * inverseBind
            if !matrixIsFinite(matrix) {
                nonFiniteMatrixCount += 1
            }
            palette[jointIndex] = matrix
        }
        let bindPolicy: String
        if importedInverseBindCount == 0 {
            bindPolicy = "reconstructedBindInverseOnly"
        } else if importedInverseBindCount == jointCount {
            bindPolicy = "importedInverseBindPreferred"
        } else {
            bindPolicy = "mixedImportedAndReconstructedInverseBind"
        }
        return BonePaletteBuildResult(
            matrices: palette,
            bindPolicy: bindPolicy,
            importedInverseBindCount: importedInverseBindCount,
            nonFiniteMatrixCount: nonFiniteMatrixCount
        )
    }

    private func nextPlaybackTime(current: Float,
                                  dt: Float,
                                  duration: Float,
                                  isLooping: Bool) -> Float {
        guard duration > 0 else { return max(0.0, current + dt) }
        let advanced = current + dt
        if isLooping {
            let wrapped = advanced.truncatingRemainder(dividingBy: duration)
            return wrapped >= 0 ? wrapped : (wrapped + duration)
        }
        return simd_clamp(advanced, 0.0, duration)
    }

    private func evaluateGraphMode(scene: EngineScene,
                                   assets: AssetManager,
                                   entity: Entity,
                                   dt: Float,
                                   skinnedMesh: SkinnedMeshComponent?,
                                   skeleton: SkeletonAsset?,
                                   animator: inout AnimatorComponent) {
        guard let graphHandle = animator.graphHandle else {
            animator.evaluationMode = .clip
            animator.graphRuntimeState = nil
            if let skeleton {
                animator.poseRuntimeState = makeBindPoseState(skeleton: skeleton,
                                                              playbackTime: animator.playbackTime,
                                                              assets: assets)
            } else {
                animator.poseRuntimeState = nil
            }
            return
        }

        guard let compiledGraph = assets.compiledAnimationGraph(handle: graphHandle) else {
            let graphPath = scene.engineContext?.assetDatabase?.assetURL(for: graphHandle)?.path ?? "<unresolved>"
            logRuntimeIssueOnce(
                key: "graphCompileFailure|\(entity.id.uuidString)|\(graphHandle.rawValue.uuidString)",
                message: "Animator graph compile/load failure entity=\(entity.id.uuidString)\nactiveGraphHandle=\(graphHandle.rawValue.uuidString)\nactiveGraphPath=\(graphPath)\naction=bindPoseOnly",
                level: .warning
            )
            if let skeleton {
                animator.poseRuntimeState = makeBindPoseState(skeleton: skeleton,
                                                              playbackTime: animator.playbackTime,
                                                              assets: assets)
            } else {
                animator.poseRuntimeState = nil
            }
            return
        }

        var runtimeState = animator.graphRuntimeState ?? AnimationGraphRuntimeInstanceState()
        if runtimeState.graphHandle != graphHandle || !runtimeState.hasParameterStorage(count: compiledGraph.parameters.count) {
            runtimeState.resetDefaults(from: compiledGraph, graphHandle: graphHandle)
        }

        let graphPath = scene.engineContext?.assetDatabase?.assetURL(for: graphHandle)?.path ?? "<unresolved>"
        guard let skeleton else {
            logRuntimeIssueOnce(
                key: "graphNoSkeleton|\(entity.id.uuidString)|\(graphHandle.rawValue.uuidString)",
                message: "Animator graph evaluation skipped entity=\(entity.id.uuidString)\nactiveGraphHandle=\(graphHandle.rawValue.uuidString)\nactiveGraphPath=\(graphPath)\nreason=missingSkeleton\nevaluatedPose=false",
                level: .warning
            )
            animator.poseRuntimeState = nil
            animator.graphRuntimeState = runtimeState
            return
        }

        guard let outputSourceNodeIndex = graphOutputSourceNodeIndex(compiledGraph: compiledGraph) else {
            logRuntimeIssueOnce(
                key: "graphNoOutputInput|\(entity.id.uuidString)|\(graphHandle.rawValue.uuidString)",
                message: "Animator graph evaluation fallback entity=\(entity.id.uuidString)\nactiveGraphHandle=\(graphHandle.rawValue.uuidString)\nactiveGraphPath=\(graphPath)\nactiveOutputNode=\(compiledGraph.nodes[compiledGraph.outputNodeIndex].id.uuidString)\nactiveOutputSourceNode=<none>\nreason=outputPoseHasNoIncomingLink\nevaluatedPose=false",
                level: .warning
            )
            animator.poseRuntimeState = makeBindPoseState(skeleton: skeleton,
                                                          playbackTime: animator.playbackTime,
                                                          assets: assets)
            animator.graphRuntimeState = runtimeState
            return
        }

        let sourceNode = compiledGraph.nodes[outputSourceNodeIndex]
        if animator.isPlaying, dt > 0 {
            let playbackStep = dt * max(0.0, animator.playbackSpeed)
            animator.playbackTime = max(0.0, animator.playbackTime + playbackStep)
            if runtimeState.transitionDurationSeconds > 0 {
                runtimeState.transitionElapsedSeconds = min(runtimeState.transitionDurationSeconds,
                                                            runtimeState.transitionElapsedSeconds + playbackStep)
            }
        }

        let rootSelection = resolveRootJointSelection(skeleton: skeleton, skinnedMesh: skinnedMesh)
        var evaluationContext = GraphEvaluationContext(compiledGraph: compiledGraph,
                                                       assets: assets,
                                                       skeleton: skeleton,
                                                       rootJointIndex: rootSelection.index,
                                                       rootBoneName: rootSelection.name,
                                                       entityID: entity.id,
                                                       graphHandle: graphHandle,
                                                       runtimeState: runtimeState,
                                                       isPlaying: animator.isPlaying,
                                                       deltaTime: dt * max(0.0, animator.playbackSpeed),
                                                       isLooping: animator.isLooping,
                                                       rootMotionTranslationJointOverride: nil,
                                                       rootMotionRotationJointOverride: nil)
        let graphEvalStart = CACurrentMediaTime()
        guard let graphResult = evaluateGraphNodePose(nodeIndex: outputSourceNodeIndex, context: &evaluationContext) else {
            logRuntimeIssueOnce(
                key: "graphEvalFailed|\(entity.id.uuidString)|\(graphHandle.rawValue.uuidString)|\(sourceNode.id.uuidString)",
                message: "Animator graph evaluation fallback entity=\(entity.id.uuidString)\nactiveGraphHandle=\(graphHandle.rawValue.uuidString)\nactiveGraphPath=\(graphPath)\nactiveOutputNode=\(compiledGraph.nodes[compiledGraph.outputNodeIndex].id.uuidString)\nactiveOutputSourceNode=\(sourceNode.id.uuidString)\nactiveOutputSourceType=\(sourceNode.type.rawValue)\nreason=nodeEvaluationFailed\nevaluatedPose=false",
                level: .warning
            )
            animator.poseRuntimeState = makeBindPoseState(skeleton: skeleton,
                                                          playbackTime: animator.playbackTime,
                                                          assets: assets)
            animator.graphRuntimeState = runtimeState
            return
        }
        let graphEvalElapsedMS = (CACurrentMediaTime() - graphEvalStart) * 1000.0

        runtimeState = evaluationContext.runtimeState
        runtimeState.currentStateNodeID = sourceNode.id
        animator.graphRuntimeState = runtimeState
        let localToGlobalStart = CACurrentMediaTime()
        animator.poseRuntimeState = makePoseState(skeleton: skeleton,
                                                  localPose: graphResult.localPose,
                                                  sampleTime: graphResult.sampleTime,
                                                  rootMotionDelta: graphResult.rootMotionDelta,
                                                  usesRootMotion: graphResult.usesRootMotion && animator.enableRootMotion,
                                                  currentStateName: graphResult.currentStateName,
                                                  rootMotionBoneName: graphResult.rootMotionBoneName,
                                                  rootMotionJointIndex: graphResult.rootMotionJointIndex,
                                                  rootMotionTrackConsumed: graphResult.rootMotionTrackConsumed,
                                                  rootMotionTranslationBoneName: graphResult.rootMotionTranslationBoneName,
                                                  rootMotionTranslationJointIndex: graphResult.rootMotionTranslationJointIndex,
                                                  rootMotionRotationBoneName: graphResult.rootMotionRotationBoneName,
                                                  rootMotionRotationJointIndex: graphResult.rootMotionRotationJointIndex,
                                                  rootMotionConsumeBoneName: graphResult.rootMotionConsumeBoneName,
                                                  rootMotionConsumeJointIndex: graphResult.rootMotionConsumeJointIndex,
                                                  assets: assets)
        let localToGlobalElapsedMS = (CACurrentMediaTime() - localToGlobalStart) * 1000.0
        timingAverages.graphEvalMS += graphEvalElapsedMS
        timingAverages.samplePoseMS += evaluationContext.samplePoseTimeMS
        timingAverages.blendMS += evaluationContext.blendTimeMS
        timingAverages.localToGlobalMS += localToGlobalElapsedMS
    }

    private func graphOutputSourceNodeIndex(compiledGraph: CompiledAnimationGraph) -> Int? {
        let candidates = compiledGraph.links
            .filter { $0.toNodeIndex == compiledGraph.outputNodeIndex }
            .sorted { lhs, rhs in
                if lhs.toSlotIndex == rhs.toSlotIndex {
                    return lhs.fromNodeIndex < rhs.fromNodeIndex
                }
                return lhs.toSlotIndex < rhs.toSlotIndex
            }
        return candidates.first?.fromNodeIndex
    }

    private struct GraphNodeEvaluationResult {
        let localPose: [TransformComponent]
        let sampleTime: Float
        let sampleDuration: Float
        let rootMotionDelta: RootMotionDelta
        let usesRootMotion: Bool
        let currentStateName: String
        let rootMotionBoneName: String
        let rootMotionJointIndex: Int
        let rootMotionTrackConsumed: Bool
        let rootMotionTranslationBoneName: String
        let rootMotionTranslationJointIndex: Int
        let rootMotionRotationBoneName: String
        let rootMotionRotationJointIndex: Int
        let rootMotionConsumeBoneName: String
        let rootMotionConsumeJointIndex: Int
        let diagnosticClipHandle: String?

        init(localPose: [TransformComponent],
             sampleTime: Float,
             sampleDuration: Float,
             rootMotionDelta: RootMotionDelta,
             usesRootMotion: Bool,
             currentStateName: String,
             rootMotionBoneName: String,
             rootMotionJointIndex: Int,
             rootMotionTrackConsumed: Bool,
             rootMotionTranslationBoneName: String = "",
             rootMotionTranslationJointIndex: Int = -1,
             rootMotionRotationBoneName: String = "",
             rootMotionRotationJointIndex: Int = -1,
             rootMotionConsumeBoneName: String = "",
             rootMotionConsumeJointIndex: Int = -1,
             diagnosticClipHandle: String?) {
            self.localPose = localPose
            self.sampleTime = sampleTime
            self.sampleDuration = sampleDuration
            self.rootMotionDelta = rootMotionDelta
            self.usesRootMotion = usesRootMotion
            self.currentStateName = currentStateName
            self.rootMotionBoneName = rootMotionBoneName
            self.rootMotionJointIndex = rootMotionJointIndex
            self.rootMotionTrackConsumed = rootMotionTrackConsumed
            self.rootMotionTranslationBoneName = rootMotionTranslationBoneName
            self.rootMotionTranslationJointIndex = rootMotionTranslationJointIndex
            self.rootMotionRotationBoneName = rootMotionRotationBoneName
            self.rootMotionRotationJointIndex = rootMotionRotationJointIndex
            self.rootMotionConsumeBoneName = rootMotionConsumeBoneName
            self.rootMotionConsumeJointIndex = rootMotionConsumeJointIndex
            self.diagnosticClipHandle = diagnosticClipHandle
        }
    }

    private struct RootMotionPolicy {
        let applyTranslation: Bool
        let applyRotation: Bool
        let consumeTranslation: Bool
        let consumeRotation: Bool
    }

    private struct RootMotionChannels {
        let translationJointIndex: Int
        let rotationJointIndex: Int
        let consumeJointIndex: Int
        let translationJointName: String
        let rotationJointName: String
        let consumeJointName: String
    }

    private struct NodeSampleTimes {
        let previous: Float
        let current: Float
    }

    private struct GraphEvaluationContext {
        let compiledGraph: CompiledAnimationGraph
        let assets: AssetManager
        let skeleton: SkeletonAsset
        let rootJointIndex: Int
        let rootBoneName: String
        let entityID: UUID
        let graphHandle: AnimationGraphHandle
        var runtimeState: AnimationGraphRuntimeInstanceState
        let isPlaying: Bool
        let deltaTime: Float
        let isLooping: Bool
        var rootMotionTranslationJointOverride: Int?
        var rootMotionRotationJointOverride: Int?
        var cache: [Int: GraphNodeEvaluationResult] = [:]
        var evaluationStack: Set<Int> = []
        var samplePoseTimeMS: Double = 0
        var blendTimeMS: Double = 0
    }

    private func evaluateGraphNodePose(nodeIndex: Int,
                                       context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        if let cached = context.cache[nodeIndex] {
            return cached
        }
        guard nodeIndex >= 0, nodeIndex < context.compiledGraph.nodes.count else { return nil }
        if context.evaluationStack.contains(nodeIndex) {
            return nil
        }
        context.evaluationStack.insert(nodeIndex)
        defer { context.evaluationStack.remove(nodeIndex) }
        let node = context.compiledGraph.nodes[nodeIndex]
        let result: GraphNodeEvaluationResult?
        switch node.type {
        case .clipPlayer:
            result = evaluateClipPlayerNode(node: node, context: &context)
        case .blend1D:
            result = evaluateBlend1DNode(node: node, context: &context)
        case .blend2D:
            result = evaluateBlend2DNode(node: node, context: &context)
        case .blendList,
             .layeredBlend,
             .select,
             .poseCache,
             .aimOffset,
             .lookAt,
             .twoBoneIK,
             .strideWarp,
             .orientationWarp,
             .motionMatch,
             .rootMotionModifier:
            result = evaluatePassThroughPoseNode(nodeIndex: nodeIndex, context: &context)
        case .additiveClip:
            result = evaluateClipPlayerNode(node: node, context: &context)
        case .stateMachine:
            result = evaluateStateMachineNode(node: node, context: &context)
        default:
            result = nil
        }
        if let result {
            context.cache[nodeIndex] = result
        }
        return result
    }

    private func evaluatePassThroughPoseNode(nodeIndex: Int,
                                             context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        let candidates = context.compiledGraph.links
            .filter { $0.toNodeIndex == nodeIndex }
            .sorted { lhs, rhs in
                if lhs.toSlotIndex == rhs.toSlotIndex {
                    return lhs.fromNodeIndex < rhs.fromNodeIndex
                }
                return lhs.toSlotIndex < rhs.toSlotIndex
            }
        for candidate in candidates {
            if let result = evaluateGraphNodePose(nodeIndex: candidate.fromNodeIndex, context: &context) {
                return result
            }
        }
        return nil
    }

    private func evaluateClipPlayerNode(node: CompiledAnimationGraph.Node,
                                        context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        guard let clipHandle = node.clipHandle,
              let clip = context.assets.animationClip(handle: clipHandle) else { return nil }
        let sampleTimes = advanceAndResolveNodeSampleTime(nodeID: node.id,
                                                          duration: clip.durationSeconds,
                                                          isLooping: context.isLooping,
                                                          context: &context)
        let sampleStart = CACurrentMediaTime()
        let localPose = evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTimes.current, assets: context.assets)
        context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
        let rootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                   clip: clip,
                                                   rootJointIndex: context.rootJointIndex,
                                                   translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                   rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                   previousTime: sampleTimes.previous,
                                                   currentTime: sampleTimes.current,
                                                   isLooping: context.isLooping,
                                                   assets: context.assets)
        return GraphNodeEvaluationResult(localPose: localPose,
                                         sampleTime: sampleTimes.current,
                                         sampleDuration: max(clip.durationSeconds, 0.0),
                                         rootMotionDelta: rootMotion,
                                         usesRootMotion: false,
                                         currentStateName: "",
                                         rootMotionBoneName: context.rootBoneName,
                                         rootMotionJointIndex: context.rootJointIndex,
                                         rootMotionTrackConsumed: false,
                                         diagnosticClipHandle: clipHandle.rawValue.uuidString)
    }

    private func evaluateBlend1DNode(node: CompiledAnimationGraph.Node,
                                     context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        guard let blend = node.blend1D, !blend.samples.isEmpty else { return nil }
        let parameterValue = graphParameterFloat(name: blend.parameterName,
                                                 compiledGraph: context.compiledGraph,
                                                 runtimeState: context.runtimeState)
        let sortedSamples = blend.samples.sorted { $0.threshold < $1.threshold }
        let representativeDuration = sortedSamples.reduce(Float(0.0)) { current, sample in
            guard let clip = context.assets.animationClip(handle: sample.clipHandle) else { return current }
            return max(current, clip.durationSeconds)
        }
        let nodeSampleTimes = advanceAndResolveNodeSampleTime(nodeID: node.id,
                                                              duration: representativeDuration,
                                                              isLooping: context.isLooping,
                                                              context: &context)

        let lowerUpper = neighboringBlend1DSamples(samples: sortedSamples, value: parameterValue)
        switch lowerUpper {
        case let (lower?, upper?) where lower.clipHandle == upper.clipHandle || abs(upper.threshold - lower.threshold) <= 1.0e-5:
            guard let clip = context.assets.animationClip(handle: lower.clipHandle) else { return nil }
            let sampleTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                   duration: clip.durationSeconds,
                                                   isLooping: context.isLooping)
            let previousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                     duration: clip.durationSeconds,
                                                     isLooping: context.isLooping)
            let sampleStart = CACurrentMediaTime()
            let localPose = evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTime, assets: context.assets)
            context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
            let rootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                       clip: clip,
                                                       rootJointIndex: context.rootJointIndex,
                                                       translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                       rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                       previousTime: previousTime,
                                                       currentTime: sampleTime,
                                                       isLooping: context.isLooping,
                                                       assets: context.assets)
            return GraphNodeEvaluationResult(localPose: localPose,
                                             sampleTime: sampleTime,
                                             sampleDuration: max(clip.durationSeconds, 0.0),
                                             rootMotionDelta: rootMotion,
                                             usesRootMotion: false,
                                             currentStateName: "",
                                             rootMotionBoneName: context.rootBoneName,
                                             rootMotionJointIndex: context.rootJointIndex,
                                             rootMotionTrackConsumed: false,
                                             diagnosticClipHandle: lower.clipHandle.rawValue.uuidString)
        case let (lower?, upper?):
            guard let lowerClip = context.assets.animationClip(handle: lower.clipHandle),
                  let upperClip = context.assets.animationClip(handle: upper.clipHandle) else { return nil }
            let t = simd_clamp((parameterValue - lower.threshold) / max(upper.threshold - lower.threshold, 1.0e-5), 0.0, 1.0)
            let lowerTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                  duration: lowerClip.durationSeconds,
                                                  isLooping: context.isLooping)
            let upperTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                  duration: upperClip.durationSeconds,
                                                  isLooping: context.isLooping)
            let lowerPreviousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                          duration: lowerClip.durationSeconds,
                                                          isLooping: context.isLooping)
            let upperPreviousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                          duration: upperClip.durationSeconds,
                                                          isLooping: context.isLooping)
            let sampleStart = CACurrentMediaTime()
            let lowerLocalPose = evaluateLocalPose(skeleton: context.skeleton, clip: lowerClip, playbackTime: lowerTime, assets: context.assets)
            let upperLocalPose = evaluateLocalPose(skeleton: context.skeleton, clip: upperClip, playbackTime: upperTime, assets: context.assets)
            context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
            let lowerRootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                            clip: lowerClip,
                                                            rootJointIndex: context.rootJointIndex,
                                                            translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                            rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                            previousTime: lowerPreviousTime,
                                                            currentTime: lowerTime,
                                                            isLooping: context.isLooping,
                                                            assets: context.assets)
            let upperRootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                            clip: upperClip,
                                                            rootJointIndex: context.rootJointIndex,
                                                            translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                            rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                            previousTime: upperPreviousTime,
                                                            currentTime: upperTime,
                                                            isLooping: context.isLooping,
                                                            assets: context.assets)
            let blendStart = CACurrentMediaTime()
            let blendedLocal = blendLocalPoses(lowerLocalPose,
                                               upperLocalPose,
                                               weight: t,
                                               skeleton: context.skeleton,
                                               assets: context.assets)
            let blendedRootMotion = blendRootMotionDeltas(lowerRootMotion, upperRootMotion, weight: t)
            context.blendTimeMS += (CACurrentMediaTime() - blendStart) * 1000.0
            return GraphNodeEvaluationResult(localPose: blendedLocal,
                                             sampleTime: nodeSampleTimes.current,
                                             sampleDuration: max(representativeDuration, 0.0),
                                             rootMotionDelta: blendedRootMotion,
                                             usesRootMotion: false,
                                             currentStateName: "",
                                             rootMotionBoneName: context.rootBoneName,
                                             rootMotionJointIndex: context.rootJointIndex,
                                             rootMotionTrackConsumed: false,
                                             diagnosticClipHandle: "\(lower.clipHandle.rawValue.uuidString),\(upper.clipHandle.rawValue.uuidString)")
        case let (single?, nil), let (nil, single?):
            guard let clip = context.assets.animationClip(handle: single.clipHandle) else { return nil }
            let sampleTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                   duration: clip.durationSeconds,
                                                   isLooping: context.isLooping)
            let previousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                     duration: clip.durationSeconds,
                                                     isLooping: context.isLooping)
            let sampleStart = CACurrentMediaTime()
            let localPose = evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTime, assets: context.assets)
            context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
            let rootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                       clip: clip,
                                                       rootJointIndex: context.rootJointIndex,
                                                       translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                       rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                       previousTime: previousTime,
                                                       currentTime: sampleTime,
                                                       isLooping: context.isLooping,
                                                       assets: context.assets)
            return GraphNodeEvaluationResult(localPose: localPose,
                                             sampleTime: sampleTime,
                                             sampleDuration: max(clip.durationSeconds, 0.0),
                                             rootMotionDelta: rootMotion,
                                             usesRootMotion: false,
                                             currentStateName: "",
                                             rootMotionBoneName: context.rootBoneName,
                                             rootMotionJointIndex: context.rootJointIndex,
                                             rootMotionTrackConsumed: false,
                                             diagnosticClipHandle: single.clipHandle.rawValue.uuidString)
        default:
            return nil
        }
    }

    private func evaluateBlend2DNode(node: CompiledAnimationGraph.Node,
                                     context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        guard let blend = node.blend2D, !blend.samples.isEmpty else { return nil }
        let px = graphParameterFloat(name: blend.parameterXName,
                                     compiledGraph: context.compiledGraph,
                                     runtimeState: context.runtimeState)
        let py = graphParameterFloat(name: blend.parameterYName,
                                     compiledGraph: context.compiledGraph,
                                     runtimeState: context.runtimeState)
        let originalPoint = SIMD2<Float>(px, py)
        var parameterPoint = originalPoint
        let locomotionNode = isLocomotionBlendNode(node)
        let cardinalStrafeIntent = locomotionNode
            && abs(parameterPoint.x) >= 0.75
            && abs(parameterPoint.y) <= 0.2
        // For pure cardinal strafe, lock to exact side sample to prevent forward contamination.
        if cardinalStrafeIntent {
            parameterPoint = SIMD2<Float>(parameterPoint.x < 0.0 ? -1.0 : 1.0, 0.0)
        } else if locomotionNode,
                  abs(parameterPoint.x) >= 0.85,
                  abs(parameterPoint.y) <= 0.15 {
            parameterPoint.y = 0.0
        }

        let representativeDuration = blend.samples.reduce(Float(0.0)) { current, sample in
            guard let clip = context.assets.animationClip(handle: sample.clipHandle) else { return current }
            return max(current, clip.durationSeconds)
        }
        let nodeSampleTimes = advanceAndResolveNodeSampleTime(nodeID: node.id,
                                                              duration: representativeDuration,
                                                              isLooping: context.isLooping,
                                                              context: &context)

        var localPoses: [[TransformComponent]] = []
        var rootMotions: [RootMotionDelta] = []
        var weights: [Float] = []
        var diagnosticHandles: [String] = []
        let epsilon: Float = 1.0e-4
        var exactMatchHandle: AssetHandle?
        for sample in blend.samples {
            let delta = parameterPoint - sample.position
            let distance = simd_length(delta)
            if distance <= epsilon {
                exactMatchHandle = sample.clipHandle
                break
            }
        }

        if let exactMatchHandle, let clip = context.assets.animationClip(handle: exactMatchHandle) {
            let sampleTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                   duration: clip.durationSeconds,
                                                   isLooping: context.isLooping)
            let previousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                     duration: clip.durationSeconds,
                                                     isLooping: context.isLooping)
            let sampleStart = CACurrentMediaTime()
            let localPose = evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTime, assets: context.assets)
            context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
            let sampledRootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                              clip: clip,
                                                              rootJointIndex: context.rootJointIndex,
                                                              translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                              rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                              previousTime: previousTime,
                                                              currentTime: sampleTime,
                                                              isLooping: context.isLooping,
                                                              assets: context.assets)
            let rootMotion = cardinalStrafeIntent
                ? constrainCardinalStrafeRootMotion(sampledRootMotion, inputX: originalPoint.x)
                : sampledRootMotion
            maybeLogLocomotionBlendSelection(node: node,
                                             originalPoint: originalPoint,
                                             adjustedPoint: parameterPoint,
                                             samples: ["\(clip.name)=1.0"],
                                             blendedDelta: rootMotion,
                                             context: context,
                                             cardinalStrafeIntent: cardinalStrafeIntent)
            return GraphNodeEvaluationResult(localPose: localPose,
                                             sampleTime: sampleTime,
                                             sampleDuration: max(clip.durationSeconds, 0.0),
                                             rootMotionDelta: rootMotion,
                                             usesRootMotion: false,
                                             currentStateName: "",
                                             rootMotionBoneName: context.rootBoneName,
                                             rootMotionJointIndex: context.rootJointIndex,
                                             rootMotionTrackConsumed: false,
                                             diagnosticClipHandle: exactMatchHandle.rawValue.uuidString)
        }

        let nearestSamples = blend.samples
            .sorted { lhs, rhs in
                let lhsDistance = simd_length_squared(parameterPoint - lhs.position)
                let rhsDistance = simd_length_squared(parameterPoint - rhs.position)
                return lhsDistance < rhsDistance
            }
            .prefix(4)
        var weightedDiagnostics: [(name: String, weight: Float)] = []
        let sampleStart = CACurrentMediaTime()
        for sample in nearestSamples {
            guard let clip = context.assets.animationClip(handle: sample.clipHandle) else { continue }
            let delta = parameterPoint - sample.position
            let distance = max(simd_length(delta), epsilon)
            let weight = 1.0 / distance
            let sampleTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.current,
                                                   duration: clip.durationSeconds,
                                                   isLooping: context.isLooping)
            let previousTime = resolveClipSampleTime(nodeTime: nodeSampleTimes.previous,
                                                     duration: clip.durationSeconds,
                                                     isLooping: context.isLooping)
            localPoses.append(evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTime, assets: context.assets))
            rootMotions.append(sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                         clip: clip,
                                                         rootJointIndex: context.rootJointIndex,
                                                         translationJointIndexOverride: context.rootMotionTranslationJointOverride,
                                                         rotationJointIndexOverride: context.rootMotionRotationJointOverride,
                                                         previousTime: previousTime,
                                                         currentTime: sampleTime,
                                                         isLooping: context.isLooping,
                                                         assets: context.assets))
            weights.append(weight)
            weightedDiagnostics.append((clip.name, weight))
            diagnosticHandles.append(sample.clipHandle.rawValue.uuidString)
        }
        context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0

        guard !localPoses.isEmpty else { return nil }
        let blendStart = CACurrentMediaTime()
        let blendedLocal = blendLocalPoses(localPoses: localPoses,
                                           weights: weights,
                                           skeleton: context.skeleton,
                                           assets: context.assets)
        let sampledBlendedRootMotion = blendRootMotionDeltas(rootMotions, weights: weights)
        let blendedRootMotion = cardinalStrafeIntent
            ? constrainCardinalStrafeRootMotion(sampledBlendedRootMotion, inputX: originalPoint.x)
            : sampledBlendedRootMotion
        let sampleSummary = weightedDiagnostics.map { "\($0.name)=\($0.weight)" }
        maybeLogLocomotionBlendSelection(node: node,
                                         originalPoint: originalPoint,
                                         adjustedPoint: parameterPoint,
                                         samples: sampleSummary,
                                         blendedDelta: blendedRootMotion,
                                         context: context,
                                         cardinalStrafeIntent: cardinalStrafeIntent)
        maybeLogBlend2DDiagnostics(node: node,
                                   point: parameterPoint,
                                   originalPoint: originalPoint,
                                   weights: sampleSummary,
                                   blendedDelta: blendedRootMotion,
                                   context: context)
        context.blendTimeMS += (CACurrentMediaTime() - blendStart) * 1000.0
        return GraphNodeEvaluationResult(localPose: blendedLocal,
                                         sampleTime: nodeSampleTimes.current,
                                         sampleDuration: max(representativeDuration, 0.0),
                                         rootMotionDelta: blendedRootMotion,
                                         usesRootMotion: false,
                                         currentStateName: "",
                                         rootMotionBoneName: context.rootBoneName,
                                         rootMotionJointIndex: context.rootJointIndex,
                                         rootMotionTrackConsumed: false,
                                         diagnosticClipHandle: diagnosticHandles.joined(separator: ","))
    }

    private func advanceAndResolveNodeSampleTime(nodeID: UUID,
                                                 duration: Float,
                                                 isLooping: Bool,
                                                 context: inout GraphEvaluationContext) -> NodeSampleTimes {
        let stored = context.runtimeState.nodeLocalTimes[nodeID] ?? 0.0
        let current = resolveClipSampleTime(nodeTime: stored,
                                            duration: duration,
                                            isLooping: isLooping)
        let next: Float
        if context.isPlaying, context.deltaTime > 0 {
            next = nextPlaybackTime(current: current,
                                    dt: context.deltaTime,
                                    duration: duration,
                                    isLooping: isLooping)
        } else {
            next = current
        }
        context.runtimeState.nodeLocalTimes[nodeID] = next
        return NodeSampleTimes(previous: current, current: next)
    }

    private func resolveClipSampleTime(nodeTime: Float,
                                       duration: Float,
                                       isLooping: Bool) -> Float {
        return nextPlaybackTime(current: nodeTime, dt: 0.0, duration: duration, isLooping: isLooping)
    }

    private func neighboringBlend1DSamples(samples: [AnimationGraphBlend1DSampleDefinition],
                                           value: Float) -> (AnimationGraphBlend1DSampleDefinition?, AnimationGraphBlend1DSampleDefinition?) {
        guard !samples.isEmpty else { return (nil, nil) }
        if samples.count == 1 { return (samples[0], nil) }
        if value <= samples[0].threshold { return (samples[0], nil) }
        if value >= samples[samples.count - 1].threshold { return (samples[samples.count - 1], nil) }
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            if value >= a.threshold && value <= b.threshold {
                return (a, b)
            }
        }
        return (samples[samples.count - 1], nil)
    }

    private func evaluateStateMachineNode(node: CompiledAnimationGraph.Node,
                                          context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        guard let machine = node.stateMachine, !machine.states.isEmpty else { return nil }
        guard let currentState = resolveStateMachineCurrentState(machine: machine, stateMachineNodeID: node.id, context: &context) else {
            return nil
        }

        guard let currentStatePose = evaluateStateMachineStatePose(state: currentState, stateMachineNodeID: node.id, context: &context) else {
            return nil
        }
        let currentNormalizedTime = stateNormalizedTime(for: currentStatePose)

        if let nextStateID = context.runtimeState.stateMachineNextStateByNodeID[node.id],
           let nextState = machine.states.first(where: { $0.id == nextStateID }) {
            var transitionElapsed = context.runtimeState.stateMachineTransitionElapsedByNodeID[node.id] ?? 0.0
            let transitionDuration = max(context.runtimeState.stateMachineTransitionDurationByNodeID[node.id] ?? 0.0, 0.0)
            if context.isPlaying, context.deltaTime > 0 {
                transitionElapsed += context.deltaTime
            }
            let alpha = transitionDuration <= 1.0e-5 ? 1.0 : simd_clamp(transitionElapsed / transitionDuration, 0.0, 1.0)

            guard let nextStatePose = evaluateStateMachineStatePose(state: nextState, stateMachineNodeID: node.id, context: &context) else {
                context.runtimeState.stateMachineNextStateByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionElapsedByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionDurationByNodeID.removeValue(forKey: node.id)
                return currentStatePose
            }

            let blendedLocal = blendLocalPoses(currentStatePose.localPose,
                                               nextStatePose.localPose,
                                               weight: alpha,
                                               skeleton: context.skeleton,
                                               assets: context.assets)
            let blendedRootMotion = blendRootMotionDeltas(currentStatePose.rootMotionDelta,
                                                          nextStatePose.rootMotionDelta,
                                                          weight: alpha)
            if alpha >= 1.0 - 1.0e-5 {
                context.runtimeState.stateMachineCurrentStateByNodeID[node.id] = nextState.id
                context.runtimeState.stateMachineNextStateByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionElapsedByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionDurationByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineStateElapsedByNodeID[node.id] = 0.0
                resetStateMachineEntryPlayback(stateMachineNodeID: node.id, state: nextState, context: &context)
                emitStateMachineDiagnostic(node: node, machine: machine, context: &context, reason: "transitionCompleted")
            } else {
                context.runtimeState.stateMachineTransitionElapsedByNodeID[node.id] = transitionElapsed
            }

            let duration = max(currentStatePose.sampleDuration, nextStatePose.sampleDuration)
            let reportedPose = alpha >= 0.5 ? nextStatePose : currentStatePose
            return GraphNodeEvaluationResult(localPose: blendedLocal,
                                             sampleTime: reportedPose.sampleTime,
                                             sampleDuration: duration,
                                             rootMotionDelta: blendedRootMotion,
                                             usesRootMotion: currentStatePose.usesRootMotion || nextStatePose.usesRootMotion,
                                             currentStateName: reportedPose.currentStateName,
                                             rootMotionBoneName: reportedPose.rootMotionBoneName,
                                             rootMotionJointIndex: reportedPose.rootMotionJointIndex,
                                             rootMotionTrackConsumed: currentStatePose.rootMotionTrackConsumed || nextStatePose.rootMotionTrackConsumed,
                                             rootMotionTranslationBoneName: reportedPose.rootMotionTranslationBoneName,
                                             rootMotionTranslationJointIndex: reportedPose.rootMotionTranslationJointIndex,
                                             rootMotionRotationBoneName: reportedPose.rootMotionRotationBoneName,
                                             rootMotionRotationJointIndex: reportedPose.rootMotionRotationJointIndex,
                                             rootMotionConsumeBoneName: reportedPose.rootMotionConsumeBoneName,
                                             rootMotionConsumeJointIndex: reportedPose.rootMotionConsumeJointIndex,
                                             diagnosticClipHandle: [currentStatePose.diagnosticClipHandle, nextStatePose.diagnosticClipHandle]
                                                .compactMap { $0 }
                                                .joined(separator: ","))
        }

        if context.isPlaying, context.deltaTime > 0 {
            let elapsed = (context.runtimeState.stateMachineStateElapsedByNodeID[node.id] ?? 0.0) + context.deltaTime
            context.runtimeState.stateMachineStateElapsedByNodeID[node.id] = elapsed
        }

        if let transition = firstPassingTransition(machine: machine,
                                                   fromStateID: currentState.id,
                                                   currentNormalizedTime: currentNormalizedTime,
                                                   context: &context),
           let destinationState = machine.states.first(where: { $0.id == transition.toStateID }) {
            let transitionDuration = max(transition.durationSeconds, 0.0)
            if transitionDuration <= 1.0e-5 {
                context.runtimeState.stateMachineCurrentStateByNodeID[node.id] = destinationState.id
                context.runtimeState.stateMachineStateElapsedByNodeID[node.id] = 0.0
                context.runtimeState.stateMachineNextStateByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionElapsedByNodeID.removeValue(forKey: node.id)
                context.runtimeState.stateMachineTransitionDurationByNodeID.removeValue(forKey: node.id)
                resetStateMachineEntryPlayback(stateMachineNodeID: node.id, state: destinationState, context: &context)
                emitStateMachineDiagnostic(node: node, machine: machine, context: &context, reason: "transitionInstant")
                return evaluateStateMachineStatePose(state: destinationState, stateMachineNodeID: node.id, context: &context)
            }

            context.runtimeState.stateMachineNextStateByNodeID[node.id] = destinationState.id
            context.runtimeState.stateMachineTransitionElapsedByNodeID[node.id] = 0.0
            context.runtimeState.stateMachineTransitionDurationByNodeID[node.id] = transitionDuration
            resetStateMachineEntryPlayback(stateMachineNodeID: node.id, state: destinationState, context: &context)
            emitStateMachineDiagnostic(node: node, machine: machine, context: &context, reason: "transitionStarted")
            if let destinationPose = evaluateStateMachineStatePose(state: destinationState, stateMachineNodeID: node.id, context: &context) {
                if destinationState.name.caseInsensitiveCompare("JumpStart") == .orderedSame {
                    let sourceName = currentState.name.isEmpty ? currentState.id.uuidString : currentState.name
                    let destinationName = destinationState.name.isEmpty ? destinationState.id.uuidString : destinationState.name
                    EngineLoggerContext.log(
                        "Animator JumpStart entry sourceState=\(sourceName) destinationState=\(destinationName) entryPlaybackTime=\(destinationPose.sampleTime) normalized=\(stateNormalizedTime(for: destinationPose)) entity=\(context.entityID.uuidString)",
                        level: .debug,
                        category: .scene
                    )
                }
                let blendedLocal = blendLocalPoses(currentStatePose.localPose,
                                                   destinationPose.localPose,
                                                   weight: 0.0,
                                                   skeleton: context.skeleton,
                                                   assets: context.assets)
                return GraphNodeEvaluationResult(localPose: blendedLocal,
                                                 sampleTime: currentStatePose.sampleTime,
                                                 sampleDuration: max(currentStatePose.sampleDuration, destinationPose.sampleDuration),
                                                 rootMotionDelta: blendRootMotionDeltas(currentStatePose.rootMotionDelta,
                                                                                        destinationPose.rootMotionDelta,
                                                                                        weight: 0.0),
                                                 usesRootMotion: currentStatePose.usesRootMotion || destinationPose.usesRootMotion,
                                                 currentStateName: currentStatePose.currentStateName,
                                                 rootMotionBoneName: currentStatePose.rootMotionBoneName,
                                                 rootMotionJointIndex: currentStatePose.rootMotionJointIndex,
                                                 rootMotionTrackConsumed: currentStatePose.rootMotionTrackConsumed || destinationPose.rootMotionTrackConsumed,
                                                 rootMotionTranslationBoneName: currentStatePose.rootMotionTranslationBoneName,
                                                 rootMotionTranslationJointIndex: currentStatePose.rootMotionTranslationJointIndex,
                                                 rootMotionRotationBoneName: currentStatePose.rootMotionRotationBoneName,
                                                 rootMotionRotationJointIndex: currentStatePose.rootMotionRotationJointIndex,
                                                 rootMotionConsumeBoneName: currentStatePose.rootMotionConsumeBoneName,
                                                 rootMotionConsumeJointIndex: currentStatePose.rootMotionConsumeJointIndex,
                                                 diagnosticClipHandle: [currentStatePose.diagnosticClipHandle, destinationPose.diagnosticClipHandle]
                                                    .compactMap { $0 }
                                                    .joined(separator: ","))
            }
        }

        return currentStatePose
    }

    private func emitStateMachineDiagnostic(node: CompiledAnimationGraph.Node,
                                            machine: AnimationGraphStateMachineScaffold,
                                            context: inout GraphEvaluationContext,
                                            reason: String) {
        guard animationGraphDebugLoggingEnabled else { return }
        let nextStateName: String
        if let nextStateID = context.runtimeState.stateMachineNextStateByNodeID[node.id],
           let nextState = machine.states.first(where: { $0.id == nextStateID }) {
            nextStateName = nextState.name.isEmpty ? nextState.id.uuidString : nextState.name
        } else {
            nextStateName = "<none>"
        }
        let currentStateName: String
        if let currentStateID = context.runtimeState.stateMachineCurrentStateByNodeID[node.id],
           let currentState = machine.states.first(where: { $0.id == currentStateID }) {
            currentStateName = currentState.name.isEmpty ? currentState.id.uuidString : currentState.name
        } else {
            currentStateName = "<unset>"
        }
        logStateMachineSignatureIfChanged(entityID: context.entityID,
                                          graphHandle: context.graphHandle,
                                          nodeID: node.id,
                                          currentStateName: currentStateName,
                                          nextStateName: nextStateName,
                                          reason: reason)
    }

    private func resolveStateMachineCurrentState(machine: AnimationGraphStateMachineScaffold,
                                                 stateMachineNodeID: UUID,
                                                 context: inout GraphEvaluationContext) -> AnimationGraphStateDefinition? {
        if let currentStateID = context.runtimeState.stateMachineCurrentStateByNodeID[stateMachineNodeID],
           let currentState = machine.states.first(where: { $0.id == currentStateID }) {
            return currentState
        }
        let fallbackState: AnimationGraphStateDefinition?
        if let defaultStateID = machine.defaultStateID {
            fallbackState = machine.states.first(where: { $0.id == defaultStateID })
        } else {
            fallbackState = machine.states.first
        }
        if let fallbackState {
            context.runtimeState.stateMachineCurrentStateByNodeID[stateMachineNodeID] = fallbackState.id
            context.runtimeState.stateMachineStateElapsedByNodeID[stateMachineNodeID] = 0.0
            resetStateMachineEntryPlayback(stateMachineNodeID: stateMachineNodeID, state: fallbackState, context: &context)
        }
        return fallbackState
    }

    private func resetStateMachineEntryPlayback(stateMachineNodeID: UUID,
                                                state: AnimationGraphStateDefinition,
                                                context: inout GraphEvaluationContext) {
        context.runtimeState.nodeLocalTimes[state.id] = 0.0
        if let nodeID = state.nodeID {
            context.runtimeState.nodeLocalTimes[nodeID] = 0.0
            if let nodeIndex = context.compiledGraph.nodes.firstIndex(where: { $0.id == nodeID }) {
                context.cache.removeValue(forKey: nodeIndex)
            }
        }
        if let machineNodeIndex = context.compiledGraph.nodes.firstIndex(where: { $0.id == stateMachineNodeID }) {
            context.cache.removeValue(forKey: machineNodeIndex)
        }
    }

    private func evaluateStateMachineStatePose(state: AnimationGraphStateDefinition,
                                               stateMachineNodeID: UUID,
                                               context: inout GraphEvaluationContext) -> GraphNodeEvaluationResult? {
        let policy = rootMotionPolicy(for: state)
        let stateChannels = resolveStateRootMotionChannels(state: state,
                                                           skeleton: context.skeleton,
                                                           clip: state.clipHandle.flatMap { context.assets.animationClip(handle: $0) },
                                                           preferredRootJointIndex: context.rootJointIndex)
        let hasExplicitConsumeJoint = !(state.rootMotion?.consumeJointName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let consumeTranslationJointIndex = hasExplicitConsumeJoint ? stateChannels.consumeJointIndex : stateChannels.translationJointIndex
        let consumeRotationJointIndex = hasExplicitConsumeJoint ? stateChannels.consumeJointIndex : stateChannels.rotationJointIndex
        let previousTranslationOverride = context.rootMotionTranslationJointOverride
        let previousRotationOverride = context.rootMotionRotationJointOverride
        context.rootMotionTranslationJointOverride = stateChannels.translationJointIndex
        context.rootMotionRotationJointOverride = stateChannels.rotationJointIndex
        defer {
            context.rootMotionTranslationJointOverride = previousTranslationOverride
            context.rootMotionRotationJointOverride = previousRotationOverride
        }

        if let stateNodeID = state.nodeID {
            guard let nodeIndex = context.compiledGraph.nodes.firstIndex(where: { $0.id == stateNodeID }) else { return nil }
            guard context.compiledGraph.nodes[nodeIndex].id != stateMachineNodeID else { return nil }
            guard let evaluated = evaluateGraphNodePose(nodeIndex: nodeIndex, context: &context) else { return nil }
            let filteredRootMotion = RootMotionDelta(
                deltaPos: policy.applyTranslation ? evaluated.rootMotionDelta.deltaPos : .zero,
                deltaRot: policy.applyRotation ? evaluated.rootMotionDelta.deltaRot : TransformMath.identityQuaternion
            )
            let consumedPose = state.usesRootMotion
                ? consumeRootMotionTracks(in: evaluated.localPose,
                                          skeleton: context.skeleton,
                                          translationJointIndex: consumeTranslationJointIndex,
                                          rotationJointIndex: consumeRotationJointIndex,
                                          consumeTranslation: policy.consumeTranslation,
                                          consumeRotation: policy.consumeRotation)
                : evaluated.localPose
            return GraphNodeEvaluationResult(localPose: consumedPose,
                                             sampleTime: evaluated.sampleTime,
                                             sampleDuration: evaluated.sampleDuration,
                                             rootMotionDelta: filteredRootMotion,
                                             usesRootMotion: state.usesRootMotion,
                                             currentStateName: state.name,
                                             rootMotionBoneName: stateChannels.consumeJointName,
                                             rootMotionJointIndex: stateChannels.consumeJointIndex,
                                             rootMotionTrackConsumed: state.usesRootMotion && (policy.consumeTranslation || policy.consumeRotation),
                                             rootMotionTranslationBoneName: stateChannels.translationJointName,
                                             rootMotionTranslationJointIndex: stateChannels.translationJointIndex,
                                             rootMotionRotationBoneName: stateChannels.rotationJointName,
                                             rootMotionRotationJointIndex: stateChannels.rotationJointIndex,
                                             rootMotionConsumeBoneName: stateChannels.consumeJointName,
                                             rootMotionConsumeJointIndex: stateChannels.consumeJointIndex,
                                             diagnosticClipHandle: evaluated.diagnosticClipHandle)
        }

        guard let clipHandle = state.clipHandle,
              let clip = context.assets.animationClip(handle: clipHandle) else { return nil }
        let shouldLoop = state.isOneShot ? false : context.isLooping
        let sampleTimes = advanceAndResolveNodeSampleTime(nodeID: state.id,
                                                          duration: clip.durationSeconds,
                                                          isLooping: shouldLoop,
                                                          context: &context)
        let sampleStart = CACurrentMediaTime()
        let localPose = evaluateLocalPose(skeleton: context.skeleton, clip: clip, playbackTime: sampleTimes.current, assets: context.assets)
        context.samplePoseTimeMS += (CACurrentMediaTime() - sampleStart) * 1000.0
        let rootMotion = sampleClipRootMotionDelta(skeleton: context.skeleton,
                                                   clip: clip,
                                                   rootJointIndex: context.rootJointIndex,
                                                   translationJointIndexOverride: stateChannels.translationJointIndex,
                                                   rotationJointIndexOverride: stateChannels.rotationJointIndex,
                                                   previousTime: sampleTimes.previous,
                                                   currentTime: sampleTimes.current,
                                                   isLooping: shouldLoop,
                                                   assets: context.assets)
        let filteredRootMotion = RootMotionDelta(
            deltaPos: policy.applyTranslation ? rootMotion.deltaPos : .zero,
            deltaRot: policy.applyRotation ? rootMotion.deltaRot : TransformMath.identityQuaternion
        )
        let outputPose = state.usesRootMotion
            ? consumeRootMotionTracks(in: localPose,
                                      skeleton: context.skeleton,
                                      translationJointIndex: consumeTranslationJointIndex,
                                      rotationJointIndex: consumeRotationJointIndex,
                                      consumeTranslation: policy.consumeTranslation,
                                      consumeRotation: policy.consumeRotation)
            : localPose
        return GraphNodeEvaluationResult(localPose: outputPose,
                                         sampleTime: sampleTimes.current,
                                         sampleDuration: max(clip.durationSeconds, 0.0),
                                         rootMotionDelta: filteredRootMotion,
                                         usesRootMotion: state.usesRootMotion,
                                         currentStateName: state.name,
                                         rootMotionBoneName: stateChannels.consumeJointName,
                                         rootMotionJointIndex: stateChannels.consumeJointIndex,
                                         rootMotionTrackConsumed: state.usesRootMotion && (policy.consumeTranslation || policy.consumeRotation),
                                         rootMotionTranslationBoneName: stateChannels.translationJointName,
                                         rootMotionTranslationJointIndex: stateChannels.translationJointIndex,
                                         rootMotionRotationBoneName: stateChannels.rotationJointName,
                                         rootMotionRotationJointIndex: stateChannels.rotationJointIndex,
                                         rootMotionConsumeBoneName: stateChannels.consumeJointName,
                                         rootMotionConsumeJointIndex: stateChannels.consumeJointIndex,
                                         diagnosticClipHandle: clipHandle.rawValue.uuidString)
    }

    private func rootMotionPolicy(for state: AnimationGraphStateDefinition) -> RootMotionPolicy {
        guard state.usesRootMotion else {
            return RootMotionPolicy(applyTranslation: false,
                                    applyRotation: false,
                                    consumeTranslation: false,
                                    consumeRotation: false)
        }
        if let configured = state.rootMotion {
            return RootMotionPolicy(applyTranslation: configured.applyTranslation ?? true,
                                    applyRotation: configured.applyRotation ?? true,
                                    consumeTranslation: configured.consumeTranslation ?? true,
                                    consumeRotation: configured.consumeRotation ?? true)
        }
        let normalized = state.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("turn") {
            return RootMotionPolicy(applyTranslation: false,
                                    applyRotation: true,
                                    consumeTranslation: false,
                                    consumeRotation: true)
        }
        if normalized.contains("locomotion") {
            return RootMotionPolicy(applyTranslation: true,
                                    applyRotation: false,
                                    consumeTranslation: true,
                                    consumeRotation: false)
        }
        return RootMotionPolicy(applyTranslation: true,
                                applyRotation: true,
                                consumeTranslation: true,
                                consumeRotation: true)
    }

    private func resolveStateRootMotionChannels(state: AnimationGraphStateDefinition,
                                                skeleton: SkeletonAsset,
                                                clip: AnimationClipAsset?,
                                                preferredRootJointIndex: Int) -> RootMotionChannels {
        let translationConfiguredIndex = state.rootMotion?.translationSourceJointName.flatMap {
            jointIndex(named: $0, skeleton: skeleton)
        }
        let rotationConfiguredIndex = state.rootMotion?.rotationSourceJointName.flatMap {
            jointIndex(named: $0, skeleton: skeleton)
        }
        let consumeConfiguredIndex = state.rootMotion?.consumeJointName.flatMap {
            jointIndex(named: $0, skeleton: skeleton)
        }
        let channelPair: (translationJointIndex: Int, rotationJointIndex: Int)
        if let clip {
            channelPair = resolveRootMotionChannels(skeleton: skeleton,
                                                    clip: clip,
                                                    preferredRootJointIndex: preferredRootJointIndex,
                                                    translationJointIndexOverride: translationConfiguredIndex,
                                                    rotationJointIndexOverride: rotationConfiguredIndex)
        } else {
            let fallbackJoint = fallbackRootMotionJointIndex(skeleton: skeleton,
                                                             preferredRootJointIndex: preferredRootJointIndex)
            let translation = translationConfiguredIndex ?? fallbackJoint
            let rotation = rotationConfiguredIndex ?? fallbackJoint
            channelPair = (translationJointIndex: translation, rotationJointIndex: rotation)
        }
        let consumeJointIndex = consumeConfiguredIndex ?? channelPair.translationJointIndex
        let translationName = skeleton.joints.indices.contains(channelPair.translationJointIndex)
            ? skeleton.joints[channelPair.translationJointIndex].name
            : ""
        let rotationName = skeleton.joints.indices.contains(channelPair.rotationJointIndex)
            ? skeleton.joints[channelPair.rotationJointIndex].name
            : ""
        let consumeName = skeleton.joints.indices.contains(consumeJointIndex)
            ? skeleton.joints[consumeJointIndex].name
            : ""
        return RootMotionChannels(translationJointIndex: channelPair.translationJointIndex,
                                  rotationJointIndex: channelPair.rotationJointIndex,
                                  consumeJointIndex: consumeJointIndex,
                                  translationJointName: translationName,
                                  rotationJointName: rotationName,
                                  consumeJointName: consumeName)
    }

    private func jointIndex(named rawName: String, skeleton: SkeletonAsset) -> Int? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = skeleton.joints.firstIndex(where: { $0.name == trimmed }) {
            return exact
        }
        return skeleton.joints.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
    }

    private func stateNormalizedTime(for result: GraphNodeEvaluationResult) -> Float {
        guard result.sampleDuration > 1.0e-5 else { return 0.0 }
        return simd_clamp(result.sampleTime / result.sampleDuration, 0.0, 1.0)
    }

    private func firstPassingTransition(machine: AnimationGraphStateMachineScaffold,
                                        fromStateID: UUID,
                                        currentNormalizedTime: Float,
                                        context: inout GraphEvaluationContext) -> AnimationGraphTransitionDefinition? {
        for transition in machine.transitions where transition.fromStateID == fromStateID {
            if let minimumNormalizedTime = transition.minimumNormalizedTime,
               currentNormalizedTime < minimumNormalizedTime {
                continue
            }
            var triggersToConsume = Set<Int>()
            if transitionConditionsPass(transition.conditions,
                                        context: &context,
                                        triggerIndicesToConsume: &triggersToConsume) {
                for triggerIndex in triggersToConsume {
                    context.runtimeState.clearTrigger(index: triggerIndex)
                }
                return transition
            }
        }
        return nil
    }

    private func transitionConditionsPass(_ conditions: [AnimationGraphConditionDefinition],
                                          context: inout GraphEvaluationContext,
                                          triggerIndicesToConsume: inout Set<Int>) -> Bool {
        for condition in conditions {
            if !transitionConditionPasses(condition,
                                          context: &context,
                                          triggerIndicesToConsume: &triggerIndicesToConsume) {
                return false
            }
        }
        return true
    }

    private func transitionConditionPasses(_ condition: AnimationGraphConditionDefinition,
                                           context: inout GraphEvaluationContext,
                                           triggerIndicesToConsume: inout Set<Int>) -> Bool {
        let op = normalizedConditionOperator(condition.op)
        guard let parameterIndex = graphParameterIndex(name: condition.parameterName,
                                                       compiledGraph: context.compiledGraph),
              parameterIndex >= 0,
              parameterIndex < context.runtimeState.floatParameterValues.count else { return false }
        let parameterType = context.compiledGraph.parameters[parameterIndex].type

        let defaultFloat = condition.floatValue ?? 0.0
        let defaultInt = condition.intValue ?? 0
        let defaultBool = condition.boolValue ?? true

        switch parameterType {
        case .float:
            let effectiveOp = op.isEmpty ? ">" : op
            let value = context.runtimeState.floatParameterValues[parameterIndex]
            switch effectiveOp {
            case ">", "gt":
                return value > defaultFloat
            case ">=", "gte", "ge":
                return value >= defaultFloat
            case "<", "lt":
                return value < defaultFloat
            case "<=", "lte", "le":
                return value <= defaultFloat
            case "!=", "neq", "not":
                return abs(value - defaultFloat) > 1.0e-5
            default:
                return abs(value - defaultFloat) <= 1.0e-5
            }
        case .int:
            let effectiveOp = op.isEmpty ? ">" : op
            let value = context.runtimeState.intParameterValues[parameterIndex]
            switch effectiveOp {
            case "!=", "neq", "not":
                return value != defaultInt
            case ">", "gt":
                return value > defaultInt
            case ">=", "gte", "ge":
                return value >= defaultInt
            case "<", "lt":
                return value < defaultInt
            case "<=", "lte", "le":
                return value <= defaultInt
            default:
                return value == defaultInt
            }
        case .bool:
            let effectiveOp = op.isEmpty ? "istrue" : op
            let value = context.runtimeState.boolParameterValues[parameterIndex]
            switch effectiveOp {
            case "!=", "neq", "not":
                return value != defaultBool
            case "istrue", "true":
                return value
            case "isfalse", "false":
                return !value
            default:
                return value == defaultBool
            }
        case .trigger:
            let effectiveOp = op.isEmpty ? "istrue" : op
            let value = context.runtimeState.triggerParameterValues[parameterIndex]
            let active = value || context.runtimeState.triggerLatchedParameterIndices.contains(parameterIndex)
            let passes: Bool
            switch effectiveOp {
            case "isfalse", "false":
                passes = !active
            case "!=", "neq", "not":
                passes = active != defaultBool
            default:
                passes = active == defaultBool
            }
            if passes && active {
                triggerIndicesToConsume.insert(parameterIndex)
            }
            return passes
        }
    }

    private func normalizedConditionOperator(_ rawOperator: String) -> String {
        let normalized = rawOperator
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case ">", "gt", "greater", "greaterthan":
            return ">"
        case ">=", "gte", "ge", "greaterorequal", "greaterthanorequal":
            return ">="
        case "<", "lt", "less", "lessthan":
            return "<"
        case "<=", "lte", "le", "lessorequal", "lessthanorequal":
            return "<="
        case "==", "=", "eq", "equal", "equals":
            return "=="
        case "!=", "<>", "neq", "notequal", "not":
            return "!="
        case "true", "istrue":
            return "istrue"
        case "false", "isfalse":
            return "isfalse"
        default:
            return normalized
        }
    }

    private func isLocomotionBlendNode(_ node: CompiledAnimationGraph.Node) -> Bool {
        let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title.contains("locomotion")
    }

    private func constrainCardinalStrafeRootMotion(_ delta: RootMotionDelta,
                                                   inputX: Float) -> RootMotionDelta {
        let sign: Float = inputX < 0.0 ? -1.0 : 1.0
        let planarMagnitude = simd_length(SIMD2<Float>(delta.deltaPos.x, delta.deltaPos.z))
        let constrained = SIMD3<Float>(sign * planarMagnitude, 0.0, 0.0)
        return RootMotionDelta(deltaPos: constrained, deltaRot: delta.deltaRot)
    }

    private func maybeLogLocomotionBlendSelection(node: CompiledAnimationGraph.Node,
                                                  originalPoint: SIMD2<Float>,
                                                  adjustedPoint: SIMD2<Float>,
                                                  samples: [String],
                                                  blendedDelta: RootMotionDelta,
                                                  context: GraphEvaluationContext,
                                                  cardinalStrafeIntent: Bool) {
#if DEBUG
        guard isLocomotionBlendNode(node) else { return }
        let significantAdjustment = simd_length(originalPoint - adjustedPoint) > 0.1
        guard cardinalStrafeIntent || significantAdjustment else { return }
        let sector = cardinalStrafeIntent ? (originalPoint.x < 0.0 ? "left" : "right") : "adjusted"
        let key = "\(context.entityID.uuidString)|\(context.graphHandle.rawValue.uuidString)|\(node.id.uuidString)|\(sector)"
        guard !loggedBlend2DDiagnosticsKeys.contains(key) else { return }
        loggedBlend2DDiagnosticsKeys.insert(key)
        let sampleSummary = samples.isEmpty ? "<none>" : samples.joined(separator: ", ")
        EngineLoggerContext.log(
            "Animator locomotion blend selection entity=\(context.entityID.uuidString) node=\(node.title) inputPoint=\(originalPoint) adjustedPoint=\(adjustedPoint) samples=\(sampleSummary) blendedLocalRootDelta=\(blendedDelta.deltaPos)",
            level: .debug,
            category: .scene
        )
#endif
    }

    private func maybeLogBlend2DDiagnostics(node: CompiledAnimationGraph.Node,
                                            point: SIMD2<Float>,
                                            originalPoint: SIMD2<Float>,
                                            weights: [String],
                                            blendedDelta: RootMotionDelta,
                                            context: GraphEvaluationContext) {
#if DEBUG
        guard isLocomotionBlendNode(node) else { return }
        let strafeIntent = abs(point.x) >= 0.85 && abs(point.y) <= 0.2
        guard strafeIntent else { return }
        let forwardDominant = abs(blendedDelta.deltaPos.z) > (abs(blendedDelta.deltaPos.x) * 1.4 + 0.02)
        guard forwardDominant else { return }
        let key = "\(context.entityID.uuidString)|\(context.graphHandle.rawValue.uuidString)|\(node.id.uuidString)|strafeForwardBias"
        guard !loggedBlend2DDiagnosticsKeys.contains(key) else { return }
        loggedBlend2DDiagnosticsKeys.insert(key)
        let sampleSummary = weights.isEmpty ? "<none>" : weights.joined(separator: ", ")
        EngineLoggerContext.log(
            "Animator locomotion blend strafe-forward-bias entity=\(context.entityID.uuidString) node=\(node.title) inputPoint=\(originalPoint) adjustedPoint=\(point) blendedLocalRootDelta=\(blendedDelta.deltaPos) samples=\(sampleSummary)",
            level: .warning,
            category: .scene
        )
#endif
    }

    private func graphParameterIndex(name: String,
                                     compiledGraph: CompiledAnimationGraph) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return compiledGraph.parameterIndexByName[trimmed]
    }

    private func graphParameterFloat(name: String,
                                     compiledGraph: CompiledAnimationGraph,
                                     runtimeState: AnimationGraphRuntimeInstanceState) -> Float {
        guard let index = graphParameterIndex(name: name, compiledGraph: compiledGraph),
              index >= 0,
              index < runtimeState.floatParameterValues.count else { return 0.0 }
        switch compiledGraph.parameters[index].type {
        case .float:
            return runtimeState.floatParameterValues[index]
        case .int:
            return Float(runtimeState.intParameterValues[index])
        case .bool:
            return runtimeState.boolParameterValues[index] ? 1.0 : 0.0
        case .trigger:
            let value = runtimeState.triggerParameterValues[index] || runtimeState.triggerLatchedParameterIndices.contains(index)
            return value ? 1.0 : 0.0
        }
    }

    // Ozz is the primary runtime backend for local-space pose blending.
    // Legacy math is kept as a narrow fallback when Ozz runtime assets are unavailable.
    private func blendLocalPoses(_ a: [TransformComponent],
                                 _ b: [TransformComponent],
                                 weight: Float,
                                 skeleton: SkeletonAsset,
                                 assets: AssetManager? = nil) -> [TransformComponent] {
        let count = min(a.count, b.count)
        guard count > 0 else { return [] }
        let t = simd_clamp(weight, 0.0, 1.0)
        if let assets,
           let skeletonRuntime = assets.ozzSkeletonRuntime(handle: skeleton.handle),
           let blendingContext = skeletonRuntime.blendingContext(maxLayers: 2),
           let blended = OzzRuntimeBridge.blendLocalPoses(skeletonRuntime: skeletonRuntime,
                                                          blendingContext: blendingContext,
                                                          localPoses: [a, b],
                                                          weights: [1.0 - t, t],
                                                          expectedJointCount: count),
           blended.count == count {
            return blended
        }

        return blendLocalPosesFallback(a, b, weight: t, count: count)
    }

    private func blendLocalPoses(localPoses: [[TransformComponent]],
                                 weights: [Float],
                                 skeleton: SkeletonAsset,
                                 assets: AssetManager? = nil) -> [TransformComponent] {
        guard !localPoses.isEmpty, localPoses.count == weights.count else { return [] }
        let jointCount = localPoses.map(\.count).min() ?? 0
        guard jointCount > 0 else { return [] }
        if let assets,
           let skeletonRuntime = assets.ozzSkeletonRuntime(handle: skeleton.handle),
           let blendingContext = skeletonRuntime.blendingContext(maxLayers: localPoses.count),
           let blended = OzzRuntimeBridge.blendLocalPoses(skeletonRuntime: skeletonRuntime,
                                                          blendingContext: blendingContext,
                                                          localPoses: localPoses,
                                                          weights: weights,
                                                          expectedJointCount: jointCount),
           blended.count == jointCount {
            return blended
        }

        return blendLocalPosesFallback(localPoses: localPoses, weights: weights, jointCount: jointCount)
    }

    // Ozz BlendingJob is the primary path for root-motion delta blending.
    // Legacy blend math remains only as a runtime-availability fallback.
    private func blendRootMotionDeltas(_ a: RootMotionDelta,
                                       _ b: RootMotionDelta,
                                       weight: Float) -> RootMotionDelta {
        let t = simd_clamp(weight, 0.0, 1.0)
        if let ozzBlended = OzzRuntimeBridge.blendRootMotionDeltas([a, b], weights: [1.0 - t, t]) {
            return ozzBlended
        }
        return blendRootMotionDeltasFallback(a, b, weight: t)
    }

    private func blendRootMotionDeltas(_ deltas: [RootMotionDelta],
                                       weights: [Float]) -> RootMotionDelta {
        guard !deltas.isEmpty, deltas.count == weights.count else { return .zero }
        let sum = max(weights.reduce(0, +), 1.0e-6)
        var normalized = weights.map { max(0.0, $0) / sum }
        if normalized.allSatisfy({ $0 <= 1.0e-6 }) {
            normalized = Array(repeating: 1.0 / Float(deltas.count), count: deltas.count)
        }
        if let ozzBlended = OzzRuntimeBridge.blendRootMotionDeltas(deltas, weights: normalized) {
            return ozzBlended
        }
        return blendRootMotionDeltasFallback(deltas, weights: normalized)
    }

    private func resolveRootJointSelection(skeleton: SkeletonAsset,
                                           skinnedMesh: SkinnedMeshComponent?) -> (index: Int, name: String) {
        func jointDepth(_ index: Int) -> Int {
            guard index >= 0, index < skeleton.joints.count else { return Int.max / 2 }
            var depth = 0
            var cursor = index
            var visited: Set<Int> = []
            while cursor >= 0, cursor < skeleton.joints.count, !visited.contains(cursor) {
                visited.insert(cursor)
                let parent = skeleton.joints[cursor].parentIndex
                if parent < 0 { break }
                depth += 1
                cursor = parent
            }
            return depth
        }

        func scoreName(_ name: String) -> Int {
            let lowered = name.lowercased()
            if lowered.contains("translation") { return 4 }
            if lowered.contains("root") { return 3 }
            if lowered.contains("hips") || lowered.contains("pelvis") { return 2 }
            return 0
        }

        if let configured = skinnedMesh?.rootBoneName.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           let index = skeleton.joints.firstIndex(where: { $0.name == configured }) {
            return (index, configured)
        }
        if let bestIndex = skeleton.joints.indices.max(by: { lhs, rhs in
            let lhsScore = scoreName(skeleton.joints[lhs].name)
            let rhsScore = scoreName(skeleton.joints[rhs].name)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            let lhsDepth = jointDepth(lhs)
            let rhsDepth = jointDepth(rhs)
            if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
            return lhs > rhs
        }), scoreName(skeleton.joints[bestIndex].name) > 0 {
            return (bestIndex, skeleton.joints[bestIndex].name)
        }
        if let rootIndex = skeleton.joints.firstIndex(where: { $0.parentIndex < 0 }) {
            return (rootIndex, skeleton.joints[rootIndex].name)
        }
        if let first = skeleton.joints.first {
            return (0, first.name)
        }
        return (0, "")
    }

    // Root motion extraction remains graph-controlled, but extraction math is Ozz-backed.
    // Legacy extraction is retained only if Ozz runtime objects are unavailable.
    private func sampleClipRootMotionDelta(skeleton: SkeletonAsset,
                                           clip: AnimationClipAsset,
                                           rootJointIndex: Int,
                                           translationJointIndexOverride: Int? = nil,
                                           rotationJointIndexOverride: Int? = nil,
                                           previousTime: Float,
                                           currentTime: Float,
                                           isLooping: Bool,
                                           assets: AssetManager? = nil) -> RootMotionDelta {
        let duration = max(clip.durationSeconds, 0.0)
        let prev = resolveClipSampleTime(nodeTime: previousTime, duration: duration, isLooping: isLooping)
        let curr = resolveClipSampleTime(nodeTime: currentTime, duration: duration, isLooping: isLooping)
        guard duration > 1.0e-6 else {
            return sampleRootMotionDeltaSingleSpan(skeleton: skeleton,
                                                   clip: clip,
                                                   rootJointIndex: rootJointIndex,
                                                   translationJointIndexOverride: translationJointIndexOverride,
                                                   rotationJointIndexOverride: rotationJointIndexOverride,
                                                   fromTime: prev,
                                                   toTime: curr,
                                                   assets: assets)
        }
        if !isLooping || curr >= prev {
            return sampleRootMotionDeltaSingleSpan(skeleton: skeleton,
                                                   clip: clip,
                                                   rootJointIndex: rootJointIndex,
                                                   translationJointIndexOverride: translationJointIndexOverride,
                                                   rotationJointIndexOverride: rotationJointIndexOverride,
                                                   fromTime: prev,
                                                   toTime: curr,
                                                   assets: assets)
        }
        let preWrap = sampleRootMotionDeltaSingleSpan(skeleton: skeleton,
                                                      clip: clip,
                                                      rootJointIndex: rootJointIndex,
                                                      translationJointIndexOverride: translationJointIndexOverride,
                                                      rotationJointIndexOverride: rotationJointIndexOverride,
                                                      fromTime: prev,
                                                      toTime: duration,
                                                      assets: assets)
        let postWrap = sampleRootMotionDeltaSingleSpan(skeleton: skeleton,
                                                       clip: clip,
                                                       rootJointIndex: rootJointIndex,
                                                       translationJointIndexOverride: translationJointIndexOverride,
                                                       rotationJointIndexOverride: rotationJointIndexOverride,
                                                       fromTime: 0.0,
                                                       toTime: curr,
                                                       assets: assets)
        let composedPosition = preWrap.deltaPos + simd_quatf(vector: preWrap.deltaRot).act(postWrap.deltaPos)
        let composedRotation = (simd_quatf(vector: preWrap.deltaRot) * simd_quatf(vector: postWrap.deltaRot)).vector
        return RootMotionDelta(deltaPos: composedPosition, deltaRot: composedRotation)
    }

    private func sampleRootMotionDeltaSingleSpan(skeleton: SkeletonAsset,
                                                 clip: AnimationClipAsset,
                                                 rootJointIndex: Int,
                                                 translationJointIndexOverride: Int? = nil,
                                                 rotationJointIndexOverride: Int? = nil,
                                                 fromTime: Float,
                                                 toTime: Float,
                                                 assets: AssetManager? = nil) -> RootMotionDelta {
        guard rootJointIndex >= 0, rootJointIndex < skeleton.joints.count else { return .zero }
        let channels = resolveRootMotionChannels(skeleton: skeleton,
                                                 clip: clip,
                                                 preferredRootJointIndex: rootJointIndex,
                                                 translationJointIndexOverride: translationJointIndexOverride,
                                                 rotationJointIndexOverride: rotationJointIndexOverride)
        let clipTrackDelta = sampleRootMotionDeltaFromClipTracks(clip: clip,
                                                                 channels: channels,
                                                                 fromTime: fromTime,
                                                                 toTime: toTime)
        if let assets,
           let skeletonRuntime = assets.ozzSkeletonRuntime(handle: skeleton.handle),
           let animationRuntime = assets.ozzAnimationRuntime(handle: clip.handle),
           let rootMotionRuntime = assets.ozzRootMotionRuntime(skeletonHandle: skeleton.handle, clipHandle: clip.handle),
           let ozzDelta = OzzRuntimeBridge.extractRootMotionDelta(skeletonRuntime: skeletonRuntime,
                                                                  animationRuntime: animationRuntime,
                                                                  rootMotionRuntime: rootMotionRuntime,
                                                                  translationJointIndex: channels.translationJointIndex,
                                                                  rotationJointIndex: channels.rotationJointIndex,
                                                                  previousTimeSeconds: fromTime,
                                                                  currentTimeSeconds: toTime) {
            if simd_length_squared(ozzDelta.deltaPos) <= 1.0e-10,
               simd_length_squared(clipTrackDelta.deltaPos) > 1.0e-8 {
                return RootMotionDelta(deltaPos: clipTrackDelta.deltaPos, deltaRot: ozzDelta.deltaRot)
            }
            return ozzDelta
        }
        let fallbackDelta = sampleRootMotionDeltaSingleSpanFallback(skeleton: skeleton,
                                                                    clip: clip,
                                                                    channels: channels,
                                                                    fromTime: fromTime,
                                                                    toTime: toTime,
                                                                    assets: assets)
        if simd_length_squared(fallbackDelta.deltaPos) <= 1.0e-10,
           simd_length_squared(clipTrackDelta.deltaPos) > 1.0e-8 {
            return RootMotionDelta(deltaPos: clipTrackDelta.deltaPos, deltaRot: fallbackDelta.deltaRot)
        }
        return fallbackDelta
    }

    private func consumeRootMotionTracks(in localPose: [TransformComponent],
                                         skeleton: SkeletonAsset,
                                         translationJointIndex: Int,
                                         rotationJointIndex: Int,
                                         consumeTranslation: Bool,
                                         consumeRotation: Bool) -> [TransformComponent] {
        guard consumeTranslation || consumeRotation else { return localPose }
        var consumed = localPose
        if consumeTranslation {
            guard translationJointIndex >= 0,
                  translationJointIndex < consumed.count,
                  translationJointIndex < skeleton.joints.count else { return localPose }
            let bindJoint = skeleton.joints[translationJointIndex]
            var translationJoint = consumed[translationJointIndex]
            translationJoint.position = bindJoint.bindLocalPosition
            consumed[translationJointIndex] = translationJoint
        }
        if consumeRotation {
            guard rotationJointIndex >= 0,
                  rotationJointIndex < consumed.count,
                  rotationJointIndex < skeleton.joints.count else { return localPose }
            let bindJoint = skeleton.joints[rotationJointIndex]
            var rotationJoint = consumed[rotationJointIndex]
            rotationJoint.rotation = bindJoint.bindLocalRotation
            consumed[rotationJointIndex] = rotationJoint
        }
        return consumed
    }

    private func resolveRootMotionChannels(skeleton: SkeletonAsset,
                                           clip: AnimationClipAsset,
                                           preferredRootJointIndex: Int,
                                           translationJointIndexOverride: Int? = nil,
                                           rotationJointIndexOverride: Int? = nil) -> (translationJointIndex: Int, rotationJointIndex: Int) {
        if let translationJointIndexOverride,
           let rotationJointIndexOverride,
           translationJointIndexOverride >= 0,
           translationJointIndexOverride < skeleton.joints.count,
           rotationJointIndexOverride >= 0,
           rotationJointIndexOverride < skeleton.joints.count {
            return (translationJointIndexOverride, rotationJointIndexOverride)
        }
        let translationJointIndex = resolveTranslationChannelJointIndex(skeleton: skeleton,
                                                                        clip: clip,
                                                                        preferredRootJointIndex: preferredRootJointIndex)
        let rotationJointIndex = resolveRotationChannelJointIndex(skeleton: skeleton,
                                                                  preferredRootJointIndex: preferredRootJointIndex,
                                                                  clip: clip)
        if let translationJointIndexOverride,
           translationJointIndexOverride >= 0,
           translationJointIndexOverride < skeleton.joints.count {
            return (translationJointIndexOverride, rotationJointIndex)
        }
        if let rotationJointIndexOverride,
           rotationJointIndexOverride >= 0,
           rotationJointIndexOverride < skeleton.joints.count {
            return (translationJointIndex, rotationJointIndexOverride)
        }
        return (translationJointIndex, rotationJointIndex)
    }

    private func resolveTranslationChannelJointIndex(skeleton: SkeletonAsset,
                                                     clip: AnimationClipAsset,
                                                     preferredRootJointIndex: Int) -> Int {
        if hasMeaningfulTranslationTrack(clip: clip, jointIndex: preferredRootJointIndex) {
            return preferredRootJointIndex
        }
        let descendantCandidates = descendantJointIndices(rootJointIndex: preferredRootJointIndex, skeleton: skeleton)
        if let named = descendantCandidates.first(where: { index in
            skeleton.joints[index].name.lowercased().contains("translation")
            && hasMeaningfulTranslationTrack(clip: clip, jointIndex: index)
        }) {
            return named
        }
        if let firstTrack = clip.tracks.first(where: { hasMeaningfulTranslationTrack(clip: clip, jointIndex: $0.jointIndex) }) {
            return firstTrack.jointIndex
        }
        return preferredRootJointIndex
    }

    private func resolveRotationChannelJointIndex(skeleton: SkeletonAsset,
                                                  preferredRootJointIndex: Int,
                                                  clip: AnimationClipAsset? = nil) -> Int {
        if let clip, hasMeaningfulRotationTrack(clip: clip, jointIndex: preferredRootJointIndex) {
            return preferredRootJointIndex
        }
        let descendantCandidates = descendantJointIndices(rootJointIndex: preferredRootJointIndex, skeleton: skeleton)
        if let clip {
            if let named = descendantCandidates.first(where: { index in
                skeleton.joints[index].name.lowercased().contains("rotation")
                && hasMeaningfulRotationTrack(clip: clip, jointIndex: index)
            }) {
                return named
            }
            if let firstTrack = clip.tracks.first(where: { hasMeaningfulRotationTrack(clip: clip, jointIndex: $0.jointIndex) }) {
                return firstTrack.jointIndex
            }
        } else if let named = descendantCandidates.first(where: { index in
            skeleton.joints[index].name.lowercased().contains("rotation")
        }) {
            return named
        }
        return preferredRootJointIndex
    }

    private func descendantJointIndices(rootJointIndex: Int, skeleton: SkeletonAsset) -> [Int] {
        guard rootJointIndex >= 0, rootJointIndex < skeleton.joints.count else { return [] }
        var result: [Int] = []
        var queue: [Int] = [rootJointIndex]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for childIndex in skeleton.joints.indices where skeleton.joints[childIndex].parentIndex == current {
                result.append(childIndex)
                queue.append(childIndex)
            }
        }
        return result
    }

    private func fallbackRootMotionJointIndex(skeleton: SkeletonAsset,
                                              preferredRootJointIndex: Int) -> Int {
        guard !skeleton.joints.isEmpty else { return preferredRootJointIndex }
        if preferredRootJointIndex >= 0,
           preferredRootJointIndex < skeleton.joints.count {
            let preferredName = skeleton.joints[preferredRootJointIndex].name.lowercased()
            let looksLikeRoot = preferredName.contains("root")
            if !looksLikeRoot {
                return preferredRootJointIndex
            }
        }
        if let hipsOrPelvis = skeleton.joints.firstIndex(where: { joint in
            let name = joint.name.lowercased()
            return name.contains("hips") || name.contains("pelvis")
        }) {
            return hipsOrPelvis
        }
        if let firstNonRoot = skeleton.joints.firstIndex(where: { joint in
            !joint.name.lowercased().contains("root")
        }) {
            return firstNonRoot
        }
        return min(max(preferredRootJointIndex, 0), skeleton.joints.count - 1)
    }

    private func sampleRootMotionDeltaFromClipTracks(clip: AnimationClipAsset,
                                                     channels: (translationJointIndex: Int, rotationJointIndex: Int),
                                                     fromTime: Float,
                                                     toTime: Float) -> RootMotionDelta {
        let translationTrack = clip.tracks.first(where: { $0.jointIndex == channels.translationJointIndex })
        let rotationTrack = clip.tracks.first(where: { $0.jointIndex == channels.rotationJointIndex })

        let fromTranslation = translationTrack.flatMap { sampleTranslation($0.translations, time: fromTime) } ?? .zero
        let toTranslation = translationTrack.flatMap { sampleTranslation($0.translations, time: toTime) } ?? fromTranslation

        var prevRotationVector = rotationTrack.flatMap { sampleRotation($0.rotations, time: fromTime) } ?? TransformMath.identityQuaternion
        if !simd4IsFinite(prevRotationVector) || simd_length_squared(prevRotationVector) <= 1.0e-8 {
            prevRotationVector = TransformMath.identityQuaternion
        }
        var currRotationVector = rotationTrack.flatMap { sampleRotation($0.rotations, time: toTime) } ?? prevRotationVector
        if !simd4IsFinite(currRotationVector) || simd_length_squared(currRotationVector) <= 1.0e-8 {
            currRotationVector = prevRotationVector
        }

        let prevRotation = simd_quatf(vector: TransformMath.normalizedQuaternion(prevRotationVector))
        let currRotation = simd_quatf(vector: TransformMath.normalizedQuaternion(currRotationVector))
        let worldDelta = toTranslation - fromTranslation
        let localDeltaRaw = prevRotation.inverse.act(worldDelta)
        let localDelta = simd3IsFinite(localDeltaRaw) ? localDeltaRaw : .zero
        let deltaRotation = simd_normalize(prevRotation.inverse * currRotation).vector
        let safeDeltaRotation = simd4IsFinite(deltaRotation)
            ? TransformMath.normalizedQuaternion(deltaRotation)
            : TransformMath.identityQuaternion

        return RootMotionDelta(deltaPos: localDelta, deltaRot: safeDeltaRotation)
    }

    private func hasMeaningfulTranslationTrack(clip: AnimationClipAsset, jointIndex: Int) -> Bool {
        guard let track = clip.tracks.first(where: { $0.jointIndex == jointIndex }),
              track.translations.count > 1 else { return false }
        let first = track.translations[0].value
        return track.translations.contains(where: { simd_length($0.value - first) > 1.0e-4 })
    }

    private func hasMeaningfulRotationTrack(clip: AnimationClipAsset, jointIndex: Int) -> Bool {
        guard let track = clip.tracks.first(where: { $0.jointIndex == jointIndex }),
              track.rotations.count > 1 else { return false }
        let first = simd_quatf(vector: TransformMath.normalizedQuaternion(track.rotations[0].value))
        return track.rotations.contains { sample in
            let q = simd_quatf(vector: TransformMath.normalizedQuaternion(sample.value))
            let dotValue = abs(simd_dot(first.vector, q.vector))
            return dotValue < 0.9999
        }
    }

    private func simd3IsFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private func simd4IsFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private func evaluateClipMode(scene: EngineScene,
                                  entity: Entity,
                                  dt: Float,
                                  skinnedMesh: SkinnedMeshComponent?,
                                  skeleton: SkeletonAsset?,
                                  animator: inout AnimatorComponent) {
        animator.graphRuntimeState = nil
        let assets = scene.engineContext?.assets
        let previousPlaybackTime = animator.playbackTime
        let clipHandle = animator.clipHandle
        let clip = clipHandle.flatMap { assets?.animationClip(handle: $0) }
        let clipMetadata = clipHandle.flatMap { scene.engineContext?.assetDatabase?.metadata(for: $0) }
        let clipAssociatedSkeletonHandle = assetHandle(from: clipMetadata?.importSettings["skeletonHandle"])
        let skinnedSkeletonHandle = skinnedMesh?.skeletonHandle
        let clipSkeletonMatches = (clipAssociatedSkeletonHandle != nil) && (clipAssociatedSkeletonHandle == skinnedSkeletonHandle)
        var diagnosticState = clipDiagnosticStateByEntity[entity.id] ?? ClipDiagnosticState(lastClipHandle: nil, pendingSummaryClipHandle: nil)
        if diagnosticState.lastClipHandle != clipHandle {
            diagnosticState.lastClipHandle = clipHandle
            diagnosticState.pendingSummaryClipHandle = clipHandle
        }

        if animator.isPlaying, dt > 0 {
            let playbackStep = dt * max(0.0, animator.playbackSpeed)
            animator.playbackTime = nextPlaybackTime(current: animator.playbackTime,
                                                     dt: playbackStep,
                                                     duration: clip?.durationSeconds ?? 0.0,
                                                     isLooping: animator.isLooping)
            if let duration = clip?.durationSeconds,
               duration > 0,
               !animator.isLooping,
               animator.playbackTime >= duration {
                animator.isPlaying = false
            }
        }

        if let handle = clipHandle, clip == nil {
            let clipPath = scene.engineContext?.assetDatabase?.assetURL(for: handle)?.path ?? "<unresolved>"
            logRuntimeIssueOnce(
                key: "unresolvedClip|\(entity.id.uuidString)|\(handle.rawValue.uuidString)",
                message: "Animator clip resolve failure entity=\(entity.id.uuidString)\nactiveClipHandle=\(handle.rawValue.uuidString)\nactiveClipPath=\(clipPath)\nreason=clipAssetMissingForHandle",
                level: .warning
            )
        }

        if clipAssociatedSkeletonHandle == nil, let activeClipHandle = clipHandle {
            let clipPath = scene.engineContext?.assetDatabase?.assetURL(for: activeClipHandle)?.path ?? "<unresolved>"
            logRuntimeIssueOnce(
                key: "clipSkeletonUnset|\(entity.id.uuidString)|\(activeClipHandle.rawValue.uuidString)",
                message: "Animator clip missing skeleton association entity=\(entity.id.uuidString)\nactiveClipHandle=\(activeClipHandle.rawValue.uuidString)\nactiveClipPath=\(clipPath)\naction=bindPoseOnly",
                level: .warning
            )
        }

        if clipAssociatedSkeletonHandle != nil, !clipSkeletonMatches, let activeClipHandle = clipHandle {
            let clipPath = scene.engineContext?.assetDatabase?.assetURL(for: activeClipHandle)?.path ?? "<unresolved>"
            let clipImportScaleApplied = clipMetadata?.importSettings["importScaleApplied"] ?? "<unset>"
            let clipImportScaleSource = clipMetadata?.importSettings["importScaleSource"] ?? "<unset>"
            logRuntimeIssueOnce(
                key: "clipSkeletonMismatch|\(entity.id.uuidString)|\(activeClipHandle.rawValue.uuidString)|\(skinnedSkeletonHandle?.rawValue.uuidString ?? "<none>")",
                message: "Animator clip/skeleton mismatch entity=\(entity.id.uuidString)\nactiveClipHandle=\(activeClipHandle.rawValue.uuidString)\nactiveClipPath=\(clipPath)\nactiveClipImportScaleApplied=\(clipImportScaleApplied)\nactiveClipImportScaleSource=\(clipImportScaleSource)\nactiveClipSkeletonAssociationHandle=\(clipAssociatedSkeletonHandle?.rawValue.uuidString ?? "<none>")\nskinnedMeshSkeletonHandle=\(skinnedSkeletonHandle?.rawValue.uuidString ?? "<none>")\naction=poseEvaluationSkipped",
                level: .warning
            )
        }

        if let skeleton, let clip, clipSkeletonMatches {
            if let activeClipHandle = clipHandle {
                logRuntimeIssueOnce(
                    key: "clipEvaluating|\(entity.id.uuidString)|\(activeClipHandle.rawValue.uuidString)",
                    message: "Animator clip evaluation active entity=\(entity.id.uuidString)\nactiveClipHandle=\(activeClipHandle.rawValue.uuidString)\naction=evaluatingClip",
                    level: .debug
                )
            }
            let rootSelection = resolveRootJointSelection(skeleton: skeleton, skinnedMesh: skinnedMesh)
            animator.poseRuntimeState = evaluatePose(skeleton: skeleton,
                                                     clip: clip,
                                                     assets: assets,
                                                     previousPlaybackTime: previousPlaybackTime,
                                                     playbackTime: animator.playbackTime,
                                                     isLooping: animator.isLooping,
                                                     rootJointIndex: rootSelection.index,
                                                     rootBoneName: rootSelection.name,
                                                     usesRootMotion: animator.enableRootMotion,
                                                     currentStateName: "")
        } else if let skeleton {
            animator.poseRuntimeState = makeBindPoseState(skeleton: skeleton,
                                                          playbackTime: animator.playbackTime,
                                                          assets: assets)
        } else {
            animator.poseRuntimeState = nil
        }
        clipDiagnosticStateByEntity[entity.id] = diagnosticState
    }

    private func evaluatePose(skeleton: SkeletonAsset,
                              clip: AnimationClipAsset,
                              assets: AssetManager?,
                              previousPlaybackTime: Float,
                              playbackTime: Float,
                              isLooping: Bool,
                              rootJointIndex: Int,
                              rootBoneName: String,
                              usesRootMotion: Bool,
                              currentStateName: String) -> AnimationPoseRuntimeState {
        let sampledLocalPose = evaluateLocalPose(skeleton: skeleton,
                                               clip: clip,
                                               playbackTime: playbackTime,
                                               assets: assets)
        let rootMotionDelta = sampleClipRootMotionDelta(skeleton: skeleton,
                                                        clip: clip,
                                                        rootJointIndex: rootJointIndex,
                                                        previousTime: previousPlaybackTime,
                                                        currentTime: playbackTime,
                                                        isLooping: isLooping,
                                                        assets: assets)
        let consumedRootTrack = usesRootMotion
        let outputLocalPose = consumedRootTrack
            ? consumeRootMotionTracks(in: sampledLocalPose,
                                      skeleton: skeleton,
                                      translationJointIndex: rootJointIndex,
                                      rotationJointIndex: rootJointIndex,
                                      consumeTranslation: true,
                                      consumeRotation: true)
            : sampledLocalPose
        let globalPose = makeGlobalPose(localPose: outputLocalPose,
                                        skeleton: skeleton,
                                        assets: assets)
        return AnimationPoseRuntimeState(sampleTime: playbackTime,
                                         localPose: outputLocalPose,
                                         globalPose: globalPose,
                                         rootMotionDelta: rootMotionDelta,
                                         usesRootMotion: usesRootMotion,
                                         currentStateName: currentStateName,
                                         rootMotionBoneName: rootBoneName,
                                         rootMotionJointIndex: rootJointIndex,
                                         rootMotionTrackConsumed: consumedRootTrack,
                                         rootMotionTranslationBoneName: rootBoneName,
                                         rootMotionTranslationJointIndex: rootJointIndex,
                                         rootMotionRotationBoneName: rootBoneName,
                                         rootMotionRotationJointIndex: rootJointIndex,
                                         rootMotionConsumeBoneName: rootBoneName,
                                         rootMotionConsumeJointIndex: rootJointIndex)
    }

    // Ozz SamplingJob is the primary local-pose sampling path.
    // Legacy keyframe interpolation is retained only as fallback.
    private func evaluateLocalPose(skeleton: SkeletonAsset,
                                   clip: AnimationClipAsset,
                                   playbackTime: Float,
                                   assets: AssetManager? = nil) -> [TransformComponent] {
        if let assets,
           let skeletonRuntime = assets.ozzSkeletonRuntime(handle: skeleton.handle),
           let animationRuntime = assets.ozzAnimationRuntime(handle: clip.handle),
           let samplingContext = animationRuntime.context(maxSoaTracks: skeletonRuntime.maxSoaTracks),
           let ozzPose = OzzRuntimeBridge.sampleLocalPose(skeletonRuntime: skeletonRuntime,
                                                          animationRuntime: animationRuntime,
                                                          samplingContext: samplingContext,
                                                          timeSeconds: playbackTime,
                                                          expectedJointCount: skeleton.joints.count),
           ozzPose.count == skeleton.joints.count {
            return ozzPose
        }
        return evaluateLocalPoseFallback(skeleton: skeleton, clip: clip, playbackTime: playbackTime)
    }

    private func makeGlobalPose(localPose: [TransformComponent],
                                skeleton: SkeletonAsset,
                                assets: AssetManager? = nil) -> [TransformComponent] {
        let globalMatrices = globalMatrices(from: localPose, skeleton: skeleton, assets: assets)
        var globalPose = Array(repeating: TransformComponent(), count: globalMatrices.count)
        for jointIndex in 0..<globalMatrices.count {
            let decomposed = TransformMath.decomposeMatrix(globalMatrices[jointIndex])
            globalPose[jointIndex] = TransformComponent(position: decomposed.position,
                                                        rotation: decomposed.rotation,
                                                        scale: decomposed.scale)
        }
        return globalPose
    }

    private func makeBindPoseState(skeleton: SkeletonAsset,
                                   playbackTime: Float,
                                   assets: AssetManager? = nil) -> AnimationPoseRuntimeState {
        let localPose = skeleton.joints.map { joint in
            TransformComponent(position: joint.bindLocalPosition,
                               rotation: joint.bindLocalRotation,
                               scale: joint.bindLocalScale)
        }
        let globalPose = makeGlobalPose(localPose: localPose, skeleton: skeleton, assets: assets)
        let selection = resolveRootJointSelection(skeleton: skeleton, skinnedMesh: nil)
        return AnimationPoseRuntimeState(sampleTime: playbackTime,
                                         localPose: localPose,
                                         globalPose: globalPose,
                                         rootMotionBoneName: selection.name,
                                         rootMotionJointIndex: selection.index,
                                         rootMotionTrackConsumed: false,
                                         rootMotionTranslationBoneName: selection.name,
                                         rootMotionTranslationJointIndex: selection.index,
                                         rootMotionRotationBoneName: selection.name,
                                         rootMotionRotationJointIndex: selection.index,
                                         rootMotionConsumeBoneName: selection.name,
                                         rootMotionConsumeJointIndex: selection.index)
    }

    private func makePoseState(skeleton: SkeletonAsset,
                               localPose: [TransformComponent],
                               sampleTime: Float,
                               rootMotionDelta: RootMotionDelta = .zero,
                               usesRootMotion: Bool = false,
                               currentStateName: String = "",
                               rootMotionBoneName: String = "",
                               rootMotionJointIndex: Int = -1,
                               rootMotionTrackConsumed: Bool = false,
                               rootMotionTranslationBoneName: String = "",
                               rootMotionTranslationJointIndex: Int = -1,
                               rootMotionRotationBoneName: String = "",
                               rootMotionRotationJointIndex: Int = -1,
                               rootMotionConsumeBoneName: String = "",
                               rootMotionConsumeJointIndex: Int = -1,
                               assets: AssetManager? = nil) -> AnimationPoseRuntimeState {
        guard !localPose.isEmpty else {
            return makeBindPoseState(skeleton: skeleton, playbackTime: sampleTime, assets: assets)
        }
        let globalPose = makeGlobalPose(localPose: localPose, skeleton: skeleton, assets: assets)
        return AnimationPoseRuntimeState(sampleTime: sampleTime,
                                         localPose: localPose,
                                         globalPose: globalPose,
                                         rootMotionDelta: rootMotionDelta,
                                         usesRootMotion: usesRootMotion,
                                         currentStateName: currentStateName,
                                         rootMotionBoneName: rootMotionBoneName,
                                         rootMotionJointIndex: rootMotionJointIndex,
                                         rootMotionTrackConsumed: rootMotionTrackConsumed,
                                         rootMotionTranslationBoneName: rootMotionTranslationBoneName,
                                         rootMotionTranslationJointIndex: rootMotionTranslationJointIndex,
                                         rootMotionRotationBoneName: rootMotionRotationBoneName,
                                         rootMotionRotationJointIndex: rootMotionRotationJointIndex,
                                         rootMotionConsumeBoneName: rootMotionConsumeBoneName,
                                         rootMotionConsumeJointIndex: rootMotionConsumeJointIndex)
    }

    private func sampleTranslation(_ keyframes: [AnimationClipAsset.TranslationKeyframe], time: Float) -> SIMD3<Float>? {
        sampleVector3Keyframes(keyframes.map { ($0.time, $0.value) }, time: time)
    }

    private func sampleScale(_ keyframes: [AnimationClipAsset.ScaleKeyframe], time: Float) -> SIMD3<Float>? {
        sampleVector3Keyframes(keyframes.map { ($0.time, $0.value) }, time: time)
    }

    private func sampleRotation(_ keyframes: [AnimationClipAsset.RotationKeyframe], time: Float) -> SIMD4<Float>? {
        guard !keyframes.isEmpty else { return nil }
        if keyframes.count == 1 { return keyframes[0].value }
        if time <= keyframes[0].time { return keyframes[0].value }
        if time >= keyframes[keyframes.count - 1].time { return keyframes[keyframes.count - 1].value }

        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            guard time >= a.time, time <= b.time else { continue }
            let span = max(b.time - a.time, 1.0e-6)
            let t = simd_clamp((time - a.time) / span, 0.0, 1.0)
            let qa = simd_quatf(real: a.value.w, imag: SIMD3<Float>(a.value.x, a.value.y, a.value.z))
            let qb = simd_quatf(real: b.value.w, imag: SIMD3<Float>(b.value.x, b.value.y, b.value.z))
            let q = simd_slerp(qa, qb, t)
            return TransformMath.normalizedQuaternion(SIMD4<Float>(q.imag.x, q.imag.y, q.imag.z, q.real))
        }
        return keyframes[keyframes.count - 1].value
    }

    private func sampleVector3Keyframes(_ keyframes: [(Float, SIMD3<Float>)], time: Float) -> SIMD3<Float>? {
        guard !keyframes.isEmpty else { return nil }
        if keyframes.count == 1 { return keyframes[0].1 }
        if time <= keyframes[0].0 { return keyframes[0].1 }
        if time >= keyframes[keyframes.count - 1].0 { return keyframes[keyframes.count - 1].1 }

        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            guard time >= a.0, time <= b.0 else { continue }
            let span = max(b.0 - a.0, 1.0e-6)
            let t = simd_clamp((time - a.0) / span, 0.0, 1.0)
            return a.1 + ((b.1 - a.1) * t)
        }
        return keyframes[keyframes.count - 1].1
    }

    // Ozz LocalToModelJob is the primary hierarchy solve for model-space matrices.
    // Legacy parent-chain multiplication is retained only as fallback.
    private func globalMatrices(from localPose: [TransformComponent],
                                skeleton: SkeletonAsset,
                                assets: AssetManager? = nil) -> [matrix_float4x4] {
        let jointCount = min(skeleton.joints.count, localPose.count)
        guard jointCount > 0 else { return [] }
        if let assets,
           let skeletonRuntime = assets.ozzSkeletonRuntime(handle: skeleton.handle),
           let localToModelContext = skeletonRuntime.context(),
           let modelMatrices = OzzRuntimeBridge.localToModelMatrices(skeletonRuntime: skeletonRuntime,
                                                                     localToModelContext: localToModelContext,
                                                                     localPose: localPose,
                                                                     expectedJointCount: jointCount),
           modelMatrices.count == jointCount {
            return modelMatrices
        }
        return globalMatricesFallback(from: localPose, skeleton: skeleton, jointCount: jointCount)
    }

    private func blendLocalPosesFallback(_ a: [TransformComponent],
                                         _ b: [TransformComponent],
                                         weight: Float,
                                         count: Int) -> [TransformComponent] {
        var output = Array(repeating: TransformComponent(), count: count)
        for i in 0..<count {
            let pa = a[i]
            let pb = b[i]
            let blendedPosition = pa.position + ((pb.position - pa.position) * weight)
            let blendedScale = pa.scale + ((pb.scale - pa.scale) * weight)
            let qa = simd_quatf(real: pa.rotation.w, imag: SIMD3<Float>(pa.rotation.x, pa.rotation.y, pa.rotation.z))
            let qb = simd_quatf(real: pb.rotation.w, imag: SIMD3<Float>(pb.rotation.x, pb.rotation.y, pb.rotation.z))
            let q = simd_slerp(qa, qb, weight)
            output[i] = TransformComponent(position: blendedPosition,
                                           rotation: SIMD4<Float>(q.imag.x, q.imag.y, q.imag.z, q.real),
                                           scale: blendedScale)
        }
        return output
    }

    private func blendLocalPosesFallback(localPoses: [[TransformComponent]],
                                         weights: [Float],
                                         jointCount: Int) -> [TransformComponent] {
        let weightSum = max(weights.reduce(0, +), 1.0e-6)
        var normalizedWeights = weights.map { $0 / weightSum }
        if normalizedWeights.isEmpty {
            normalizedWeights = Array(repeating: 1.0 / Float(localPoses.count), count: localPoses.count)
        }

        var output = Array(repeating: TransformComponent(), count: jointCount)
        for jointIndex in 0..<jointCount {
            var blendedPosition = SIMD3<Float>(repeating: 0.0)
            var blendedScale = SIMD3<Float>(repeating: 0.0)
            let firstRotation = localPoses[0][jointIndex].rotation
            var accumRotation = SIMD4<Float>(repeating: 0.0)
            for poseIndex in 0..<localPoses.count {
                let pose = localPoses[poseIndex][jointIndex]
                let w = normalizedWeights[poseIndex]
                blendedPosition += pose.position * w
                blendedScale += pose.scale * w

                var q = TransformMath.normalizedQuaternion(pose.rotation)
                if simd_dot(firstRotation, q) < 0.0 {
                    q = -q
                }
                accumRotation += q * w
            }
            output[jointIndex] = TransformComponent(position: blendedPosition,
                                                    rotation: TransformMath.normalizedQuaternion(accumRotation),
                                                    scale: blendedScale)
        }
        return output
    }

    private func blendRootMotionDeltasFallback(_ a: RootMotionDelta,
                                               _ b: RootMotionDelta,
                                               weight: Float) -> RootMotionDelta {
        let blendedPosition = simd_mix(a.deltaPos, b.deltaPos, SIMD3<Float>(repeating: weight))
        let qa = simd_quatf(vector: TransformMath.normalizedQuaternion(a.deltaRot))
        let qb = simd_quatf(vector: TransformMath.normalizedQuaternion(b.deltaRot))
        let blendedRotation = simd_slerp(qa, qb, weight).vector
        return RootMotionDelta(deltaPos: blendedPosition, deltaRot: blendedRotation)
    }

    private func blendRootMotionDeltasFallback(_ deltas: [RootMotionDelta],
                                               weights: [Float]) -> RootMotionDelta {
        var result = deltas[0]
        var consumed = weights[0]
        if deltas.count == 1 { return result }
        for i in 1..<deltas.count {
            let nextWeight = weights[i]
            let t = nextWeight / max(consumed + nextWeight, 1.0e-6)
            result = blendRootMotionDeltasFallback(result, deltas[i], weight: t)
            consumed += nextWeight
        }
        return result
    }

    private func sampleRootMotionDeltaSingleSpanFallback(skeleton: SkeletonAsset,
                                                         clip: AnimationClipAsset,
                                                         channels: (translationJointIndex: Int, rotationJointIndex: Int),
                                                         fromTime: Float,
                                                         toTime: Float,
                                                         assets: AssetManager?) -> RootMotionDelta {
        let fromLocalPose = evaluateLocalPose(skeleton: skeleton, clip: clip, playbackTime: fromTime, assets: assets)
        let toLocalPose = evaluateLocalPose(skeleton: skeleton, clip: clip, playbackTime: toTime, assets: assets)
        let fromGlobalPose = makeGlobalPose(localPose: fromLocalPose, skeleton: skeleton, assets: assets)
        let toGlobalPose = makeGlobalPose(localPose: toLocalPose, skeleton: skeleton, assets: assets)
        guard channels.translationJointIndex < fromGlobalPose.count,
              channels.translationJointIndex < toGlobalPose.count,
              channels.rotationJointIndex < fromGlobalPose.count,
              channels.rotationJointIndex < toGlobalPose.count else { return .zero }

        let fromTranslationTransform = fromGlobalPose[channels.translationJointIndex]
        let toTranslationTransform = toGlobalPose[channels.translationJointIndex]
        let fromRotationTransform = fromGlobalPose[channels.rotationJointIndex]
        let toRotationTransform = toGlobalPose[channels.rotationJointIndex]

        var previousRotationVector = TransformMath.normalizedQuaternion(fromRotationTransform.rotation)
        if !simd4IsFinite(previousRotationVector) || simd_length_squared(previousRotationVector) <= 1.0e-8 {
            previousRotationVector = TransformMath.identityQuaternion
        }
        var currentRotationVector = TransformMath.normalizedQuaternion(toRotationTransform.rotation)
        if !simd4IsFinite(currentRotationVector) || simd_length_squared(currentRotationVector) <= 1.0e-8 {
            currentRotationVector = TransformMath.identityQuaternion
        }
        let previousRotation = simd_quatf(vector: previousRotationVector)
        let currentRotation = simd_quatf(vector: currentRotationVector)
        let rawDeltaRotation = simd_normalize(simd_inverse(previousRotation) * currentRotation).vector
        let deltaRotation = simd4IsFinite(rawDeltaRotation)
            ? TransformMath.normalizedQuaternion(rawDeltaRotation)
            : TransformMath.identityQuaternion

        let worldTranslationDelta = toTranslationTransform.position - fromTranslationTransform.position
        let localTranslationDeltaRaw = previousRotation.inverse.act(worldTranslationDelta)
        let localTranslationDelta = simd3IsFinite(localTranslationDeltaRaw) ? localTranslationDeltaRaw : .zero

        return RootMotionDelta(deltaPos: localTranslationDelta,
                               deltaRot: deltaRotation)
    }

    private func evaluateLocalPoseFallback(skeleton: SkeletonAsset,
                                           clip: AnimationClipAsset,
                                           playbackTime: Float) -> [TransformComponent] {
        let jointCount = skeleton.joints.count
        guard jointCount > 0 else {
            return []
        }

        var localPose = Array(repeating: TransformComponent(), count: jointCount)
        for jointIndex in 0..<jointCount {
            let joint = skeleton.joints[jointIndex]
            localPose[jointIndex] = TransformComponent(position: joint.bindLocalPosition,
                                                       rotation: joint.bindLocalRotation,
                                                       scale: joint.bindLocalScale)
        }
        for track in clip.tracks {
            guard track.jointIndex >= 0, track.jointIndex < jointCount else { continue }
            var jointLocal = localPose[track.jointIndex]
            if let translation = sampleTranslation(track.translations, time: playbackTime) {
                jointLocal.position = translation
            }
            if let rotation = sampleRotation(track.rotations, time: playbackTime) {
                jointLocal.rotation = rotation
            }
            if let scale = sampleScale(track.scales, time: playbackTime) {
                jointLocal.scale = scale
            }
            localPose[track.jointIndex] = jointLocal
        }
        return localPose
    }

    private func globalMatricesFallback(from localPose: [TransformComponent],
                                        skeleton: SkeletonAsset,
                                        jointCount: Int) -> [matrix_float4x4] {
        let localMatrices: [matrix_float4x4] = localPose.prefix(jointCount).map { local in
            TransformMath.makeMatrix(position: local.position,
                                     rotation: local.rotation,
                                     scale: local.scale)
        }
        var resolved = Array(repeating: matrix_identity_float4x4, count: jointCount)
        var visitState = Array(repeating: UInt8(0), count: jointCount) // 0=unvisited, 1=visiting, 2=resolved

        func resolve(_ jointIndex: Int) {
            if visitState[jointIndex] == 2 { return }
            if visitState[jointIndex] == 1 {
                resolved[jointIndex] = localMatrices[jointIndex]
                visitState[jointIndex] = 2
                return
            }
            visitState[jointIndex] = 1
            let parentIndex = skeleton.joints[jointIndex].parentIndex
            if parentIndex >= 0, parentIndex < jointCount, parentIndex != jointIndex {
                resolve(parentIndex)
                resolved[jointIndex] = resolved[parentIndex] * localMatrices[jointIndex]
            } else {
                resolved[jointIndex] = localMatrices[jointIndex]
            }
            visitState[jointIndex] = 2
        }

        for jointIndex in 0..<jointCount {
            resolve(jointIndex)
        }
        return resolved
    }

    private func matrixIsFinite(_ matrix: matrix_float4x4) -> Bool {
        for column in 0..<4 {
            let value = matrix[column]
            if !value.x.isFinite || !value.y.isFinite || !value.z.isFinite || !value.w.isFinite {
                return false
            }
        }
        return true
    }

    private func logRuntimeSummaryOnce(engineContext: EngineContext?,
                                       entity: Entity,
                                       animator: AnimatorComponent?,
                                       skinnedMesh: SkinnedMeshComponent,
                                       skeleton: SkeletonAsset,
                                       clip: AnimationClipAsset?,
                                       mesh: MCMesh?,
                                       localPose: [TransformComponent],
                                       globalPose: [TransformComponent],
                                       evaluatedJointCount: Int,
                                       bindPolicy: String,
                                       importedInverseBindCount: Int,
                                       nonFinitePaletteMatrixCount: Int,
                                       forceLog: Bool) {
#if DEBUG
        guard animationGraphDebugLoggingEnabled else { return }
        let key = "\(entity.id.uuidString)|\(skeleton.handle.rawValue.uuidString)|\(clip?.handle.rawValue.uuidString ?? "<none>")"
        if !forceLog {
            guard !loggedRuntimeSummaryKeys.contains(key) else { return }
        }
        loggedRuntimeSummaryKeys.insert(key)
        let indexCount = mesh?.totalIndexCount() ?? 0
        let rootTranslationMagnitude = globalPose.isEmpty ? 0 : simd_length(globalPose[0].position)
        var maxJointTranslationMagnitude: Float = 0
        for joint in globalPose {
            maxJointTranslationMagnitude = max(maxJointTranslationMagnitude, simd_length(joint.position))
        }
        let nonFiniteLocalCount = localPose.reduce(into: 0) { count, pose in
            if !vector3IsFinite(pose.position) || !vector4IsFinite(pose.rotation) || !vector3IsFinite(pose.scale) {
                count += 1
            }
        }
        let nonFiniteGlobalCount = globalPose.reduce(into: 0) { count, pose in
            if !vector3IsFinite(pose.position) || !vector4IsFinite(pose.rotation) || !vector3IsFinite(pose.scale) {
                count += 1
            }
        }

        let clipHandle = animator?.clipHandle
        let clipMeta = clipHandle.flatMap { engineContext?.assetDatabase?.metadata(for: $0) }
        let clipPath = clipHandle.flatMap { engineContext?.assetDatabase?.assetURL(for: $0)?.path } ?? "<unresolved>"
        let clipImportScaleApplied = clipMeta?.importSettings["importScaleApplied"] ?? "<unset>"
        let clipImportScaleSource = clipMeta?.importSettings["importScaleSource"] ?? "<unset>"
        let clipSkeletonAssociation = clipMeta?.importSettings["skeletonHandle"] ?? "<unset>"
        let clipCanonicalJointCount = clipMeta?.importSettings["clipCanonicalJointCountAfterRemap"] ?? "<unset>"
        let clipTargetSkeletonJointCount = clipMeta?.importSettings["targetSkeletonJointCount"] ?? "<unset>"
        let skinnedSkeletonHandle = skinnedMesh.skeletonHandle?.rawValue.uuidString ?? "<none>"
        let skeletonHandleMatch = clipSkeletonAssociation == skinnedSkeletonHandle ? "true" : "false"

        let meshBoundsRadius = mesh?.boundsRadius ?? 0
        let animatedBoundsRisk = meshBoundsRadius > 0
            ? (maxJointTranslationMagnitude > (meshBoundsRadius * 8.0))
            : false
        EngineLoggerContext.log(
            """
            FBX runtime skinning summary entity=\(entity.id.uuidString)
            activeClipHandle=\(clipHandle?.rawValue.uuidString ?? "<none>")
            activeClipPath=\(clipPath)
            activeClipName=\(clip?.name ?? "<none>")
            activeClipImportScaleApplied=\(clipImportScaleApplied)
            activeClipImportScaleSource=\(clipImportScaleSource)
            activeClipSkeletonAssociationHandle=\(clipSkeletonAssociation)
            activeClipCanonicalJointCountAfterRemap=\(clipCanonicalJointCount)
            activeClipTargetSkeletonJointCount=\(clipTargetSkeletonJointCount)
            skinnedMeshSkeletonHandle=\(skinnedSkeletonHandle)
            clipSkeletonHandleMatchesSkinnedMesh=\(skeletonHandleMatch)
            clipEvaluationState=\(clip != nil && skeletonHandleMatch == "true" ? "evaluatingClip" : "bindPoseOnly")
            playbackTime=\(animator?.playbackTime ?? 0)
            playbackSpeed=\(animator?.playbackSpeed ?? 0)
            isPlaying=\(animator?.isPlaying ?? false)
            meshVertexCount=\(mesh?.vertexCount ?? 0)
            meshIndexCount=\(indexCount)
            meshBoundsRadius=\(meshBoundsRadius)
            skinningStreamsPresent=\(mesh?.hasValidSkinningVertexStreams() ?? false)
            evaluatedJointCount=\(evaluatedJointCount)
            skeletonJointCount=\(skeleton.joints.count)
            rootJointTranslationMagnitude=\(rootTranslationMagnitude)
            maxJointTranslationMagnitude=\(maxJointTranslationMagnitude)
            nonFiniteLocalJointTransformCount=\(nonFiniteLocalCount)
            nonFiniteGlobalJointTransformCount=\(nonFiniteGlobalCount)
            nonFinitePaletteMatrixCount=\(nonFinitePaletteMatrixCount)
            importedInverseBindCount=\(importedInverseBindCount)
            bindPolicy=\(bindPolicy)
            animatedBoundsRisk=\(animatedBoundsRisk)
            """,
            level: .debug,
            category: .assets
        )
#endif
    }

    private func vector3IsFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private func vector4IsFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private func assetHandle(from rawValue: String?) -> AssetHandle? {
        guard let rawValue, !rawValue.isEmpty, let uuid = UUID(uuidString: rawValue) else { return nil }
        return AssetHandle(rawValue: uuid)
    }

    private func logStateMachineSignatureIfChanged(entityID: UUID,
                                                   graphHandle: AnimationGraphHandle,
                                                   nodeID: UUID,
                                                   currentStateName: String,
                                                   nextStateName: String,
                                                   reason: String) {
#if DEBUG
        let key = "\(entityID.uuidString)|\(graphHandle.rawValue.uuidString)|\(nodeID.uuidString)"
        let signature = "\(currentStateName)|\(nextStateName)"
        if lastStateMachineSignatureByKey[key] == signature {
            return
        }
        lastStateMachineSignatureByKey[key] = signature
        EngineLoggerContext.log(
            "Animator graph state change entity=\(entityID.uuidString) graph=\(graphHandle.rawValue.uuidString) node=\(nodeID.uuidString) currentState=\(currentStateName) nextState=\(nextStateName) reason=\(reason)",
            level: .debug,
            category: .scene
        )
#endif
    }

    private func logRuntimeIssueOnce(key: String, message: @autoclosure () -> String, level: MCLogLevel) {
#if DEBUG
        guard !loggedRuntimeIssueKeys.contains(key) else { return }
        loggedRuntimeIssueKeys.insert(key)
        EngineLoggerContext.log(
            message(),
            level: level,
            category: .assets
        )
#endif
    }

    private func logRuntimeIssueOnce(key: String, level: MCLogLevel, message: @autoclosure () -> String) {
        #if DEBUG
        guard !loggedRuntimeIssueKeys.contains(key) else { return }
        loggedRuntimeIssueKeys.insert(key)
        EngineLoggerContext.log(
            message(),
            level: level,
            category: .assets
        )
        #endif
    }

    private func shouldForceRuntimeSummary(entityId: UUID, clipHandle: AssetHandle?) -> Bool {
        guard let state = clipDiagnosticStateByEntity[entityId] else { return false }
        return state.pendingSummaryClipHandle == clipHandle
    }

    private func markRuntimeSummaryForcedHandled(entityId: UUID, clipHandle: AssetHandle?) {
        guard var state = clipDiagnosticStateByEntity[entityId] else { return }
        if state.pendingSummaryClipHandle == clipHandle {
            state.pendingSummaryClipHandle = nil
            clipDiagnosticStateByEntity[entityId] = state
        }
    }
}
