/// AnimationSystem.swift
/// Minimal animation scaffolding for update-time evaluation and render snapshot prep.
/// Created by Kaden Cringle.

import Foundation
import simd

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
        scene.ecs.viewDeterministic(AnimatorComponent.self) { entity, animator in
            var updated = animator
            let entityId = entity.id
            let skinnedMesh = scene.ecs.get(SkinnedMeshComponent.self, for: entity)
            let skeleton = skinnedMesh?.skeletonHandle.flatMap { assets.skeleton(handle: $0) }
            let clipHandle = animator.clipHandle
            let clip = clipHandle.flatMap { assets.animationClip(handle: $0) }
            let clipMetadata = clipHandle.flatMap { scene.engineContext?.assetDatabase?.metadata(for: $0) }
            let clipAssociatedSkeletonHandle = assetHandle(from: clipMetadata?.importSettings["skeletonHandle"])
            let skinnedSkeletonHandle = skinnedMesh?.skeletonHandle
            let clipSkeletonMatches = (clipAssociatedSkeletonHandle != nil) && (clipAssociatedSkeletonHandle == skinnedSkeletonHandle)
            var diagnosticState = clipDiagnosticStateByEntity[entityId] ?? ClipDiagnosticState(lastClipHandle: nil, pendingSummaryClipHandle: nil)
            if diagnosticState.lastClipHandle != clipHandle {
                diagnosticState.lastClipHandle = clipHandle
                diagnosticState.pendingSummaryClipHandle = clipHandle
            }

            if updated.isPlaying, dt > 0 {
                let playbackStep = dt * max(0.0, updated.playbackSpeed)
                updated.playbackTime = nextPlaybackTime(current: updated.playbackTime,
                                                        dt: playbackStep,
                                                        duration: clip?.durationSeconds ?? 0.0,
                                                        isLooping: updated.isLooping)
                if let duration = clip?.durationSeconds,
                   duration > 0,
                   !updated.isLooping,
                   updated.playbackTime >= duration {
                    updated.isPlaying = false
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
                updated.poseRuntimeState = evaluatePose(skeleton: skeleton,
                                                        clip: clip,
                                                        playbackTime: updated.playbackTime)
            } else if let skeleton {
                updated.poseRuntimeState = makeBindPoseState(skeleton: skeleton, playbackTime: updated.playbackTime)
            } else {
                updated.poseRuntimeState = nil
            }
            scene.ecs.add(updated, to: entity)
            clipDiagnosticStateByEntity[entityId] = diagnosticState
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
                    let paletteResult = makeBonePalette(skeleton: skeleton, globalPose: globalPose)
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

    private func makeBonePalette(skeleton: SkeletonAsset, globalPose: [TransformComponent]) -> BonePaletteBuildResult {
        let jointCount = min(skeleton.joints.count, globalPose.count)
        guard jointCount > 0 else {
            return BonePaletteBuildResult(matrices: [], bindPolicy: "none", importedInverseBindCount: 0, nonFiniteMatrixCount: 0)
        }

        let bindLocalPose: [TransformComponent] = skeleton.joints.map { joint in
            TransformComponent(position: joint.bindLocalPosition,
                               rotation: joint.bindLocalRotation,
                               scale: joint.bindLocalScale)
        }
        let bindGlobalMatrices = globalMatrices(from: bindLocalPose, skeleton: skeleton)

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

    private func evaluatePose(skeleton: SkeletonAsset,
                              clip: AnimationClipAsset,
                              playbackTime: Float) -> AnimationPoseRuntimeState {
        let jointCount = skeleton.joints.count
        guard jointCount > 0 else {
            return AnimationPoseRuntimeState(sampleTime: playbackTime, localPose: [], globalPose: [])
        }

        var localPose: [TransformComponent] = skeleton.joints.map { joint in
            TransformComponent(position: joint.bindLocalPosition,
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

        let globalMatrices = globalMatrices(from: localPose, skeleton: skeleton)
        var globalPose = Array(repeating: TransformComponent(), count: jointCount)
        for jointIndex in 0..<jointCount {
            let decomposed = TransformMath.decomposeMatrix(globalMatrices[jointIndex])
            globalPose[jointIndex] = TransformComponent(position: decomposed.position,
                                                        rotation: decomposed.rotation,
                                                        scale: decomposed.scale)
        }

        return AnimationPoseRuntimeState(sampleTime: playbackTime,
                                         localPose: localPose,
                                         globalPose: globalPose)
    }

    private func makeBindPoseState(skeleton: SkeletonAsset,
                                   playbackTime: Float) -> AnimationPoseRuntimeState {
        let localPose = skeleton.joints.map { joint in
            TransformComponent(position: joint.bindLocalPosition,
                               rotation: joint.bindLocalRotation,
                               scale: joint.bindLocalScale)
        }
        let globalMatrices = globalMatrices(from: localPose, skeleton: skeleton)
        var globalPose = Array(repeating: TransformComponent(), count: localPose.count)
        for jointIndex in 0..<globalMatrices.count {
            let decomposed = TransformMath.decomposeMatrix(globalMatrices[jointIndex])
            globalPose[jointIndex] = TransformComponent(position: decomposed.position,
                                                        rotation: decomposed.rotation,
                                                        scale: decomposed.scale)
        }
        return AnimationPoseRuntimeState(sampleTime: playbackTime, localPose: localPose, globalPose: globalPose)
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

    private func globalMatrices(from localPose: [TransformComponent], skeleton: SkeletonAsset) -> [matrix_float4x4] {
        let jointCount = min(skeleton.joints.count, localPose.count)
        guard jointCount > 0 else { return [] }
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

    private func logRuntimeIssueOnce(key: String, message: String, level: MCLogLevel) {
#if DEBUG
        guard !loggedRuntimeIssueKeys.contains(key) else { return }
        loggedRuntimeIssueKeys.insert(key)
        EngineLoggerContext.log(
            message,
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
