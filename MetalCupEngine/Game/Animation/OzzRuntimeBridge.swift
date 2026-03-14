import Foundation
import simd

@_silgen_name("MCEOzzCreateSkeletonRuntime")
private func MCEOzzCreateSkeletonRuntime(_ joints: UnsafePointer<OzzJointRestPoseC>?,
                                         _ jointCount: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroySkeletonRuntime")
func MCEOzzDestroySkeletonRuntime(_ runtimePtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzSkeletonRuntimeJointCount")
private func MCEOzzSkeletonRuntimeJointCount(_ runtimePtr: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("MCEOzzCreateAnimationRuntime")
private func MCEOzzCreateAnimationRuntime(_ name: UnsafePointer<CChar>?,
                                          _ durationSeconds: Float,
                                          _ jointTrackCount: Int32,
                                          _ trackSpans: UnsafePointer<OzzTrackSpanC>?,
                                          _ trackSpanCount: Int32,
                                          _ translationKeys: UnsafePointer<OzzVec3KeyC>?,
                                          _ translationKeyCount: Int32,
                                          _ rotationKeys: UnsafePointer<OzzQuatKeyC>?,
                                          _ rotationKeyCount: Int32,
                                          _ scaleKeys: UnsafePointer<OzzVec3KeyC>?,
                                          _ scaleKeyCount: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroyAnimationRuntime")
func MCEOzzDestroyAnimationRuntime(_ runtimePtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzAnimationRuntimeJointCount")
private func MCEOzzAnimationRuntimeJointCount(_ runtimePtr: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("MCEOzzCreateSamplingContext")
func MCEOzzCreateSamplingContext(_ maxSoaTracks: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroySamplingContext")
func MCEOzzDestroySamplingContext(_ contextPtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzCreateLocalToModelContext")
func MCEOzzCreateLocalToModelContext(_ maxSoaTracks: Int32,
                                     _ maxJoints: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroyLocalToModelContext")
func MCEOzzDestroyLocalToModelContext(_ contextPtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzCreateBlendingContext")
func MCEOzzCreateBlendingContext(_ maxSoaTracks: Int32,
                                 _ maxLayers: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroyBlendingContext")
func MCEOzzDestroyBlendingContext(_ contextPtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzBlendLocalPoses")
private func MCEOzzBlendLocalPoses(_ skeletonRuntimePtr: UnsafeMutableRawPointer?,
                                   _ blendingContextPtr: UnsafeMutableRawPointer?,
                                   _ localTransforms: UnsafePointer<OzzLocalTransformC>?,
                                   _ transformsPerPose: Int32,
                                   _ poseCount: Int32,
                                   _ layerWeights: UnsafePointer<Float>?,
                                   _ layerWeightCount: Int32,
                                   _ outTransforms: UnsafeMutablePointer<OzzLocalTransformC>?,
                                   _ outTransformCount: Int32) -> UInt32

@_silgen_name("MCEOzzCreateRootMotionContext")
func MCEOzzCreateRootMotionContext(_ maxSoaTracks: Int32,
                                   _ maxJoints: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("MCEOzzDestroyRootMotionContext")
func MCEOzzDestroyRootMotionContext(_ contextPtr: UnsafeMutableRawPointer)

@_silgen_name("MCEOzzExtractRootMotionDelta")
private func MCEOzzExtractRootMotionDelta(_ skeletonRuntimePtr: UnsafeMutableRawPointer?,
                                          _ animationRuntimePtr: UnsafeMutableRawPointer?,
                                          _ rootMotionContextPtr: UnsafeMutableRawPointer?,
                                          _ translationJointIndex: Int32,
                                          _ rotationJointIndex: Int32,
                                          _ previousTimeSeconds: Float,
                                          _ currentTimeSeconds: Float,
                                          _ outDeltaPos3: UnsafeMutablePointer<Float>?,
                                          _ outDeltaRot4: UnsafeMutablePointer<Float>?) -> UInt32

@_silgen_name("MCEOzzBlendRootMotionDeltas")
private func MCEOzzBlendRootMotionDeltas(_ deltas: UnsafePointer<OzzLocalTransformC>?,
                                         _ deltaCount: Int32,
                                         _ weights: UnsafePointer<Float>?,
                                         _ weightCount: Int32,
                                         _ outDelta: UnsafeMutablePointer<OzzLocalTransformC>?) -> UInt32

@_silgen_name("MCEOzzLocalToModel")
private func MCEOzzLocalToModel(_ skeletonRuntimePtr: UnsafeMutableRawPointer?,
                                _ localToModelContextPtr: UnsafeMutableRawPointer?,
                                _ localTransforms: UnsafePointer<OzzLocalTransformC>?,
                                _ localTransformCount: Int32,
                                _ outModelMatrices: UnsafeMutablePointer<OzzModelMatrixC>?,
                                _ outModelMatrixCount: Int32) -> UInt32

@_silgen_name("MCEOzzSampleLocalPose")
private func MCEOzzSampleLocalPose(_ skeletonRuntimePtr: UnsafeMutableRawPointer?,
                                   _ animationRuntimePtr: UnsafeMutableRawPointer?,
                                   _ samplingContextPtr: UnsafeMutableRawPointer?,
                                   _ timeSeconds: Float,
                                   _ outTransforms: UnsafeMutablePointer<OzzLocalTransformC>?,
                                   _ outTransformCount: Int32) -> UInt32

enum OzzRuntimeBridge {
    static func makeSkeletonRuntime(from skeleton: SkeletonAsset) -> OzzSkeletonRuntime? {
        guard !skeleton.joints.isEmpty else { return nil }
        let jointPayload: [OzzJointRestPoseC] = skeleton.joints.map { joint in
            OzzJointRestPoseC(parentIndex: Int32(joint.parentIndex),
                              tx: joint.bindLocalPosition.x,
                              ty: joint.bindLocalPosition.y,
                              tz: joint.bindLocalPosition.z,
                              rx: joint.bindLocalRotation.x,
                              ry: joint.bindLocalRotation.y,
                              rz: joint.bindLocalRotation.z,
                              rw: joint.bindLocalRotation.w,
                              sx: joint.bindLocalScale.x,
                              sy: joint.bindLocalScale.y,
                              sz: joint.bindLocalScale.z)
        }

        return jointPayload.withUnsafeBufferPointer { jointBuffer in
            guard let handle = MCEOzzCreateSkeletonRuntime(jointBuffer.baseAddress, Int32(jointBuffer.count)) else {
                return nil
            }
            let jointCount = Int(MCEOzzSkeletonRuntimeJointCount(handle))
            guard jointCount > 0 else {
                MCEOzzDestroySkeletonRuntime(handle)
                return nil
            }
            return OzzSkeletonRuntime(nativeHandle: handle, jointCount: jointCount)
        }
    }

    static func makeAnimationRuntime(from clip: AnimationClipAsset,
                                     jointTrackCount: Int) -> OzzAnimationRuntime? {
        guard jointTrackCount > 0 else { return nil }

        var translationKeys: [OzzVec3KeyC] = []
        var rotationKeys: [OzzQuatKeyC] = []
        var scaleKeys: [OzzVec3KeyC] = []
        var trackSpans = Array(
            repeating: OzzTrackSpanC(jointIndex: 0,
                                      translationStart: 0,
                                      translationCount: 0,
                                      rotationStart: 0,
                                      rotationCount: 0,
                                      scaleStart: 0,
                                      scaleCount: 0),
            count: jointTrackCount
        )

        for jointIndex in 0..<jointTrackCount {
            trackSpans[jointIndex].jointIndex = Int32(jointIndex)
        }

        var trackByJointIndex: [Int: AnimationClipAsset.JointTrack] = [:]
        for track in clip.tracks where track.jointIndex >= 0 && track.jointIndex < jointTrackCount {
            trackByJointIndex[track.jointIndex] = track
        }

        for jointIndex in 0..<jointTrackCount {
            guard let track = trackByJointIndex[jointIndex] else { continue }

            let translationStart = translationKeys.count
            translationKeys.reserveCapacity(translationKeys.count + track.translations.count)
            for key in track.translations {
                translationKeys.append(OzzVec3KeyC(time: key.time,
                                                   x: key.value.x,
                                                   y: key.value.y,
                                                   z: key.value.z))
            }

            let rotationStart = rotationKeys.count
            rotationKeys.reserveCapacity(rotationKeys.count + track.rotations.count)
            for key in track.rotations {
                rotationKeys.append(OzzQuatKeyC(time: key.time,
                                                x: key.value.x,
                                                y: key.value.y,
                                                z: key.value.z,
                                                w: key.value.w))
            }

            let scaleStart = scaleKeys.count
            scaleKeys.reserveCapacity(scaleKeys.count + track.scales.count)
            for key in track.scales {
                scaleKeys.append(OzzVec3KeyC(time: key.time,
                                             x: key.value.x,
                                             y: key.value.y,
                                             z: key.value.z))
            }

            trackSpans[jointIndex].translationStart = Int32(translationStart)
            trackSpans[jointIndex].translationCount = Int32(track.translations.count)
            trackSpans[jointIndex].rotationStart = Int32(rotationStart)
            trackSpans[jointIndex].rotationCount = Int32(track.rotations.count)
            trackSpans[jointIndex].scaleStart = Int32(scaleStart)
            trackSpans[jointIndex].scaleCount = Int32(track.scales.count)
        }

        let duration = max(clip.durationSeconds, 1.0e-5)
        let clipName = clip.name.isEmpty ? "clip" : clip.name

        return clipName.withCString { clipNameCString in
            trackSpans.withUnsafeBufferPointer { spansBuffer in
                translationKeys.withUnsafeBufferPointer { translationBuffer in
                    rotationKeys.withUnsafeBufferPointer { rotationBuffer in
                        scaleKeys.withUnsafeBufferPointer { scaleBuffer in
                            guard let handle = MCEOzzCreateAnimationRuntime(
                                clipNameCString,
                                duration,
                                Int32(jointTrackCount),
                                spansBuffer.baseAddress,
                                Int32(spansBuffer.count),
                                translationBuffer.baseAddress,
                                Int32(translationBuffer.count),
                                rotationBuffer.baseAddress,
                                Int32(rotationBuffer.count),
                                scaleBuffer.baseAddress,
                                Int32(scaleBuffer.count)
                            ) else {
                                return nil
                            }

                            let tracks = Int(MCEOzzAnimationRuntimeJointCount(handle))
                            guard tracks > 0 else {
                                MCEOzzDestroyAnimationRuntime(handle)
                                return nil
                            }
                            return OzzAnimationRuntime(nativeHandle: handle, jointCount: tracks)
                        }
                    }
                }
            }
        }
    }

    static func sampleLocalPose(skeletonRuntime: OzzSkeletonRuntime,
                                animationRuntime: OzzAnimationRuntime,
                                samplingContext: OzzSamplingContextRuntime,
                                timeSeconds: Float,
                                expectedJointCount: Int) -> [TransformComponent]? {
        let jointCount = min(expectedJointCount, min(skeletonRuntime.jointCount, animationRuntime.jointCount))
        guard jointCount > 0 else { return nil }

        var localTransforms = Array(
            repeating: OzzLocalTransformC(px: 0,
                                          py: 0,
                                          pz: 0,
                                          rx: 0,
                                          ry: 0,
                                          rz: 0,
                                          rw: 1,
                                          sx: 1,
                                          sy: 1,
                                          sz: 1),
            count: jointCount
        )

        let success = localTransforms.withUnsafeMutableBufferPointer { transformBuffer in
            MCEOzzSampleLocalPose(skeletonRuntime.nativeHandle,
                                  animationRuntime.nativeHandle,
                                  samplingContext.nativeHandle,
                                  timeSeconds,
                                  transformBuffer.baseAddress,
                                  Int32(transformBuffer.count)) != 0
        }
        guard success else { return nil }

        return localTransforms.map { transform in
            TransformComponent(position: SIMD3<Float>(transform.px, transform.py, transform.pz),
                               rotation: SIMD4<Float>(transform.rx, transform.ry, transform.rz, transform.rw),
                               scale: SIMD3<Float>(transform.sx, transform.sy, transform.sz))
        }
    }

    static func blendLocalPoses(skeletonRuntime: OzzSkeletonRuntime,
                                blendingContext: OzzBlendingContextRuntime,
                                localPoses: [[TransformComponent]],
                                weights: [Float],
                                expectedJointCount: Int) -> [TransformComponent]? {
        guard !localPoses.isEmpty, localPoses.count == weights.count else { return nil }
        let jointCount = min(expectedJointCount, min(localPoses.map(\.count).min() ?? 0, skeletonRuntime.jointCount))
        guard jointCount > 0 else { return nil }

        let flattenedLocalTransforms: [OzzLocalTransformC] = localPoses.flatMap { pose in
            pose.prefix(jointCount).map { transform in
                OzzLocalTransformC(px: transform.position.x,
                                   py: transform.position.y,
                                   pz: transform.position.z,
                                   rx: transform.rotation.x,
                                   ry: transform.rotation.y,
                                   rz: transform.rotation.z,
                                   rw: transform.rotation.w,
                                   sx: transform.scale.x,
                                   sy: transform.scale.y,
                                   sz: transform.scale.z)
            }
        }
        guard flattenedLocalTransforms.count == jointCount * localPoses.count else { return nil }

        var outputLocalTransforms = Array(
            repeating: OzzLocalTransformC(px: 0,
                                          py: 0,
                                          pz: 0,
                                          rx: 0,
                                          ry: 0,
                                          rz: 0,
                                          rw: 1,
                                          sx: 1,
                                          sy: 1,
                                          sz: 1),
            count: jointCount
        )

        let success = flattenedLocalTransforms.withUnsafeBufferPointer { localBuffer in
            weights.withUnsafeBufferPointer { weightBuffer in
                outputLocalTransforms.withUnsafeMutableBufferPointer { outputBuffer in
                    MCEOzzBlendLocalPoses(skeletonRuntime.nativeHandle,
                                          blendingContext.nativeHandle,
                                          localBuffer.baseAddress,
                                          Int32(jointCount),
                                          Int32(localPoses.count),
                                          weightBuffer.baseAddress,
                                          Int32(weightBuffer.count),
                                          outputBuffer.baseAddress,
                                          Int32(outputBuffer.count)) != 0
                }
            }
        }
        guard success else { return nil }

        return outputLocalTransforms.map { transform in
            TransformComponent(position: SIMD3<Float>(transform.px, transform.py, transform.pz),
                               rotation: SIMD4<Float>(transform.rx, transform.ry, transform.rz, transform.rw),
                               scale: SIMD3<Float>(transform.sx, transform.sy, transform.sz))
        }
    }

    static func makeRootMotionRuntime(skeletonRuntime: OzzSkeletonRuntime,
                                      animationRuntime: OzzAnimationRuntime) -> OzzRootMotionRuntime? {
        guard skeletonRuntime.jointCount > 0, animationRuntime.jointCount > 0 else { return nil }
        guard let handle = MCEOzzCreateRootMotionContext(Int32(skeletonRuntime.maxSoaTracks),
                                                         Int32(skeletonRuntime.jointCount)) else {
            return nil
        }
        return OzzRootMotionRuntime(nativeHandle: handle)
    }

    static func extractRootMotionDelta(skeletonRuntime: OzzSkeletonRuntime,
                                       animationRuntime: OzzAnimationRuntime,
                                       rootMotionRuntime: OzzRootMotionRuntime,
                                       translationJointIndex: Int,
                                       rotationJointIndex: Int,
                                       previousTimeSeconds: Float,
                                       currentTimeSeconds: Float) -> RootMotionDelta? {
        guard translationJointIndex >= 0, rotationJointIndex >= 0 else { return nil }
        var deltaPos = SIMD3<Float>(repeating: 0)
        var deltaRot = SIMD4<Float>(0, 0, 0, 1)
        let success = withUnsafeMutablePointer(to: &deltaPos) { posPtr in
            withUnsafeMutablePointer(to: &deltaRot) { rotPtr in
                posPtr.withMemoryRebound(to: Float.self, capacity: 3) { posFloats in
                    rotPtr.withMemoryRebound(to: Float.self, capacity: 4) { rotFloats in
                        MCEOzzExtractRootMotionDelta(skeletonRuntime.nativeHandle,
                                                     animationRuntime.nativeHandle,
                                                     rootMotionRuntime.nativeHandle,
                                                     Int32(translationJointIndex),
                                                     Int32(rotationJointIndex),
                                                     previousTimeSeconds,
                                                     currentTimeSeconds,
                                                     posFloats,
                                                     rotFloats) != 0
                    }
                }
            }
        }
        guard success else { return nil }
        return RootMotionDelta(deltaPos: deltaPos, deltaRot: deltaRot)
    }

    static func blendRootMotionDeltas(_ deltas: [RootMotionDelta],
                                      weights: [Float]) -> RootMotionDelta? {
        guard !deltas.isEmpty, deltas.count == weights.count else { return nil }
        let packedDeltas: [OzzLocalTransformC] = deltas.map { delta in
            OzzLocalTransformC(px: delta.deltaPos.x,
                               py: delta.deltaPos.y,
                               pz: delta.deltaPos.z,
                               rx: delta.deltaRot.x,
                               ry: delta.deltaRot.y,
                               rz: delta.deltaRot.z,
                               rw: delta.deltaRot.w,
                               sx: 1,
                               sy: 1,
                               sz: 1)
        }
        var output = OzzLocalTransformC(px: 0, py: 0, pz: 0, rx: 0, ry: 0, rz: 0, rw: 1, sx: 1, sy: 1, sz: 1)
        let success = packedDeltas.withUnsafeBufferPointer { deltaBuffer in
            weights.withUnsafeBufferPointer { weightBuffer in
                withUnsafeMutablePointer(to: &output) { outPtr in
                    MCEOzzBlendRootMotionDeltas(deltaBuffer.baseAddress,
                                                Int32(deltaBuffer.count),
                                                weightBuffer.baseAddress,
                                                Int32(weightBuffer.count),
                                                outPtr) != 0
                }
            }
        }
        guard success else { return nil }
        return RootMotionDelta(deltaPos: SIMD3<Float>(output.px, output.py, output.pz),
                               deltaRot: SIMD4<Float>(output.rx, output.ry, output.rz, output.rw))
    }

    static func localToModelMatrices(skeletonRuntime: OzzSkeletonRuntime,
                                     localToModelContext: OzzLocalToModelContextRuntime,
                                     localPose: [TransformComponent],
                                     expectedJointCount: Int) -> [matrix_float4x4]? {
        let jointCount = min(expectedJointCount, min(localPose.count, skeletonRuntime.jointCount))
        guard jointCount > 0 else { return nil }

        let localTransforms: [OzzLocalTransformC] = localPose.prefix(jointCount).map { transform in
            OzzLocalTransformC(px: transform.position.x,
                               py: transform.position.y,
                               pz: transform.position.z,
                               rx: transform.rotation.x,
                               ry: transform.rotation.y,
                               rz: transform.rotation.z,
                               rw: transform.rotation.w,
                               sx: transform.scale.x,
                               sy: transform.scale.y,
                               sz: transform.scale.z)
        }

        var modelMatrices = Array(
            repeating: OzzModelMatrixC(c0x: 1, c0y: 0, c0z: 0, c0w: 0,
                                       c1x: 0, c1y: 1, c1z: 0, c1w: 0,
                                       c2x: 0, c2y: 0, c2z: 1, c2w: 0,
                                       c3x: 0, c3y: 0, c3z: 0, c3w: 1),
            count: jointCount
        )

        let success = localTransforms.withUnsafeBufferPointer { localBuffer in
            modelMatrices.withUnsafeMutableBufferPointer { matrixBuffer in
                MCEOzzLocalToModel(skeletonRuntime.nativeHandle,
                                   localToModelContext.nativeHandle,
                                   localBuffer.baseAddress,
                                   Int32(localBuffer.count),
                                   matrixBuffer.baseAddress,
                                   Int32(matrixBuffer.count)) != 0
            }
        }
        guard success else { return nil }

        return modelMatrices.map { matrix in
            matrix_float4x4(
                columns: (
                    SIMD4<Float>(matrix.c0x, matrix.c0y, matrix.c0z, matrix.c0w),
                    SIMD4<Float>(matrix.c1x, matrix.c1y, matrix.c1z, matrix.c1w),
                    SIMD4<Float>(matrix.c2x, matrix.c2y, matrix.c2z, matrix.c2w),
                    SIMD4<Float>(matrix.c3x, matrix.c3y, matrix.c3z, matrix.c3w)
                )
            )
        }
    }
}
