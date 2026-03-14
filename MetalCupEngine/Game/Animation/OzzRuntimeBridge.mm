#import <Foundation/Foundation.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "ozz/animation/offline/animation_builder.h"
#include "ozz/animation/offline/raw_animation.h"
#include "ozz/animation/offline/raw_skeleton.h"
#include "ozz/animation/offline/skeleton_builder.h"
#include "ozz/animation/runtime/animation.h"
#include "ozz/animation/runtime/blending_job.h"
#include "ozz/animation/runtime/local_to_model_job.h"
#include "ozz/animation/runtime/sampling_job.h"
#include "ozz/animation/runtime/skeleton.h"
#include "ozz/base/maths/simd_math.h"
#include "ozz/base/maths/soa_transform.h"
#include "ozz/base/memory/unique_ptr.h"

namespace {
using ozz::animation::Animation;
using ozz::animation::BlendingJob;
using ozz::animation::LocalToModelJob;
using ozz::animation::SamplingJob;
using ozz::animation::Skeleton;

struct OzzSkeletonRuntime {
    ozz::unique_ptr<Skeleton> skeleton;
    int jointCount = 0;
};

struct OzzAnimationRuntime {
    ozz::unique_ptr<Animation> animation;
    int jointCount = 0;
    float duration = 0.0f;
};

struct OzzSamplingContextRuntime {
    explicit OzzSamplingContextRuntime(int maxSoaTracks)
    : context(maxSoaTracks) {}

    SamplingJob::Context context;
};

struct OzzLocalToModelContextRuntime {
    OzzLocalToModelContextRuntime(int maxSoaTracks, int maxJoints)
    : localSoaTransforms(static_cast<size_t>(std::max(maxSoaTracks, 0))),
      modelMatrices(static_cast<size_t>(std::max(maxJoints, 0))) {}

    void ensureCapacity(int soaTrackCount, int jointCount) {
        if (soaTrackCount > 0) {
            localSoaTransforms.resize(static_cast<size_t>(soaTrackCount));
        }
        if (jointCount > 0) {
            modelMatrices.resize(static_cast<size_t>(jointCount));
        }
    }

    std::vector<ozz::math::SoaTransform> localSoaTransforms;
    std::vector<ozz::math::Float4x4> modelMatrices;
};

struct OzzBlendingContextRuntime {
    OzzBlendingContextRuntime(int maxSoaTracks, int maxLayers)
    : outputSoaTransforms(static_cast<size_t>(std::max(maxSoaTracks, 0))) {
        ensureCapacity(maxSoaTracks, maxLayers);
    }

    void ensureCapacity(int soaTrackCount, int layerCount) {
        const int safeSoaTrackCount = std::max(soaTrackCount, 0);
        const int safeLayerCount = std::max(layerCount, 0);
        outputSoaTransforms.resize(static_cast<size_t>(safeSoaTrackCount));
        layerTransforms.resize(static_cast<size_t>(safeLayerCount));
        layers.resize(static_cast<size_t>(safeLayerCount));
        for (auto& transforms : layerTransforms) {
            transforms.resize(static_cast<size_t>(safeSoaTrackCount));
        }
    }

    std::vector<std::vector<ozz::math::SoaTransform>> layerTransforms;
    std::vector<BlendingJob::Layer> layers;
    std::vector<ozz::math::SoaTransform> outputSoaTransforms;
};

struct OzzRootMotionContextRuntime {
    OzzRootMotionContextRuntime(int maxSoaTracks, int maxJoints)
    : samplingContext(maxSoaTracks),
      sampledLocals(static_cast<size_t>(std::max(maxSoaTracks, 0))),
      modelMatrices(static_cast<size_t>(std::max(maxJoints, 0))) {}

    void ensureCapacity(int soaTrackCount, int jointCount) {
        if (soaTrackCount > 0) {
            sampledLocals.resize(static_cast<size_t>(soaTrackCount));
        }
        if (jointCount > 0) {
            modelMatrices.resize(static_cast<size_t>(jointCount));
        }
    }

