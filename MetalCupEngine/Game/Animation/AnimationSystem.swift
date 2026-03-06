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
            let skinnedMesh = scene.ecs.get(SkinnedMeshComponent.self, for: entity)
            let skeleton = skinnedMesh?.skeletonHandle.flatMap { assets.skeleton(handle: $0) }
            let clip = animator.clipHandle.flatMap { assets.animationClip(handle: $0) }

            if updated.isPlaying, dt > 0 {
                updated.playbackTime = nextPlaybackTime(current: updated.playbackTime,
                                                        dt: dt,
                                                        duration: clip?.durationSeconds ?? 0.0,
                                                        isLooping: updated.isLooping)
                if let duration = clip?.durationSeconds,
                   duration > 0,
                   !updated.isLooping,
                   updated.playbackTime >= duration {
                    updated.isPlaying = false
                }
            }

            if let skeleton, let clip {
                updated.poseRuntimeState = evaluatePose(skeleton: skeleton,
                                                        clip: clip,
                                                        playbackTime: updated.playbackTime)
            } else {
                updated.poseRuntimeState = nil
            }
            scene.ecs.add(updated, to: entity)
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
                   let skeleton = assets.skeleton(handle: skeletonHandle),
                   let poseState = animator?.poseRuntimeState {
                    let paletteStart = bonePaletteMatrices.count
                    let palette = makeBonePalette(skeleton: skeleton, globalPose: poseState.globalPose)
                    bonePaletteMatrices.append(contentsOf: palette)
                    paletteRange = palette.isEmpty
                        ? nil
                        : AnimationSnapshotPayload.BonePaletteRange(startIndex: paletteStart, count: palette.count)
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

    private func makeBonePalette(skeleton: SkeletonAsset, globalPose: [TransformComponent]) -> [matrix_float4x4] {
        let jointCount = min(skeleton.joints.count, globalPose.count)
        guard jointCount > 0 else { return [] }

        var bindGlobalMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.joints.count)
        for jointIndex in 0..<skeleton.joints.count {
            let joint = skeleton.joints[jointIndex]
            let localBind = TransformMath.makeMatrix(position: joint.bindLocalPosition,
                                                     rotation: joint.bindLocalRotation,
                                                     scale: joint.bindLocalScale)
            let parentIndex = joint.parentIndex
            if parentIndex >= 0, parentIndex < skeleton.joints.count {
                bindGlobalMatrices[jointIndex] = bindGlobalMatrices[parentIndex] * localBind
            } else {
                bindGlobalMatrices[jointIndex] = localBind
            }
        }

        var palette = Array(repeating: matrix_identity_float4x4, count: jointCount)
        for jointIndex in 0..<jointCount {
            let pose = globalPose[jointIndex]
            let animatedGlobal = TransformMath.makeMatrix(position: pose.position,
                                                          rotation: pose.rotation,
                                                          scale: pose.scale)
            let inverseBind = simd_inverse(bindGlobalMatrices[jointIndex])
            palette[jointIndex] = animatedGlobal * inverseBind
        }
        return palette
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

        var globalPose = Array(repeating: TransformComponent(), count: jointCount)
        var globalMatrices = Array(repeating: matrix_identity_float4x4, count: jointCount)
        for jointIndex in 0..<jointCount {
            let joint = skeleton.joints[jointIndex]
            let local = localPose[jointIndex]
            let localMatrix = TransformMath.makeMatrix(position: local.position,
                                                       rotation: local.rotation,
                                                       scale: local.scale)
            let parentIndex = joint.parentIndex
            let worldMatrix: matrix_float4x4
            if parentIndex >= 0, parentIndex < jointCount {
                worldMatrix = globalMatrices[parentIndex] * localMatrix
            } else {
                worldMatrix = localMatrix
            }
            globalMatrices[jointIndex] = worldMatrix
            let decomposed = TransformMath.decomposeMatrix(worldMatrix)
            globalPose[jointIndex] = TransformComponent(position: decomposed.position,
                                                        rotation: decomposed.rotation,
                                                        scale: decomposed.scale)
        }

        return AnimationPoseRuntimeState(sampleTime: playbackTime,
                                         localPose: localPose,
                                         globalPose: globalPose)
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
}