    SamplingJob::Context samplingContext;
    std::vector<ozz::math::SoaTransform> sampledLocals;
    std::vector<ozz::math::Float4x4> modelMatrices;
};

struct JointRestPoseC {
    int32_t parentIndex;
    float tx;
    float ty;
    float tz;
    float rx;
    float ry;
    float rz;
    float rw;
    float sx;
    float sy;
    float sz;
};

struct TrackSpanC {
    int32_t jointIndex;
    int32_t translationStart;
    int32_t translationCount;
    int32_t rotationStart;
    int32_t rotationCount;
    int32_t scaleStart;
    int32_t scaleCount;
};

struct Vec3KeyC {
    float time;
    float x;
    float y;
    float z;
};

struct QuatKeyC {
    float time;
    float x;
    float y;
    float z;
    float w;
};

struct LocalTransformC {
    float px;
    float py;
    float pz;
    float rx;
    float ry;
    float rz;
    float rw;
    float sx;
    float sy;
    float sz;
};

struct ModelMatrixC {
    float c0x;
    float c0y;
    float c0z;
    float c0w;
    float c1x;
    float c1y;
    float c1z;
    float c1w;
    float c2x;
    float c2y;
    float c2z;
    float c2w;
    float c3x;
    float c3y;
    float c3z;
    float c3w;
};

static float normalizedRatio(float timeSeconds, float durationSeconds) {
    if (!std::isfinite(durationSeconds) || durationSeconds <= 1.0e-6f) {
        return 0.0f;
    }
    float ratio = timeSeconds / durationSeconds;
    if (!std::isfinite(ratio)) {
        return 0.0f;
    }
    ratio = ratio - std::floor(ratio);
    if (ratio < 0.0f) {
        ratio += 1.0f;
    }
    return ratio;
}

static void storeSoaLane(const ozz::math::SoaTransform& soa,
                         int lane,
                         LocalTransformC* outTransform) {
    using namespace ozz::math;

    SimdFloat4 translationIn[3] = {soa.translation.x, soa.translation.y, soa.translation.z};
    SimdFloat4 translationOut[4];
    Transpose3x4(translationIn, translationOut);

    SimdFloat4 rotationIn[4] = {soa.rotation.x, soa.rotation.y, soa.rotation.z, soa.rotation.w};
    SimdFloat4 rotationOut[4];
    Transpose4x4(rotationIn, rotationOut);

    SimdFloat4 scaleIn[3] = {soa.scale.x, soa.scale.y, soa.scale.z};
    SimdFloat4 scaleOut[4];
    Transpose3x4(scaleIn, scaleOut);

    float translation[4] = {};
    float rotation[4] = {};
    float scale[4] = {};
    StorePtrU(translationOut[lane], translation);
    StorePtrU(rotationOut[lane], rotation);
    StorePtrU(scaleOut[lane], scale);

    outTransform->px = translation[0];
    outTransform->py = translation[1];
    outTransform->pz = translation[2];

    outTransform->rx = rotation[0];
    outTransform->ry = rotation[1];
    outTransform->rz = rotation[2];
    outTransform->rw = rotation[3];

    outTransform->sx = scale[0];
    outTransform->sy = scale[1];
    outTransform->sz = scale[2];
}

static ozz::math::SoaTransform makeSoaTransform(const LocalTransformC* localTransforms,
                                                 int32_t localCount,
                                                 int32_t baseJointIndex) {
    using namespace ozz::math;

    std::array<float, 4> tx = {0.f, 0.f, 0.f, 0.f};
    std::array<float, 4> ty = {0.f, 0.f, 0.f, 0.f};
    std::array<float, 4> tz = {0.f, 0.f, 0.f, 0.f};

    std::array<float, 4> rx = {0.f, 0.f, 0.f, 0.f};
    std::array<float, 4> ry = {0.f, 0.f, 0.f, 0.f};
    std::array<float, 4> rz = {0.f, 0.f, 0.f, 0.f};
    std::array<float, 4> rw = {1.f, 1.f, 1.f, 1.f};

    std::array<float, 4> sx = {1.f, 1.f, 1.f, 1.f};
    std::array<float, 4> sy = {1.f, 1.f, 1.f, 1.f};
    std::array<float, 4> sz = {1.f, 1.f, 1.f, 1.f};

    for (int lane = 0; lane < 4; ++lane) {
        const int32_t jointIndex = baseJointIndex + lane;
        if (jointIndex < 0 || jointIndex >= localCount) {
            continue;
        }
        const LocalTransformC& local = localTransforms[jointIndex];
        tx[static_cast<size_t>(lane)] = local.px;
        ty[static_cast<size_t>(lane)] = local.py;
        tz[static_cast<size_t>(lane)] = local.pz;
        rx[static_cast<size_t>(lane)] = local.rx;
        ry[static_cast<size_t>(lane)] = local.ry;
        rz[static_cast<size_t>(lane)] = local.rz;
        rw[static_cast<size_t>(lane)] = local.rw;
        sx[static_cast<size_t>(lane)] = local.sx;
        sy[static_cast<size_t>(lane)] = local.sy;
        sz[static_cast<size_t>(lane)] = local.sz;
    }

    ozz::math::SoaTransform soa;
    soa.translation.x = simd_float4::LoadPtrU(tx.data());
    soa.translation.y = simd_float4::LoadPtrU(ty.data());
    soa.translation.z = simd_float4::LoadPtrU(tz.data());
    soa.rotation.x = simd_float4::LoadPtrU(rx.data());
    soa.rotation.y = simd_float4::LoadPtrU(ry.data());
    soa.rotation.z = simd_float4::LoadPtrU(rz.data());
    soa.rotation.w = simd_float4::LoadPtrU(rw.data());
    soa.scale.x = simd_float4::LoadPtrU(sx.data());
    soa.scale.y = simd_float4::LoadPtrU(sy.data());
    soa.scale.z = simd_float4::LoadPtrU(sz.data());
    return soa;
}

static void storeModelMatrix(const ozz::math::Float4x4& matrix, ModelMatrixC* outMatrix) {
    using namespace ozz::math;
    float c0[4] = {};
    float c1[4] = {};
    float c2[4] = {};
    float c3[4] = {};
    StorePtrU(matrix.cols[0], c0);
    StorePtrU(matrix.cols[1], c1);
    StorePtrU(matrix.cols[2], c2);
    StorePtrU(matrix.cols[3], c3);

    outMatrix->c0x = c0[0];
    outMatrix->c0y = c0[1];
    outMatrix->c0z = c0[2];
    outMatrix->c0w = c0[3];

    outMatrix->c1x = c1[0];
    outMatrix->c1y = c1[1];
    outMatrix->c1z = c1[2];
    outMatrix->c1w = c1[3];

    outMatrix->c2x = c2[0];
    outMatrix->c2y = c2[1];
    outMatrix->c2z = c2[2];
    outMatrix->c2w = c2[3];

    outMatrix->c3x = c3[0];
    outMatrix->c3y = c3[1];
    outMatrix->c3z = c3[2];
    outMatrix->c3w = c3[3];
}

struct Float3Value {
    float x;
    float y;
    float z;
};

struct QuaternionValue {
    float x;
    float y;
    float z;
    float w;
};

static QuaternionValue normalizeQuaternion(QuaternionValue q) {
    const float lengthSquared = (q.x * q.x) + (q.y * q.y) + (q.z * q.z) + (q.w * q.w);
    if (!std::isfinite(lengthSquared) || lengthSquared <= 1.0e-12f) {
        return {0.0f, 0.0f, 0.0f, 1.0f};
    }
    const float invLength = 1.0f / std::sqrt(lengthSquared);
    return {q.x * invLength, q.y * invLength, q.z * invLength, q.w * invLength};
}

static QuaternionValue conjugateQuaternion(QuaternionValue q) {
    return {-q.x, -q.y, -q.z, q.w};
}

static QuaternionValue multiplyQuaternion(QuaternionValue a, QuaternionValue b) {
    return {
        (a.w * b.x) + (a.x * b.w) + (a.y * b.z) - (a.z * b.y),
        (a.w * b.y) - (a.x * b.z) + (a.y * b.w) + (a.z * b.x),
        (a.w * b.z) + (a.x * b.y) - (a.y * b.x) + (a.z * b.w),
        (a.w * b.w) - (a.x * b.x) - (a.y * b.y) - (a.z * b.z)
    };
}

static Float3Value rotateVector(QuaternionValue q, Float3Value v) {
    const QuaternionValue vectorQuaternion = {v.x, v.y, v.z, 0.0f};
    const QuaternionValue rotated = multiplyQuaternion(multiplyQuaternion(q, vectorQuaternion), conjugateQuaternion(q));
    return {rotated.x, rotated.y, rotated.z};
}

static bool sampleModelTransformsAtTime(const OzzSkeletonRuntime* skeletonRuntime,
                                        const OzzAnimationRuntime* animationRuntime,
                                        OzzRootMotionContextRuntime* contextRuntime,
                                        float timeSeconds,
                                        int32_t jointCount,
                                        int32_t soaTrackCount) {
    SamplingJob sampleJob;
    sampleJob.animation = animationRuntime->animation.get();
    sampleJob.context = &contextRuntime->samplingContext;
    sampleJob.ratio = normalizedRatio(timeSeconds, animationRuntime->duration);
    sampleJob.output = ozz::make_span(contextRuntime->sampledLocals);
    if (!sampleJob.Run()) {
        return false;
    }

    LocalToModelJob localToModelJob;
    localToModelJob.skeleton = skeletonRuntime->skeleton.get();
    localToModelJob.input = ozz::span<const ozz::math::SoaTransform>(contextRuntime->sampledLocals.data(),
                                                                      static_cast<size_t>(soaTrackCount));
    localToModelJob.output = ozz::span<ozz::math::Float4x4>(contextRuntime->modelMatrices.data(),
                                                             static_cast<size_t>(jointCount));
    return localToModelJob.Run();
}
}  // namespace

extern "C" {

void* MCEOzzCreateSkeletonRuntime(const JointRestPoseC* joints, int32_t jointCount) {
    if (!joints || jointCount <= 0) {
        return nullptr;
    }

    ozz::animation::offline::RawSkeleton raw;
    raw.roots.resize(0);

    std::vector<std::vector<int>> children(static_cast<size_t>(jointCount));
    std::vector<int> rootIndices;
    rootIndices.reserve(static_cast<size_t>(jointCount));

    for (int32_t jointIndex = 0; jointIndex < jointCount; ++jointIndex) {
        const int32_t parent = joints[jointIndex].parentIndex;
        if (parent >= 0 && parent < jointCount && parent != jointIndex) {
            children[static_cast<size_t>(parent)].push_back(jointIndex);
        } else {
            rootIndices.push_back(jointIndex);
        }
    }

    std::function<void(ozz::animation::offline::RawSkeleton::Joint&, int)> buildJoint =
        [&](ozz::animation::offline::RawSkeleton::Joint& outJoint, int jointIndex) {
            const JointRestPoseC& source = joints[jointIndex];
            outJoint.name = "joint_" + std::to_string(jointIndex);
            outJoint.transform.translation = ozz::math::Float3(source.tx, source.ty, source.tz);
            outJoint.transform.rotation = ozz::math::Quaternion(source.rx, source.ry, source.rz, source.rw);
            outJoint.transform.scale = ozz::math::Float3(source.sx, source.sy, source.sz);

            const auto& childIndices = children[static_cast<size_t>(jointIndex)];
            outJoint.children.resize(childIndices.size());
            for (size_t childCursor = 0; childCursor < childIndices.size(); ++childCursor) {
                buildJoint(outJoint.children[childCursor], childIndices[childCursor]);
            }
        };

    raw.roots.resize(rootIndices.size());
    for (size_t rootCursor = 0; rootCursor < rootIndices.size(); ++rootCursor) {
        buildJoint(raw.roots[rootCursor], rootIndices[rootCursor]);
    }

    ozz::animation::offline::SkeletonBuilder builder;
    ozz::unique_ptr<Skeleton> skeleton = builder(raw);
    if (!skeleton) {
        return nullptr;
    }

    auto runtime = std::make_unique<OzzSkeletonRuntime>();
    runtime->jointCount = skeleton->num_joints();
    runtime->skeleton = std::move(skeleton);
    return runtime.release();
}

void MCEOzzDestroySkeletonRuntime(void* runtimePtr) {
    auto* runtime = static_cast<OzzSkeletonRuntime*>(runtimePtr);
    delete runtime;
}

int32_t MCEOzzSkeletonRuntimeJointCount(void* runtimePtr) {
    auto* runtime = static_cast<OzzSkeletonRuntime*>(runtimePtr);
    return runtime ? runtime->jointCount : 0;
}

void* MCEOzzCreateAnimationRuntime(const char* name,
                                   float durationSeconds,
                                   int32_t jointTrackCount,
                                   const TrackSpanC* trackSpans,
                                   int32_t trackSpanCount,
                                   const Vec3KeyC* translationKeys,
                                   int32_t translationKeyCount,
                                   const QuatKeyC* rotationKeys,
                                   int32_t rotationKeyCount,
                                   const Vec3KeyC* scaleKeys,
                                   int32_t scaleKeyCount) {
    if (!trackSpans || jointTrackCount <= 0 || trackSpanCount <= 0) {
        return nullptr;
    }

    ozz::animation::offline::RawAnimation raw;
    raw.duration = std::max(durationSeconds, 1.0e-5f);
    raw.name = name ? name : "clip";
    raw.tracks.resize(static_cast<size_t>(jointTrackCount));

    for (int32_t spanIndex = 0; spanIndex < trackSpanCount; ++spanIndex) {
        const TrackSpanC& span = trackSpans[spanIndex];
        if (span.jointIndex < 0 || span.jointIndex >= jointTrackCount) {
            continue;
        }

        auto& track = raw.tracks[static_cast<size_t>(span.jointIndex)];

        if (translationKeys && span.translationStart >= 0 && span.translationCount > 0 &&
            span.translationStart + span.translationCount <= translationKeyCount) {
            track.translations.reserve(static_cast<size_t>(span.translationCount));
            for (int32_t keyIndex = 0; keyIndex < span.translationCount; ++keyIndex) {
                const Vec3KeyC& key = translationKeys[static_cast<size_t>(span.translationStart + keyIndex)];
                ozz::animation::offline::RawAnimation::TranslationKey converted;
                converted.time = key.time;
                converted.value = ozz::math::Float3(key.x, key.y, key.z);
                track.translations.push_back(converted);
            }
        }

        if (rotationKeys && span.rotationStart >= 0 && span.rotationCount > 0 &&
            span.rotationStart + span.rotationCount <= rotationKeyCount) {
            track.rotations.reserve(static_cast<size_t>(span.rotationCount));
            for (int32_t keyIndex = 0; keyIndex < span.rotationCount; ++keyIndex) {
                const QuatKeyC& key = rotationKeys[static_cast<size_t>(span.rotationStart + keyIndex)];
                ozz::animation::offline::RawAnimation::RotationKey converted;
                converted.time = key.time;
                converted.value = ozz::math::Quaternion(key.x, key.y, key.z, key.w);
                track.rotations.push_back(converted);
            }
        }

        if (scaleKeys && span.scaleStart >= 0 && span.scaleCount > 0 &&
            span.scaleStart + span.scaleCount <= scaleKeyCount) {
            track.scales.reserve(static_cast<size_t>(span.scaleCount));
            for (int32_t keyIndex = 0; keyIndex < span.scaleCount; ++keyIndex) {
                const Vec3KeyC& key = scaleKeys[static_cast<size_t>(span.scaleStart + keyIndex)];
                ozz::animation::offline::RawAnimation::ScaleKey converted;
                converted.time = key.time;
                converted.value = ozz::math::Float3(key.x, key.y, key.z);
                track.scales.push_back(converted);
            }
        }
    }

    if (!raw.Validate()) {
        return nullptr;
    }

    ozz::animation::offline::AnimationBuilder builder;
    ozz::unique_ptr<Animation> animation = builder(raw);
    if (!animation) {
        return nullptr;
    }

    auto runtime = std::make_unique<OzzAnimationRuntime>();
    runtime->jointCount = animation->num_tracks();
    runtime->duration = animation->duration();
    runtime->animation = std::move(animation);
    return runtime.release();
}

void MCEOzzDestroyAnimationRuntime(void* runtimePtr) {
    auto* runtime = static_cast<OzzAnimationRuntime*>(runtimePtr);
    delete runtime;
}

int32_t MCEOzzAnimationRuntimeJointCount(void* runtimePtr) {
    auto* runtime = static_cast<OzzAnimationRuntime*>(runtimePtr);
    return runtime ? runtime->jointCount : 0;
}

void* MCEOzzCreateSamplingContext(int32_t maxSoaTracks) {
    if (maxSoaTracks <= 0) {
        return nullptr;
    }
    auto runtime = std::make_unique<OzzSamplingContextRuntime>(maxSoaTracks);
    return runtime.release();
}

void MCEOzzDestroySamplingContext(void* contextPtr) {
    auto* runtime = static_cast<OzzSamplingContextRuntime*>(contextPtr);
    delete runtime;
}

void* MCEOzzCreateLocalToModelContext(int32_t maxSoaTracks, int32_t maxJoints) {
    if (maxSoaTracks <= 0 || maxJoints <= 0) {
        return nullptr;
    }
    auto runtime = std::make_unique<OzzLocalToModelContextRuntime>(maxSoaTracks, maxJoints);
    return runtime.release();
}

void MCEOzzDestroyLocalToModelContext(void* contextPtr) {
    auto* runtime = static_cast<OzzLocalToModelContextRuntime*>(contextPtr);
    delete runtime;
}

void* MCEOzzCreateBlendingContext(int32_t maxSoaTracks, int32_t maxLayers) {
    if (maxSoaTracks <= 0 || maxLayers <= 0) {
        return nullptr;
    }
    auto runtime = std::make_unique<OzzBlendingContextRuntime>(maxSoaTracks, maxLayers);
    return runtime.release();
}

void MCEOzzDestroyBlendingContext(void* contextPtr) {
    auto* runtime = static_cast<OzzBlendingContextRuntime*>(contextPtr);
    delete runtime;
}

void* MCEOzzCreateRootMotionContext(int32_t maxSoaTracks, int32_t maxJoints) {
    if (maxSoaTracks <= 0 || maxJoints <= 0) {
        return nullptr;
    }
    auto runtime = std::make_unique<OzzRootMotionContextRuntime>(maxSoaTracks, maxJoints);
    return runtime.release();
}

void MCEOzzDestroyRootMotionContext(void* contextPtr) {
    auto* runtime = static_cast<OzzRootMotionContextRuntime*>(contextPtr);
    delete runtime;
}

uint32_t MCEOzzExtractRootMotionDelta(void* skeletonRuntimePtr,
                                      void* animationRuntimePtr,
                                      void* rootMotionContextPtr,
                                      int32_t translationJointIndex,
                                      int32_t rotationJointIndex,
                                      float previousTimeSeconds,
                                      float currentTimeSeconds,
                                      float* outDeltaPos3,
                                      float* outDeltaRot4) {
    auto* skeletonRuntime = static_cast<OzzSkeletonRuntime*>(skeletonRuntimePtr);
    auto* animationRuntime = static_cast<OzzAnimationRuntime*>(animationRuntimePtr);
    auto* contextRuntime = static_cast<OzzRootMotionContextRuntime*>(rootMotionContextPtr);

    if (!skeletonRuntime || !animationRuntime || !contextRuntime || !outDeltaPos3 || !outDeltaRot4) {
        return 0;
    }
    if (!skeletonRuntime->skeleton || !animationRuntime->animation) {
        return 0;
    }

    const int32_t jointCount = skeletonRuntime->jointCount;
    if (jointCount <= 0 ||
        translationJointIndex < 0 || translationJointIndex >= jointCount ||
        rotationJointIndex < 0 || rotationJointIndex >= jointCount) {
        return 0;
    }

    const int32_t soaTrackCount = skeletonRuntime->skeleton->num_soa_joints();
    contextRuntime->ensureCapacity(soaTrackCount, jointCount);

    if (!sampleModelTransformsAtTime(skeletonRuntime,
                                     animationRuntime,
                                     contextRuntime,
                                     previousTimeSeconds,
                                     jointCount,
                                     soaTrackCount)) {
        return 0;
    }

    const ozz::math::Float4x4 prevTranslationMatrix = contextRuntime->modelMatrices[static_cast<size_t>(translationJointIndex)];
    const ozz::math::Float4x4 prevRotationMatrix = contextRuntime->modelMatrices[static_cast<size_t>(rotationJointIndex)];

    if (!sampleModelTransformsAtTime(skeletonRuntime,
                                     animationRuntime,
                                     contextRuntime,
                                     currentTimeSeconds,
                                     jointCount,
                                     soaTrackCount)) {
        return 0;
    }

    const ozz::math::Float4x4 currTranslationMatrix = contextRuntime->modelMatrices[static_cast<size_t>(translationJointIndex)];
    const ozz::math::Float4x4 currRotationMatrix = contextRuntime->modelMatrices[static_cast<size_t>(rotationJointIndex)];

    float prevTranslation[4] = {};
    float currTranslation[4] = {};
    ozz::math::StorePtrU(prevTranslationMatrix.cols[3], prevTranslation);
    ozz::math::StorePtrU(currTranslationMatrix.cols[3], currTranslation);

    ozz::math::SimdFloat4 prevRotationSimd;
    ozz::math::SimdFloat4 currRotationSimd;
    ozz::math::SimdFloat4 unusedTranslation;
    ozz::math::SimdFloat4 unusedScale;
    if (!ozz::math::ToAffine(prevRotationMatrix, &unusedTranslation, &prevRotationSimd, &unusedScale) ||
        !ozz::math::ToAffine(currRotationMatrix, &unusedTranslation, &currRotationSimd, &unusedScale)) {
        return 0;
    }

    float prevRotation[4] = {};
    float currRotation[4] = {};
    ozz::math::StorePtrU(prevRotationSimd, prevRotation);
    ozz::math::StorePtrU(currRotationSimd, currRotation);

    const QuaternionValue prevQ = normalizeQuaternion({prevRotation[0], prevRotation[1], prevRotation[2], prevRotation[3]});
    const QuaternionValue currQ = normalizeQuaternion({currRotation[0], currRotation[1], currRotation[2], currRotation[3]});
    const QuaternionValue invPrevQ = conjugateQuaternion(prevQ);

    const Float3Value worldDelta = {
        currTranslation[0] - prevTranslation[0],
        currTranslation[1] - prevTranslation[1],
        currTranslation[2] - prevTranslation[2]
    };
    const Float3Value localDelta = rotateVector(invPrevQ, worldDelta);

    const QuaternionValue deltaQ = normalizeQuaternion(multiplyQuaternion(invPrevQ, currQ));

    outDeltaPos3[0] = std::isfinite(localDelta.x) ? localDelta.x : 0.0f;
    outDeltaPos3[1] = std::isfinite(localDelta.y) ? localDelta.y : 0.0f;
    outDeltaPos3[2] = std::isfinite(localDelta.z) ? localDelta.z : 0.0f;

    outDeltaRot4[0] = std::isfinite(deltaQ.x) ? deltaQ.x : 0.0f;
    outDeltaRot4[1] = std::isfinite(deltaQ.y) ? deltaQ.y : 0.0f;
    outDeltaRot4[2] = std::isfinite(deltaQ.z) ? deltaQ.z : 0.0f;
    outDeltaRot4[3] = std::isfinite(deltaQ.w) ? deltaQ.w : 1.0f;
    return 1;
}

uint32_t MCEOzzBlendRootMotionDeltas(const LocalTransformC* deltas,
                                     int32_t deltaCount,
                                     const float* weights,
                                     int32_t weightCount,
                                     LocalTransformC* outDelta) {
    if (!deltas || !weights || !outDelta || deltaCount <= 0 || weightCount < deltaCount) {
        return 0;
    }

    std::vector<ozz::math::SoaTransform> layerTransforms(static_cast<size_t>(deltaCount));
    std::vector<BlendingJob::Layer> layers(static_cast<size_t>(deltaCount));

    for (int32_t i = 0; i < deltaCount; ++i) {
        layerTransforms[static_cast<size_t>(i)] = makeSoaTransform(deltas + i, 1, 0);
        layers[static_cast<size_t>(i)].weight = std::max(weights[i], 0.0f);
        layers[static_cast<size_t>(i)].transform = ozz::span<const ozz::math::SoaTransform>(&layerTransforms[static_cast<size_t>(i)], 1);
    }

    std::vector<ozz::math::SoaTransform> output(1);
    ozz::math::SoaTransform restPose = makeSoaTransform(deltas, 1, 0);
    restPose.translation = ozz::math::SoaFloat3::zero();
    restPose.rotation = ozz::math::SoaQuaternion::identity();
    restPose.scale = ozz::math::SoaFloat3::one();

    BlendingJob job;
    job.threshold = 0.1f;
    job.layers = ozz::span<const BlendingJob::Layer>(layers.data(), layers.size());
    job.rest_pose = ozz::span<const ozz::math::SoaTransform>(&restPose, 1);
    job.output = ozz::span<ozz::math::SoaTransform>(output.data(), output.size());

    if (!job.Run()) {
        return 0;
    }

    storeSoaLane(output[0], 0, outDelta);
    outDelta->sx = 1.0f;
    outDelta->sy = 1.0f;
    outDelta->sz = 1.0f;
    return 1;
}

uint32_t MCEOzzBlendLocalPoses(void* skeletonRuntimePtr,
                               void* blendingContextPtr,
                               const LocalTransformC* localTransforms,
                               int32_t transformsPerPose,
                               int32_t poseCount,
                               const float* layerWeights,
                               int32_t layerWeightCount,
                               LocalTransformC* outTransforms,
                               int32_t outTransformCount) {
    auto* skeletonRuntime = static_cast<OzzSkeletonRuntime*>(skeletonRuntimePtr);
    auto* contextRuntime = static_cast<OzzBlendingContextRuntime*>(blendingContextPtr);

    if (!skeletonRuntime || !contextRuntime || !skeletonRuntime->skeleton || !localTransforms ||
        !layerWeights || !outTransforms || transformsPerPose <= 0 || poseCount <= 0 ||
        layerWeightCount < poseCount || outTransformCount <= 0) {
        return 0;
    }

    const int32_t jointCount = skeletonRuntime->jointCount;
    if (jointCount <= 0 || transformsPerPose < jointCount || outTransformCount < jointCount) {
        return 0;
    }

    const int32_t soaTrackCount = skeletonRuntime->skeleton->num_soa_joints();
    contextRuntime->ensureCapacity(soaTrackCount, poseCount);

    for (int32_t poseIndex = 0; poseIndex < poseCount; ++poseIndex) {
        const LocalTransformC* poseBase = localTransforms + (poseIndex * transformsPerPose);
        auto& layerTransforms = contextRuntime->layerTransforms[static_cast<size_t>(poseIndex)];
        for (int32_t soaIndex = 0; soaIndex < soaTrackCount; ++soaIndex) {
            layerTransforms[static_cast<size_t>(soaIndex)] = makeSoaTransform(poseBase,
                                                                              transformsPerPose,
                                                                              soaIndex * 4);
        }

        auto& layer = contextRuntime->layers[static_cast<size_t>(poseIndex)];
        layer.weight = std::max(layerWeights[poseIndex], 0.0f);
        layer.transform = ozz::make_span(layerTransforms);
        layer.joint_weights = {};
    }

    BlendingJob job;
    job.threshold = 0.1f;
    job.layers = ozz::span<const BlendingJob::Layer>(contextRuntime->layers.data(),
                                                     static_cast<size_t>(poseCount));
    job.rest_pose = skeletonRuntime->skeleton->joint_rest_poses();
    job.output = ozz::make_span(contextRuntime->outputSoaTransforms);

    if (!job.Run()) {
        return 0;
    }

    int32_t written = 0;
    for (size_t soaIndex = 0; soaIndex < contextRuntime->outputSoaTransforms.size() && written < jointCount; ++soaIndex) {
        const auto& soaTransform = contextRuntime->outputSoaTransforms[soaIndex];
        for (int lane = 0; lane < 4 && written < jointCount; ++lane) {
            storeSoaLane(soaTransform, lane, &outTransforms[written]);
            ++written;
        }
    }

    return static_cast<uint32_t>(written == jointCount ? 1 : 0);
}

uint32_t MCEOzzLocalToModel(void* skeletonRuntimePtr,
                            void* localToModelContextPtr,
                            const LocalTransformC* localTransforms,
                            int32_t localTransformCount,
                            ModelMatrixC* outModelMatrices,
                            int32_t outModelMatrixCount) {
    auto* skeletonRuntime = static_cast<OzzSkeletonRuntime*>(skeletonRuntimePtr);
    auto* contextRuntime = static_cast<OzzLocalToModelContextRuntime*>(localToModelContextPtr);

    if (!skeletonRuntime || !contextRuntime || !localTransforms || !outModelMatrices ||
        localTransformCount <= 0 || outModelMatrixCount <= 0) {
        return 0;
    }
    if (!skeletonRuntime->skeleton) {
        return 0;
    }

    const int32_t jointCount = skeletonRuntime->jointCount;
    if (jointCount <= 0 || localTransformCount < jointCount || outModelMatrixCount < jointCount) {
        return 0;
    }

    const int32_t soaTrackCount = skeletonRuntime->skeleton->num_soa_joints();
    contextRuntime->ensureCapacity(soaTrackCount, jointCount);

    for (int32_t soaIndex = 0; soaIndex < soaTrackCount; ++soaIndex) {
        contextRuntime->localSoaTransforms[static_cast<size_t>(soaIndex)] = makeSoaTransform(localTransforms,
                                                                                              localTransformCount,
                                                                                              soaIndex * 4);
    }

    LocalToModelJob job;
    job.skeleton = skeletonRuntime->skeleton.get();
    job.input = ozz::make_span(contextRuntime->localSoaTransforms);
    job.output = ozz::make_span(contextRuntime->modelMatrices);
    if (!job.Run()) {
        return 0;
    }

    for (int32_t jointIndex = 0; jointIndex < jointCount; ++jointIndex) {
        const auto& matrix = contextRuntime->modelMatrices[static_cast<size_t>(jointIndex)];
        storeModelMatrix(matrix, &outModelMatrices[jointIndex]);
    }

    return 1;
}

uint32_t MCEOzzSampleLocalPose(void* skeletonRuntimePtr,
                               void* animationRuntimePtr,
                               void* samplingContextPtr,
                               float timeSeconds,
                               LocalTransformC* outTransforms,
                               int32_t outTransformCount) {
    auto* skeletonRuntime = static_cast<OzzSkeletonRuntime*>(skeletonRuntimePtr);
    auto* animationRuntime = static_cast<OzzAnimationRuntime*>(animationRuntimePtr);
    auto* contextRuntime = static_cast<OzzSamplingContextRuntime*>(samplingContextPtr);

    if (!skeletonRuntime || !animationRuntime || !contextRuntime || !outTransforms || outTransformCount <= 0) {
        return 0;
    }
    if (!skeletonRuntime->skeleton || !animationRuntime->animation) {
        return 0;
    }

    const int32_t outputCount = std::min<int32_t>(outTransformCount, std::min<int32_t>(skeletonRuntime->jointCount, animationRuntime->jointCount));
    if (outputCount <= 0) {
        return 0;
    }

    std::vector<ozz::math::SoaTransform> sampledLocals(static_cast<size_t>(animationRuntime->animation->num_soa_tracks()));

    SamplingJob job;
    job.animation = animationRuntime->animation.get();
    job.context = &contextRuntime->context;
    job.ratio = normalizedRatio(timeSeconds, animationRuntime->duration);
    job.output = ozz::make_span(sampledLocals);

    if (!job.Run()) {
        return 0;
    }

    int32_t written = 0;
    for (size_t soaIndex = 0; soaIndex < sampledLocals.size() && written < outputCount; ++soaIndex) {
        const auto& soaTransform = sampledLocals[soaIndex];
        for (int lane = 0; lane < 4 && written < outputCount; ++lane) {
            storeSoaLane(soaTransform, lane, &outTransforms[written]);
            ++written;
        }
    }

    return static_cast<uint32_t>(written == outputCount ? 1 : 0);
}

}  // extern "C"
