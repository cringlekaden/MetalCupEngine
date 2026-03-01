// JoltBridge.mm
// Minimal Jolt physics bridge for MetalCupEngine.
// Created by Codex.

#import <Foundation/Foundation.h>

#ifndef JPH_USE_VK
#define JPH_USE_VK 1
#endif
#ifndef JPH_USE_MTL
#define JPH_USE_MTL 1
#endif
#ifndef JPH_USE_CPU_COMPUTE
#define JPH_USE_CPU_COMPUTE 1
#endif
#ifndef JPH_DEBUG_RENDERER
#define JPH_DEBUG_RENDERER 1
#endif
#ifndef JPH_PROFILE_ENABLED
#define JPH_PROFILE_ENABLED 1
#endif
#ifndef JPH_OBJECT_STREAM
#define JPH_OBJECT_STREAM 1
#endif

#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <sstream>
#include <mutex>
#include <unordered_map>
#include <vector>
#include <thread>

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

namespace {
    using namespace JPH;

    static constexpr uint32_t kMaxCollisionLayers = 16;

    class BroadPhaseLayerInterfaceImpl final : public BroadPhaseLayerInterface {
    public:
        explicit BroadPhaseLayerInterfaceImpl(uint32_t layerCount) {
            mLayerCount = std::max(1u, std::min(layerCount, kMaxCollisionLayers));
            for (uint32_t i = 0; i < mLayerCount; ++i) {
                mLayers[i] = BroadPhaseLayer(i);
            }
        }

        uint GetNumBroadPhaseLayers() const override {
            return mLayerCount;
        }

        BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
            if (inLayer >= mLayerCount) {
                return BroadPhaseLayer(0);
            }
            return mLayers[inLayer];
        }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
        const char *GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
            (void)inLayer;
            return "PHYS_LAYER";
        }
#endif

    private:
        uint32_t mLayerCount = 1;
        BroadPhaseLayer mLayers[kMaxCollisionLayers];
    };

    class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
    public:
        explicit ObjectVsBroadPhaseLayerFilterImpl(const uint32_t *matrixRows, uint32_t layerCount)
        : mMatrixRows(matrixRows)
        , mLayerCount(std::max(1u, std::min(layerCount, kMaxCollisionLayers))) {}

        bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
            if (inLayer1 >= mLayerCount) { return false; }
            const uint32_t broadPhaseLayer = inLayer2.GetValue();
            if (broadPhaseLayer >= mLayerCount) { return false; }
            const uint32_t row = mMatrixRows[inLayer1];
            return (row & (1u << broadPhaseLayer)) != 0;
        }

    private:
        const uint32_t *mMatrixRows = nullptr;
        uint32_t mLayerCount = 1;
    };

    class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
    public:
        explicit ObjectLayerPairFilterImpl(const uint32_t *matrixRows, uint32_t layerCount)
        : mMatrixRows(matrixRows)
        , mLayerCount(std::max(1u, std::min(layerCount, kMaxCollisionLayers))) {}

        bool ShouldCollide(ObjectLayer inObject1, ObjectLayer inObject2) const override {
            if (inObject1 >= mLayerCount || inObject2 >= mLayerCount) { return false; }
            const uint32_t row1 = mMatrixRows[inObject1];
            const uint32_t row2 = mMatrixRows[inObject2];
            const uint32_t mask1 = 1u << inObject2;
            const uint32_t mask2 = 1u << inObject1;
            return (row1 & mask1) != 0 && (row2 & mask2) != 0;
        }

    private:
        const uint32_t *mMatrixRows = nullptr;
        uint32_t mLayerCount = 1;
    };

    struct ContactSample {
        float px;
        float py;
        float pz;
        float nx;
        float ny;
        float nz;
        uint64_t bodyId;
    };

    static constexpr uint32_t kMaxContactsPerStep = 256;
    static constexpr uint32_t kMaxOverlapEventsPerStep = 256;

    struct OverlapEvent {
        uint64_t bodyIdA;
        uint64_t bodyIdB;
        uint64_t userDataA;
        uint64_t userDataB;
        uint32_t isBegin;
    };

    class ContactCollector final : public ContactListener {
    public:
        explicit ContactCollector(ContactSample *samples,
                                  std::atomic<uint32_t> *writeIndex,
                                  OverlapEvent *overlapEvents,
                                  std::atomic<uint32_t> *overlapWriteIndex,
                                  std::atomic<uint32_t> *activeOverlapCount,
                                  std::unordered_map<uint64_t, OverlapEvent> *activeOverlaps,
                                  std::mutex *overlapMutex)
        : mSamples(samples)
        , mWriteIndex(writeIndex)
        , mOverlapEvents(overlapEvents)
        , mOverlapWriteIndex(overlapWriteIndex)
        , mActiveOverlapCount(activeOverlapCount)
        , mActiveOverlaps(activeOverlaps)
        , mOverlapMutex(overlapMutex) {}

        void OnContactAdded(const Body &inBody1,
                            const Body &inBody2,
                            const ContactManifold &inManifold,
                            ContactSettings &ioSettings) override {
            RecordContact(inBody1, inBody2, inManifold);
            RecordOverlap(inBody1, inBody2, true);
            (void)ioSettings;
        }

        void OnContactPersisted(const Body &inBody1,
                                const Body &inBody2,
                                const ContactManifold &inManifold,
                                ContactSettings &ioSettings) override {
            RecordContact(inBody1, inBody2, inManifold);
            (void)ioSettings;
        }

        void OnContactRemoved(const SubShapeIDPair &inSubShapePair) override {
            if (!mOverlapEvents || !mOverlapWriteIndex || !mActiveOverlaps || !mOverlapMutex) { return; }
            if (!mActiveOverlapCount || mActiveOverlapCount->load(std::memory_order_relaxed) == 0) { return; }
            const uint64_t bodyA = static_cast<uint64_t>(inSubShapePair.GetBody1ID().GetIndexAndSequenceNumber());
            const uint64_t bodyB = static_cast<uint64_t>(inSubShapePair.GetBody2ID().GetIndexAndSequenceNumber());
            const uint64_t key = MakePairKey(bodyA, bodyB);
            OverlapEvent cached {};
            {
                std::lock_guard<std::mutex> guard(*mOverlapMutex);
                auto it = mActiveOverlaps->find(key);
                if (it == mActiveOverlaps->end()) { return; }
                cached = it->second;
                mActiveOverlaps->erase(it);
                if (mActiveOverlapCount->load(std::memory_order_relaxed) > 0) {
                    mActiveOverlapCount->fetch_sub(1, std::memory_order_relaxed);
                }
            }
            const uint32_t writeIndex = mOverlapWriteIndex->fetch_add(1, std::memory_order_relaxed);
            const uint32_t index = writeIndex % kMaxOverlapEventsPerStep;
            OverlapEvent &event = mOverlapEvents[index];
            event.bodyIdA = cached.bodyIdA;
            event.bodyIdB = cached.bodyIdB;
            event.userDataA = cached.userDataA;
            event.userDataB = cached.userDataB;
            event.isBegin = 0;
        }

    private:
        static uint64_t MakePairKey(uint64_t a, uint64_t b) {
            if (a > b) { std::swap(a, b); }
            return (a << 32) | (b & 0xffffffffu);
        }
        void RecordContact(const Body &inBody1, const Body &inBody2, const ContactManifold &inManifold) {
            if (!mSamples || !mWriteIndex) { return; }
            if (inBody1.GetUserData() != 0 && inBody1.GetUserData() == inBody2.GetUserData()) { return; }
            const uint32_t writeIndex = mWriteIndex->fetch_add(1, std::memory_order_relaxed);
            const uint32_t index = writeIndex % kMaxContactsPerStep;

            const bool isTrigger = inBody1.IsSensor() || inBody2.IsSensor();
            const Body *body = &inBody1;
            if (isTrigger) {
                body = inBody1.IsSensor() ? &inBody1 : &inBody2;
            } else if (inBody1.GetMotionType() == EMotionType::Dynamic) {
                body = &inBody1;
            } else if (inBody2.GetMotionType() == EMotionType::Dynamic) {
                body = &inBody2;
            }

            const RVec3 contactPoint = inManifold.GetWorldSpaceContactPointOn1(0);
            const Vec3 normal = inManifold.mWorldSpaceNormal;
            ContactSample &sample = mSamples[index];
            sample.px = static_cast<float>(contactPoint.GetX());
            sample.py = static_cast<float>(contactPoint.GetY());
            sample.pz = static_cast<float>(contactPoint.GetZ());
            sample.nx = normal.GetX();
            sample.ny = normal.GetY();
            sample.nz = normal.GetZ();
            sample.bodyId = static_cast<uint64_t>(body->GetID().GetIndexAndSequenceNumber());
        }

        void RecordOverlap(const Body &inBody1, const Body &inBody2, bool isBegin) {
            if (!mOverlapEvents || !mOverlapWriteIndex || !mActiveOverlaps || !mOverlapMutex || !mActiveOverlapCount) { return; }
            if (!inBody1.IsSensor() && !inBody2.IsSensor()) { return; }
            if (inBody1.GetUserData() != 0 && inBody1.GetUserData() == inBody2.GetUserData()) { return; }
            const uint64_t bodyA = static_cast<uint64_t>(inBody1.GetID().GetIndexAndSequenceNumber());
            const uint64_t bodyB = static_cast<uint64_t>(inBody2.GetID().GetIndexAndSequenceNumber());
            const uint64_t key = MakePairKey(bodyA, bodyB);
            const uint32_t writeIndex = mOverlapWriteIndex->fetch_add(1, std::memory_order_relaxed);
            const uint32_t index = writeIndex % kMaxOverlapEventsPerStep;
            OverlapEvent &event = mOverlapEvents[index];
            event.bodyIdA = bodyA;
            event.bodyIdB = bodyB;
            event.userDataA = inBody1.GetUserData();
            event.userDataB = inBody2.GetUserData();
            event.isBegin = isBegin ? 1 : 0;
            if (isBegin) {
                std::lock_guard<std::mutex> guard(*mOverlapMutex);
                auto insertResult = mActiveOverlaps->emplace(key, event);
                if (!insertResult.second) {
                    insertResult.first->second = event;
                } else {
                    mActiveOverlapCount->fetch_add(1, std::memory_order_relaxed);
                }
            }
        }

        ContactSample *mSamples = nullptr;
        std::atomic<uint32_t> *mWriteIndex = nullptr;
        OverlapEvent *mOverlapEvents = nullptr;
        std::atomic<uint32_t> *mOverlapWriteIndex = nullptr;
        std::atomic<uint32_t> *mActiveOverlapCount = nullptr;
        std::unordered_map<uint64_t, OverlapEvent> *mActiveOverlaps = nullptr;
        std::mutex *mOverlapMutex = nullptr;
    };

    struct JoltWorld {
        uint32_t layerCount;
        std::array<uint32_t, kMaxCollisionLayers> collisionMatrix;
        PhysicsSystem physicsSystem;
        TempAllocatorImpl tempAllocator;
        JobSystemThreadPool jobSystem;
        JobSystemSingleThreaded jobSystemSingleThreaded;
        BroadPhaseLayerInterfaceImpl broadPhase;
        ObjectVsBroadPhaseLayerFilterImpl objectVsBroadPhaseLayerFilter;
        ObjectLayerPairFilterImpl objectLayerPairFilter;
        ContactSample contacts[kMaxContactsPerStep];
        std::atomic<uint32_t> contactWriteIndex;
        OverlapEvent overlapEvents[kMaxOverlapEventsPerStep];
        std::atomic<uint32_t> overlapWriteIndex;
        std::atomic<uint32_t> activeOverlapCount;
        std::unordered_map<uint64_t, OverlapEvent> activeOverlaps;
        std::mutex overlapMutex;
        ContactCollector contactCollector;
        bool useSingleThreaded;

        JoltWorld(uint32_t tempAllocatorBytes,
                  uint32_t maxJobs,
                  uint32_t maxBarriers,
                  uint32_t numThreads,
                  uint32_t collisionLayerCount,
                  const uint32_t *collisionMatrixRows,
                  bool singleThreaded)
        : layerCount(std::max(1u, std::min(collisionLayerCount, kMaxCollisionLayers)))
        , collisionMatrix{}
        , tempAllocator(tempAllocatorBytes)
        , jobSystem()
        , jobSystemSingleThreaded()
        , broadPhase(layerCount)
        , objectVsBroadPhaseLayerFilter(collisionMatrix.data(), layerCount)
        , objectLayerPairFilter(collisionMatrix.data(), layerCount)
        , contactWriteIndex(0)
        , overlapWriteIndex(0)
        , activeOverlapCount(0)
        , contactCollector(contacts, &contactWriteIndex, overlapEvents, &overlapWriteIndex, &activeOverlapCount, &activeOverlaps, &overlapMutex)
        , useSingleThreaded(singleThreaded) {
            const uint32_t fullMask = layerCount >= 32 ? 0xffffffffu : ((1u << layerCount) - 1u);
            for (uint32_t row = 0; row < layerCount; ++row) {
                const uint32_t source = collisionMatrixRows ? collisionMatrixRows[row] : fullMask;
                collisionMatrix[row] = source & fullMask;
            }
            for (uint32_t row = layerCount; row < kMaxCollisionLayers; ++row) {
                collisionMatrix[row] = 0;
            }
            if (useSingleThreaded) {
                jobSystemSingleThreaded.Init(maxJobs);
            } else {
                jobSystem.Init(maxJobs, maxBarriers, static_cast<int>(numThreads));
            }
        }
    };

    std::once_flag gInitOnce;

    void JoltInitializeOnce() {
        std::call_once(gInitOnce, []() {
            JPH::RegisterDefaultAllocator();
            JPH::Factory::sInstance = new JPH::Factory();
            JPH::RegisterTypes();
        });
    }

    void EnsureJoltInitialized() {
        JoltInitializeOnce();
    }

    static float ClampPositive(float value, float fallback) {
        if (value > 0.0001f) { return value; }
        return fallback;
    }

    static bool IsIdentityQuat(float x, float y, float z, float w) {
        return fabsf(x) < 0.0001f && fabsf(y) < 0.0001f && fabsf(z) < 0.0001f && fabsf(w - 1.0f) < 0.0001f;
    }

    static RefConst<Shape> BuildShape(uint32_t shapeType,
                                     float boxHX, float boxHY, float boxHZ,
                                     float sphereRadius,
                                     float capsuleHalfHeight,
                                     float capsuleRadius,
                                     float offsetX, float offsetY, float offsetZ,
                                     float rotX, float rotY, float rotZ, float rotW) {
        JoltInitializeOnce();
#if DEBUG
        if (JPH::Factory::sInstance == nullptr) {
            fprintf(stderr, "Jolt Factory initialization failed before shape creation.\n");
            JPH_ASSERT(false);
        }
#endif
        RefConst<Shape> baseShape;
        switch (shapeType) {
            case 0: {
                const float hx = ClampPositive(boxHX, 0.5f);
                const float hy = ClampPositive(boxHY, 0.5f);
                const float hz = ClampPositive(boxHZ, 0.5f);
                BoxShapeSettings settings(Vec3(hx, hy, hz));
                baseShape = settings.Create().Get();
            } break;
            case 1: {
                const float radius = ClampPositive(sphereRadius, 0.5f);
                SphereShapeSettings settings(radius);
                baseShape = settings.Create().Get();
            } break;
            case 2: {
                const float radius = ClampPositive(capsuleRadius, 0.5f);
                const float halfHeight = ClampPositive(capsuleHalfHeight, 0.5f);
                CapsuleShapeSettings settings(halfHeight, radius);
                baseShape = settings.Create().Get();
            } break;
            default: {
                BoxShapeSettings settings(Vec3(0.5f, 0.5f, 0.5f));
                baseShape = settings.Create().Get();
            } break;
        }

        const bool hasOffset = fabsf(offsetX) > 0.0001f || fabsf(offsetY) > 0.0001f || fabsf(offsetZ) > 0.0001f;
        const bool hasRotation = !IsIdentityQuat(rotX, rotY, rotZ, rotW);
        if (!hasOffset && !hasRotation) {
            return baseShape;
        }

        Quat rotation(rotX, rotY, rotZ, rotW);
        Vec3 offset(offsetX, offsetY, offsetZ);
        RotatedTranslatedShapeSettings settings(offset, rotation, baseShape);
        return settings.Create().Get();
    }

    static RefConst<Shape> BuildCompoundShape(uint32_t shapeCount,
                                              const uint32_t *shapeTypes,
                                              const float *boxHalfExtents,
                                              const float *sphereRadii,
                                              const float *capsuleHalfHeights,
                                              const float *capsuleRadii,
                                              const float *offsets,
                                              const float *rotationOffsets) {
        if (shapeCount == 0 || !shapeTypes || !boxHalfExtents || !sphereRadii || !capsuleHalfHeights || !capsuleRadii || !offsets || !rotationOffsets) {
            return nullptr;
        }
        if (shapeCount == 1) {
            return BuildShape(shapeTypes[0],
                              boxHalfExtents[0], boxHalfExtents[1], boxHalfExtents[2],
                              sphereRadii[0],
                              capsuleHalfHeights[0],
                              capsuleRadii[0],
                              offsets[0], offsets[1], offsets[2],
                              rotationOffsets[0], rotationOffsets[1], rotationOffsets[2], rotationOffsets[3]);
        }

        StaticCompoundShapeSettings compound;
        for (uint32_t i = 0; i < shapeCount; ++i) {
            const uint32_t boxBase = i * 3;
            const uint32_t rotBase = i * 4;
            const RefConst<Shape> shape = BuildShape(shapeTypes[i],
                                                     boxHalfExtents[boxBase + 0], boxHalfExtents[boxBase + 1], boxHalfExtents[boxBase + 2],
                                                     sphereRadii[i],
                                                     capsuleHalfHeights[i],
                                                     capsuleRadii[i],
                                                     offsets[boxBase + 0], offsets[boxBase + 1], offsets[boxBase + 2],
                                                     rotationOffsets[rotBase + 0], rotationOffsets[rotBase + 1], rotationOffsets[rotBase + 2], rotationOffsets[rotBase + 3]);
            if (!shape) { continue; }
            compound.AddShape(Vec3::sZero(), Quat::sIdentity(), shape);
        }
        return compound.Create().Get();
    }

    static EMotionType MotionTypeFromUInt(uint32_t value) {
        switch (value) {
            case 2:
                return EMotionType::Kinematic;
            case 1:
                return EMotionType::Dynamic;
            case 0:
            default:
                return EMotionType::Static;
        }
    }

    static ObjectLayer ObjectLayerFromCollisionLayer(uint32_t collisionLayer, uint32_t layerCount) {
        if (layerCount == 0) { return 0; }
        return static_cast<ObjectLayer>(std::min(collisionLayer, layerCount - 1));
    }
}

extern "C" void *MCEPhysicsCreateWorld(float gravityX,
                                       float gravityY,
                                       float gravityZ,
                                       uint32_t maxBodies,
                                       uint32_t maxBodyPairs,
                                       uint32_t maxContactConstraints,
                                       uint32_t singleThreaded,
                                       uint32_t collisionLayerCount,
                                       const uint32_t *collisionMatrixRows) {
    EnsureJoltInitialized();

    const uint32_t bodies = maxBodies > 0 ? maxBodies : 1024;
    const uint32_t bodyPairs = maxBodyPairs > 0 ? maxBodyPairs : 1024;
    const uint32_t constraints = maxContactConstraints > 0 ? maxContactConstraints : 1024;
    const uint32_t numMutexes = 0;

    const uint32_t tempAllocatorBytes = 10 * 1024 * 1024;
    const uint32_t maxJobs = 1024;
    const uint32_t maxBarriers = 128;
    const uint32_t hardwareThreads = std::max(1u, std::thread::hardware_concurrency());
    const uint32_t workerThreads = hardwareThreads > 1 ? hardwareThreads - 1 : 1;
    const bool useSingleThreaded = singleThreaded != 0;

    JoltWorld *world = new JoltWorld(tempAllocatorBytes,
                                     maxJobs,
                                     maxBarriers,
                                     workerThreads,
                                     collisionLayerCount,
                                     collisionMatrixRows,
                                     useSingleThreaded);
    world->physicsSystem.Init(bodies,
                              numMutexes,
                              bodyPairs,
                              constraints,
                              world->broadPhase,
                              world->objectVsBroadPhaseLayerFilter,
                              world->objectLayerPairFilter);
    world->physicsSystem.SetGravity(Vec3(gravityX, gravityY, gravityZ));
    world->physicsSystem.SetContactListener(&world->contactCollector);
    return world;
}

extern "C" void MCEPhysicsDestroyWorld(void *worldPtr) {
    if (!worldPtr) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    delete world;
}

extern "C" void MCEPhysicsWorldSetGravity(void *worldPtr, float gravityX, float gravityY, float gravityZ) {
    if (!worldPtr) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    world->physicsSystem.SetGravity(Vec3(gravityX, gravityY, gravityZ));
}

extern "C" void MCEPhysicsStepWorld(void *worldPtr, float dt, uint32_t collisionSteps) {
    if (!worldPtr) { return; }
    if (dt <= 0.0f) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    const uint32_t steps = std::max(1u, collisionSteps);
    world->contactWriteIndex.store(0, std::memory_order_relaxed);
    world->overlapWriteIndex.store(0, std::memory_order_relaxed);
    JobSystem *jobSystem = world->useSingleThreaded
        ? static_cast<JobSystem *>(&world->jobSystemSingleThreaded)
        : static_cast<JobSystem *>(&world->jobSystem);
    world->physicsSystem.Update(dt, steps, &world->tempAllocator, jobSystem);
}

extern "C" uint64_t MCEPhysicsCreateBodyMulti(void *worldPtr,
                                         uint32_t shapeCount,
                                         const uint32_t *shapeTypes,
                                         const float *boxHalfExtents,
                                         const float *sphereRadii,
                                         const float *capsuleHalfHeights,
                                         const float *capsuleRadii,
                                         const float *offsets,
                                         const float *rotationOffsets,
                                         uint32_t motionType,
                                         float posX, float posY, float posZ,
                                         float rotX, float rotY, float rotZ, float rotW,
                                         float friction,
                                         float restitution,
                                         float linearDamping,
                                         float angularDamping,
                                         float gravityFactor,
                                         float mass,
                                         uint64_t userData,
                                         uint32_t ccdEnabled,
                                         uint32_t isSensor,
                                         uint32_t allowSleeping,
                                         uint32_t collisionLayer) {
    if (!worldPtr) { return 0; }
    JoltInitializeOnce();
#if DEBUG
    if (JPH::Factory::sInstance == nullptr) {
        fprintf(stderr, "Jolt Factory initialization failed before body creation.\n");
        JPH_ASSERT(false);
    }
#endif
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);

    RefConst<Shape> shape = BuildCompoundShape(shapeCount,
                                               shapeTypes,
                                               boxHalfExtents,
                                               sphereRadii,
                                               capsuleHalfHeights,
                                               capsuleRadii,
                                               offsets,
                                               rotationOffsets);
    if (!shape) { return 0; }

    const EMotionType joltMotion = MotionTypeFromUInt(motionType);
    const ObjectLayer layer = ObjectLayerFromCollisionLayer(collisionLayer, world->layerCount);

    BodyCreationSettings settings(shape,
                                  RVec3(posX, posY, posZ),
                                  Quat(rotX, rotY, rotZ, rotW),
                                  joltMotion,
                                  layer);
    settings.mFriction = friction;
    settings.mRestitution = restitution;
    settings.mLinearDamping = linearDamping;
    settings.mAngularDamping = angularDamping;
    settings.mGravityFactor = gravityFactor;
    settings.mIsSensor = isSensor != 0;
    settings.mAllowSleeping = allowSleeping != 0;
    settings.mUserData = userData;
    if (ccdEnabled != 0 && joltMotion == EMotionType::Dynamic) {
        settings.mMotionQuality = EMotionQuality::LinearCast;
    }

    if (joltMotion == EMotionType::Dynamic) {
        const float resolvedMass = ClampPositive(mass, 1.0f);
        settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
        settings.mMassPropertiesOverride.mMass = resolvedMass;
    }

    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    Body *body = bodyInterface.CreateBody(settings);
    if (!body) { return 0; }
    const BodyID bodyId = body->GetID();
    const EActivation activation = (joltMotion == EMotionType::Static) ? EActivation::DontActivate : EActivation::Activate;
    bodyInterface.AddBody(bodyId, activation);
    return static_cast<uint64_t>(bodyId.GetIndexAndSequenceNumber());
}

extern "C" void MCEPhysicsDestroyBody(void *worldPtr, uint64_t bodyIdValue) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    bodyInterface.RemoveBody(bodyId);
    bodyInterface.DestroyBody(bodyId);
}

extern "C" void MCEPhysicsSetBodyTransform(void *worldPtr,
                                           uint64_t bodyIdValue,
                                           float posX, float posY, float posZ,
                                           float rotX, float rotY, float rotZ, float rotW,
                                           uint32_t activate) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    bodyInterface.SetPositionAndRotation(bodyId,
                                         RVec3(posX, posY, posZ),
                                         Quat(rotX, rotY, rotZ, rotW),
                                         activate != 0 ? EActivation::Activate : EActivation::DontActivate);
}

extern "C" uint32_t MCEPhysicsGetBodyTransform(void *worldPtr,
                                               uint64_t bodyIdValue,
                                               float *posOut,
                                               float *rotOut) {
    if (!worldPtr || bodyIdValue == 0 || !posOut || !rotOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return 0; }
    RVec3 position;
    Quat rotation;
    bodyInterface.GetPositionAndRotation(bodyId, position, rotation);
    posOut[0] = static_cast<float>(position.GetX());
    posOut[1] = static_cast<float>(position.GetY());
    posOut[2] = static_cast<float>(position.GetZ());
    rotOut[0] = rotation.GetX();
    rotOut[1] = rotation.GetY();
    rotOut[2] = rotation.GetZ();
    rotOut[3] = rotation.GetW();
    return 1;
}

extern "C" void MCEPhysicsSetBodyMotionType(void *worldPtr, uint64_t bodyIdValue, uint32_t motionType) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    bodyInterface.SetMotionType(bodyId, MotionTypeFromUInt(motionType), EActivation::Activate);
}

extern "C" void MCEPhysicsSetBodyLinearAndAngularVelocity(void *worldPtr,
                                                           uint64_t bodyIdValue,
                                                           float linearX, float linearY, float linearZ,
                                                           float angularX, float angularY, float angularZ) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    bodyInterface.SetLinearAndAngularVelocity(bodyId, Vec3(linearX, linearY, linearZ), Vec3(angularX, angularY, angularZ));
}

extern "C" uint32_t MCEPhysicsGetBodyLinearAndAngularVelocity(void *worldPtr,
                                                               uint64_t bodyIdValue,
                                                               float *linearOut,
                                                               float *angularOut) {
    if (!worldPtr || bodyIdValue == 0 || !linearOut || !angularOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyLockRead lock(world->physicsSystem.GetBodyLockInterface(), BodyID(bodyIdValue));
    if (!lock.Succeeded()) { return 0; }
    const Body &body = lock.GetBody();
    const Vec3 linear = body.GetLinearVelocity();
    const Vec3 angular = body.GetAngularVelocity();
    linearOut[0] = linear.GetX();
    linearOut[1] = linear.GetY();
    linearOut[2] = linear.GetZ();
    angularOut[0] = angular.GetX();
    angularOut[1] = angular.GetY();
    angularOut[2] = angular.GetZ();
    return 1;
}

extern "C" void MCEPhysicsSetBodyActivation(void *worldPtr, uint64_t bodyIdValue, uint32_t activate) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    if (activate != 0) {
        bodyInterface.ActivateBody(bodyId);
    } else {
        bodyInterface.DeactivateBody(bodyId);
    }
}

extern "C" uint32_t MCEPhysicsCopyLastContacts(void *worldPtr, float *buffer, uint32_t maxContacts) {
    if (!worldPtr || !buffer || maxContacts == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    const uint32_t available = world->contactWriteIndex.load(std::memory_order_relaxed);
    const uint32_t count = std::min(std::min(available, maxContacts), kMaxContactsPerStep);
    const uint32_t start = available > count ? (available - count) : 0;
    for (uint32_t i = 0; i < count; ++i) {
        const uint32_t index = (start + i) % kMaxContactsPerStep;
        const ContactSample &sample = world->contacts[index];
        const uint32_t base = i * 6;
        buffer[base + 0] = sample.px;
        buffer[base + 1] = sample.py;
        buffer[base + 2] = sample.pz;
        buffer[base + 3] = sample.nx;
        buffer[base + 4] = sample.ny;
        buffer[base + 5] = sample.nz;
    }
    return count;
}

extern "C" uint32_t MCEPhysicsCopyLastContactBodyIds(void *worldPtr, uint64_t *buffer, uint32_t maxContacts) {
    if (!worldPtr || !buffer || maxContacts == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    const uint32_t available = world->contactWriteIndex.load(std::memory_order_relaxed);
    const uint32_t count = std::min(std::min(available, maxContacts), kMaxContactsPerStep);
    const uint32_t start = available > count ? (available - count) : 0;
    for (uint32_t i = 0; i < count; ++i) {
        const uint32_t index = (start + i) % kMaxContactsPerStep;
        buffer[i] = world->contacts[index].bodyId;
    }
    return count;
}

extern "C" void MCEPhysicsClearLastContacts(void *worldPtr) {
    if (!worldPtr) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    world->contactWriteIndex.store(0, std::memory_order_relaxed);
}

extern "C" uint32_t MCEPhysicsIsBodySleeping(void *worldPtr, uint64_t bodyIdValue) {
    if (!worldPtr || bodyIdValue == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return 0; }
    return bodyInterface.IsActive(bodyId) ? 0 : 1;
}

extern "C" uint32_t MCEPhysicsRaycastClosest(void *worldPtr,
                                             float originX, float originY, float originZ,
                                             float dirX, float dirY, float dirZ,
                                             float maxDistance,
                                             float *positionOut,
                                             float *normalOut,
                                             float *distanceOut,
                                             uint64_t *bodyIdOut,
                                             uint64_t *userDataOut) {
    if (!worldPtr || !positionOut || !normalOut || !distanceOut || !bodyIdOut || !userDataOut) { return 0; }
    if (maxDistance <= 0.0f) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    Vec3 dir(dirX, dirY, dirZ);
    if (dir.LengthSq() < 1.0e-8f) { return 0; }
    dir = dir.Normalized();
    RRayCast ray(RVec3(originX, originY, originZ), dir * maxDistance);
    RayCastResult hit;
    if (!world->physicsSystem.GetNarrowPhaseQuery().CastRay(ray, hit)) {
        return 0;
    }
    BodyLockRead lock(world->physicsSystem.GetBodyLockInterface(), hit.mBodyID);
    if (!lock.Succeeded()) { return 0; }
    const Body &body = lock.GetBody();
    const RVec3 hitPosition = ray.GetPointOnRay(hit.mFraction);
    const Vec3 normal = body.GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, hitPosition);
    positionOut[0] = static_cast<float>(hitPosition.GetX());
    positionOut[1] = static_cast<float>(hitPosition.GetY());
    positionOut[2] = static_cast<float>(hitPosition.GetZ());
    normalOut[0] = normal.GetX();
    normalOut[1] = normal.GetY();
    normalOut[2] = normal.GetZ();
    *distanceOut = hit.mFraction * maxDistance;
    *bodyIdOut = static_cast<uint64_t>(hit.mBodyID.GetIndexAndSequenceNumber());
    *userDataOut = body.GetUserData();
    return 1;
}

extern "C" uint32_t MCEPhysicsSphereCastClosest(void *worldPtr,
                                                float originX, float originY, float originZ,
                                                float dirX, float dirY, float dirZ,
                                                float radius,
                                                float maxDistance,
                                                float *positionOut,
                                                float *normalOut,
                                                float *distanceOut,
                                                uint64_t *bodyIdOut,
                                                uint64_t *userDataOut) {
    if (!worldPtr || !positionOut || !normalOut || !distanceOut || !bodyIdOut || !userDataOut) { return 0; }
    if (maxDistance <= 0.0f || radius <= 0.0f) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    Vec3 dir(dirX, dirY, dirZ);
    if (dir.LengthSq() < 1.0e-8f) { return 0; }
    dir = dir.Normalized();
    SphereShapeSettings sphereSettings(radius);
    RefConst<Shape> shape = sphereSettings.Create().Get();
    if (!shape) { return 0; }
    RMat44 startTransform = RMat44::sTranslation(RVec3(originX, originY, originZ));
    RShapeCast shapeCast(shape, Vec3::sReplicate(1.0f), startTransform, dir * maxDistance);
    ShapeCastSettings castSettings;
    ClosestHitCollisionCollector<CastShapeCollector> collector;
    world->physicsSystem.GetNarrowPhaseQuery().CastShape(shapeCast, castSettings, RVec3::sZero(), collector);
    if (!collector.HadHit()) { return 0; }
    const ShapeCastResult &hit = collector.mHit;
    BodyLockRead lock(world->physicsSystem.GetBodyLockInterface(), hit.mBodyID2);
    if (!lock.Succeeded()) { return 0; }
    const Body &body = lock.GetBody();
    const RVec3 hitPosition = shapeCast.GetPointOnRay(hit.mFraction);
    const Vec3 normal = -hit.mPenetrationAxis.Normalized();
    positionOut[0] = static_cast<float>(hitPosition.GetX());
    positionOut[1] = static_cast<float>(hitPosition.GetY());
    positionOut[2] = static_cast<float>(hitPosition.GetZ());
    normalOut[0] = normal.GetX();
    normalOut[1] = normal.GetY();
    normalOut[2] = normal.GetZ();
    *distanceOut = hit.mFraction * maxDistance;
    *bodyIdOut = static_cast<uint64_t>(hit.mBodyID2.GetIndexAndSequenceNumber());
    *userDataOut = body.GetUserData();
    return 1;
}

extern "C" uint32_t MCEPhysicsCopyOverlapEvents(void *worldPtr,
                                                uint64_t *bodyAOut,
                                                uint64_t *bodyBOut,
                                                uint64_t *userDataAOut,
                                                uint64_t *userDataBOut,
                                                uint32_t *isBeginOut,
                                                uint32_t maxEvents) {
    if (!worldPtr || !bodyAOut || !bodyBOut || !userDataAOut || !userDataBOut || !isBeginOut || maxEvents == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    const uint32_t available = world->overlapWriteIndex.load(std::memory_order_relaxed);
    const uint32_t count = std::min(std::min(available, maxEvents), kMaxOverlapEventsPerStep);
    const uint32_t start = available > count ? (available - count) : 0;
    for (uint32_t i = 0; i < count; ++i) {
        const uint32_t index = (start + i) % kMaxOverlapEventsPerStep;
        const OverlapEvent &event = world->overlapEvents[index];
        bodyAOut[i] = event.bodyIdA;
        bodyBOut[i] = event.bodyIdB;
        userDataAOut[i] = event.userDataA;
        userDataBOut[i] = event.userDataB;
        isBeginOut[i] = event.isBegin;
    }
    return count;
}

namespace {
    using LuaLogCallback = void (*)(void *hostContext, int32_t level, const char *message);
    using LuaEntityExistsCallback = uint32_t (*)(void *hostContext, const char *entityId);
    using LuaEntityGetNameCallback = uint32_t (*)(void *hostContext, const char *entityId, char *buffer, int32_t bufferSize);
    using LuaEntityGetTransformCallback = uint32_t (*)(void *hostContext, const char *entityId, float *positionOut, float *rotationEulerOut, float *scaleOut);
    using LuaEntitySetTransformCallback = uint32_t (*)(void *hostContext, const char *entityId, const float *position, const float *rotationEuler, const float *scale);

    static constexpr int kEntityIdBufferSize = 64;

    struct LuaScriptHost;

    struct LuaScriptInstance {
        std::string scriptPath;
        int selfRef = LUA_NOREF;
        int onCreateRef = LUA_NOREF;
        int onStartRef = LUA_NOREF;
        int onUpdateRef = LUA_NOREF;
        int onFixedUpdateRef = LUA_NOREF;
        int onDestroyRef = LUA_NOREF;
        bool faulted = false;
        std::string lastError;
    };

    struct LuaScriptHost {
        void *hostContext = nullptr;
        LuaLogCallback logCallback = nullptr;
        LuaEntityExistsCallback entityExistsCallback = nullptr;
        LuaEntityGetNameCallback entityGetNameCallback = nullptr;
        LuaEntityGetTransformCallback entityGetTransformCallback = nullptr;
        LuaEntitySetTransformCallback entitySetTransformCallback = nullptr;
        lua_State *L = nullptr;
        std::unordered_map<std::string, LuaScriptInstance> instances;
    };

    static void WriteCString(const std::string &text, char *buffer, int32_t size) {
        if (!buffer || size <= 0) { return; }
        const int32_t maxCount = size - 1;
        const int32_t count = std::min<int32_t>(maxCount, static_cast<int32_t>(text.size()));
        if (count > 0) {
            memcpy(buffer, text.data(), static_cast<size_t>(count));
        }
        buffer[count] = 0;
    }

    static void UnrefIfValid(lua_State *L, int &ref) {
        if (!L || ref == LUA_NOREF) { return; }
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
        ref = LUA_NOREF;
    }

    static void ClearInstanceRefs(lua_State *L, LuaScriptInstance &instance) {
        UnrefIfValid(L, instance.selfRef);
        UnrefIfValid(L, instance.onCreateRef);
        UnrefIfValid(L, instance.onStartRef);
        UnrefIfValid(L, instance.onUpdateRef);
        UnrefIfValid(L, instance.onFixedUpdateRef);
        UnrefIfValid(L, instance.onDestroyRef);
    }

    static void LogMessage(LuaScriptHost *host, int32_t level, const std::string &text) {
        if (!host || !host->logCallback) { return; }
        host->logCallback(host->hostContext, level, text.c_str());
    }

    static void LogInfo(LuaScriptHost *host, const std::string &text) { LogMessage(host, 0, text); }
    static void LogWarning(LuaScriptHost *host, const std::string &text) { LogMessage(host, 1, text); }
    static void LogError(LuaScriptHost *host, const std::string &text) { LogMessage(host, 2, text); }

    static std::string FormatLuaError(const std::string &entityId,
                                      const std::string &scriptPath,
                                      const std::string &phase,
                                      const std::string &details) {
        std::ostringstream stream;
        stream << phase << " failed for entity " << entityId << " (" << scriptPath << "): " << details;
        return stream.str();
    }

    static bool ReadVec3FromLuaTable(lua_State *L, int index, float outVec[3], const float fallback[3]) {
        if (!lua_istable(L, index)) { return false; }
        outVec[0] = fallback[0];
        outVec[1] = fallback[1];
        outVec[2] = fallback[2];

        lua_rawgeti(L, index, 1);
        if (lua_isnumber(L, -1)) { outVec[0] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 2);
        if (lua_isnumber(L, -1)) { outVec[1] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 3);
        if (lua_isnumber(L, -1)) { outVec[2] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);

        // Prefer named fields over array slots so scripts that mutate p.x/p.y/p.z
        // are not overwritten by stale [1]/[2]/[3] values.
        lua_getfield(L, index, "x");
        if (lua_isnumber(L, -1)) { outVec[0] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, index, "y");
        if (lua_isnumber(L, -1)) { outVec[1] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, index, "z");
        if (lua_isnumber(L, -1)) { outVec[2] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        return true;
    }

    static void PushVec3Table(lua_State *L, const float vec[3]) {
        lua_createtable(L, 3, 3);
        lua_pushnumber(L, vec[0]); lua_setfield(L, -2, "x");
        lua_pushnumber(L, vec[1]); lua_setfield(L, -2, "y");
        lua_pushnumber(L, vec[2]); lua_setfield(L, -2, "z");
        lua_pushnumber(L, vec[0]); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, vec[1]); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, vec[2]); lua_rawseti(L, -2, 3);
    }

    static LuaScriptHost *BoundHostOrNil(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return nullptr; }
        if (!host->entityExistsCallback) { return nullptr; }
        const char *entityId = lua_tostring(L, lua_upvalueindex(2));
        if (!entityId || host->entityExistsCallback(host->hostContext, entityId) == 0) {
            if (entityId) {
                LogWarning(host, std::string("Lua entity binding lost target entity: ") + entityId);
            } else {
                LogWarning(host, "Lua entity binding missing entity id.");
            }
            return nullptr;
        }
        return host;
    }

    static const char *BoundEntityId(lua_State *L) {
        const char *entityId = lua_tostring(L, lua_upvalueindex(2));
        return entityId ? entityId : "";
    }

    static int VecInputArgIndex(lua_State *L) {
        if (lua_istable(L, 2)) { return 2; }
        if (lua_istable(L, 1)) { return 1; }
        return 0;
    }

    static int LuaEntityGetName(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetNameCallback) {
            lua_pushliteral(L, "");
            return 1;
        }
        char nameBuffer[512] = {0};
        if (host->entityGetNameCallback(host->hostContext, BoundEntityId(L), nameBuffer, static_cast<int32_t>(sizeof(nameBuffer))) == 0) {
            lua_pushliteral(L, "");
            return 1;
        }
        lua_pushstring(L, nameBuffer);
        return 1;
    }

    static int LuaEntityGetID(lua_State *L) {
        lua_pushstring(L, BoundEntityId(L));
        return 1;
    }

    static int LuaEntityGetPosition(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, position);
        return 1;
    }

    static int LuaEntityGetRotationEuler(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, rotation);
        return 1;
    }

    static int LuaEntityGetScale(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, scale);
        return 1;
    }

    static int LuaEntitySetPosition(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetPosition unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetPosition failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {position[0], position[1], position[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, position)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, updated, rotation, scale) == 0) {
                LogWarning(host, std::string("SetPosition failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaEntitySetRotationEuler(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetRotationEuler unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetRotationEuler failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {rotation[0], rotation[1], rotation[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, rotation)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, position, updated, scale) == 0) {
                LogWarning(host, std::string("SetRotationEuler failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaEntitySetScale(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetScale unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetScale failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {scale[0], scale[1], scale[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, scale)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, position, rotation, updated) == 0) {
                LogWarning(host, std::string("SetScale failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaPrint(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const int top = lua_gettop(L);
        std::ostringstream stream;
        for (int i = 1; i <= top; ++i) {
            if (i > 1) {
                stream << " ";
            }
            size_t length = 0;
            const char *text = luaL_tolstring(L, i, &length);
            if (text) {
                stream.write(text, static_cast<std::streamsize>(length));
            }
            lua_pop(L, 1);
        }
        LogInfo(host, stream.str());
        return 0;
    }

    static int LuaLogInfo(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogInfo(host, message);
        return 0;
    }

    static int LuaLogWarn(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogWarning(host, message);
        return 0;
    }

    static int LuaLogError(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogError(host, message);
        return 0;
    }

    static void RegisterGlobals(LuaScriptHost *host) {
        if (!host || !host->L) { return; }
        lua_State *L = host->L;
        lua_createtable(L, 0, 1);
        lua_pushnumber(L, 0.0);
        lua_setfield(L, -2, "deltaTime");
        lua_setglobal(L, "Time");

        lua_createtable(L, 0, 3);
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogInfo, 1);
        lua_setfield(L, -2, "Info");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogWarn, 1);
        lua_setfield(L, -2, "Warn");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogError, 1);
        lua_setfield(L, -2, "Error");
        lua_setglobal(L, "Log");

        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaPrint, 1);
        lua_setglobal(L, "print");
    }

    static void SetDeltaTime(LuaScriptHost *host, float dt) {
        if (!host || !host->L) { return; }
        lua_getglobal(host->L, "Time");
        if (lua_istable(host->L, -1)) {
            lua_pushnumber(host->L, dt);
            lua_setfield(host->L, -2, "deltaTime");
        }
        lua_pop(host->L, 1);
    }

    static int FunctionRefFromField(lua_State *L, int tableIndex, const char *name) {
        lua_getfield(L, tableIndex, name);
        if (!lua_isfunction(L, -1)) {
            lua_pop(L, 1);
            return LUA_NOREF;
        }
        return luaL_ref(L, LUA_REGISTRYINDEX);
    }

    static bool CallInstanceFunction(LuaScriptHost *host,
                                     const std::string &entityId,
                                     LuaScriptInstance &instance,
                                     int functionRef,
                                     const char *phase,
                                     float dt,
                                     bool passDelta,
                                     std::string &outError) {
        if (!host || !host->L || functionRef == LUA_NOREF || instance.faulted) {
            return true;
        }
        lua_State *L = host->L;
        lua_rawgeti(L, LUA_REGISTRYINDEX, functionRef);
        if (!lua_isfunction(L, -1)) {
            lua_pop(L, 1);
            return true;
        }
        lua_rawgeti(L, LUA_REGISTRYINDEX, instance.selfRef);
        if (passDelta) {
            lua_pushnumber(L, dt);
        }
        const int argCount = passDelta ? 2 : 1;
        if (lua_pcall(L, argCount, 0, 0) == LUA_OK) {
            return true;
        }
        const char *errorText = lua_tostring(L, -1);
        outError = FormatLuaError(entityId, instance.scriptPath, phase, errorText ? errorText : "Unknown Lua error.");
        lua_pop(L, 1);
        instance.lastError = outError;
        instance.faulted = true;
        LogError(host, outError);
        return false;
    }

    static bool DestroyInstanceInternal(LuaScriptHost *host, const std::string &entityId, std::string *outError) {
        if (!host || !host->L) { return false; }
        auto it = host->instances.find(entityId);
        if (it == host->instances.end()) { return true; }

        std::string callbackError;
        LuaScriptInstance &instance = it->second;
        if (!instance.faulted) {
            CallInstanceFunction(host, entityId, instance, instance.onDestroyRef, "OnDestroy", 0.0f, false, callbackError);
        }
        ClearInstanceRefs(host->L, instance);
        host->instances.erase(it);
        if (outError && !callbackError.empty()) {
            *outError = callbackError;
        }
        return callbackError.empty();
    }

    static bool InstantiateInternal(LuaScriptHost *host,
                                    const std::string &entityId,
                                    const std::string &scriptPath,
                                    std::string &outError) {
        if (!host || !host->L) { return false; }
        DestroyInstanceInternal(host, entityId, nullptr);
        lua_State *L = host->L;

        if (luaL_loadfile(L, scriptPath.c_str()) != LUA_OK) {
            const char *errorText = lua_tostring(L, -1);
            outError = FormatLuaError(entityId, scriptPath, "Load", errorText ? errorText : "Unable to load file.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }
        if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
            const char *errorText = lua_tostring(L, -1);
            outError = FormatLuaError(entityId, scriptPath, "Execute", errorText ? errorText : "Unable to execute chunk.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }
        if (!lua_istable(L, -1)) {
            outError = FormatLuaError(entityId, scriptPath, "Load", "Script must return a table.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }

        const int moduleIndex = lua_gettop(L);
        LuaScriptInstance instance;
        instance.scriptPath = scriptPath;
        instance.onCreateRef = FunctionRefFromField(L, moduleIndex, "OnCreate");
        instance.onStartRef = FunctionRefFromField(L, moduleIndex, "OnStart");
        instance.onUpdateRef = FunctionRefFromField(L, moduleIndex, "OnUpdate");
        instance.onFixedUpdateRef = FunctionRefFromField(L, moduleIndex, "OnFixedUpdate");
        instance.onDestroyRef = FunctionRefFromField(L, moduleIndex, "OnDestroy");

        lua_createtable(L, 0, 1);
        lua_createtable(L, 0, 8);
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntityGetName, 2); lua_setfield(L, -2, "GetName");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntityGetID, 2); lua_setfield(L, -2, "GetID");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntityGetPosition, 2); lua_setfield(L, -2, "GetPosition");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntitySetPosition, 2); lua_setfield(L, -2, "SetPosition");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntityGetRotationEuler, 2); lua_setfield(L, -2, "GetRotationEuler");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntitySetRotationEuler, 2); lua_setfield(L, -2, "SetRotationEuler");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntityGetScale, 2); lua_setfield(L, -2, "GetScale");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId.c_str()); lua_pushcclosure(L, LuaEntitySetScale, 2); lua_setfield(L, -2, "SetScale");
        lua_setfield(L, -2, "entity");
        instance.selfRef = luaL_ref(L, LUA_REGISTRYINDEX);
        lua_pop(L, 1);

        host->instances[entityId] = std::move(instance);
        LuaScriptInstance &stored = host->instances[entityId];
        if (!CallInstanceFunction(host, entityId, stored, stored.onCreateRef, "OnCreate", 0.0f, false, outError)) {
            return false;
        }
        if (!CallInstanceFunction(host, entityId, stored, stored.onStartRef, "OnStart", 0.0f, false, outError)) {
            return false;
        }
        return true;
    }
}

extern "C" void *MCELuaRuntimeCreate(void *hostContext,
                                     LuaLogCallback logCallback,
                                     LuaEntityExistsCallback entityExistsCallback,
                                     LuaEntityGetNameCallback entityGetNameCallback,
                                     LuaEntityGetTransformCallback entityGetTransformCallback,
                                     LuaEntitySetTransformCallback entitySetTransformCallback) {
    LuaScriptHost *host = new LuaScriptHost();
    host->hostContext = hostContext;
    host->logCallback = logCallback;
    host->entityExistsCallback = entityExistsCallback;
    host->entityGetNameCallback = entityGetNameCallback;
    host->entityGetTransformCallback = entityGetTransformCallback;
    host->entitySetTransformCallback = entitySetTransformCallback;
    host->L = luaL_newstate();
    if (!host->L) {
        delete host;
        return nullptr;
    }
    luaL_requiref(host->L, "_G", luaopen_base, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_TABLIBNAME, luaopen_table, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_STRLIBNAME, luaopen_string, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_MATHLIBNAME, luaopen_math, 1);
    lua_pop(host->L, 1);
    RegisterGlobals(host);
    return host;
}

extern "C" void MCELuaRuntimeDestroy(void *runtimePtr) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host) { return; }
    if (host->L) {
        for (auto &entry : host->instances) {
            ClearInstanceRefs(host->L, entry.second);
        }
        host->instances.clear();
        lua_close(host->L);
        host->L = nullptr;
    }
    delete host;
}

extern "C" uint32_t MCELuaRuntimeInstantiate(void *runtimePtr,
                                             const char *entityId,
                                             const char *scriptPath,
                                             char *errorBuffer,
                                             int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !scriptPath) { return 0; }
    std::string error;
    const bool ok = InstantiateInternal(host, entityId, scriptPath, error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeReload(void *runtimePtr,
                                        const char *entityId,
                                        const char *scriptPath,
                                        char *errorBuffer,
                                        int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !scriptPath) { return 0; }
    std::string ignored;
    DestroyInstanceInternal(host, entityId, &ignored);
    std::string error;
    const bool ok = InstantiateInternal(host, entityId, scriptPath, error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeUpdate(void *runtimePtr,
                                        const char *entityId,
                                        float dt,
                                        char *errorBuffer,
                                        int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !host->L) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    SetDeltaTime(host, dt);
    std::string error;
    const bool ok = CallInstanceFunction(host,
                                         entityId,
                                         it->second,
                                         it->second.onUpdateRef,
                                         "OnUpdate",
                                         dt,
                                         true,
                                         error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeFixedUpdate(void *runtimePtr,
                                             const char *entityId,
                                             float dt,
                                             char *errorBuffer,
                                             int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !host->L) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    SetDeltaTime(host, dt);
    std::string error;
    const bool ok = CallInstanceFunction(host,
                                         entityId,
                                         it->second,
                                         it->second.onFixedUpdateRef,
                                         "OnFixedUpdate",
                                         dt,
                                         true,
                                         error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeDestroyInstance(void *runtimePtr,
                                                 const char *entityId,
                                                 char *errorBuffer,
                                                 int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId) { return 0; }
    std::string error;
    const bool ok = DestroyInstanceInternal(host, entityId, &error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeHasInstance(void *runtimePtr,
                                             const char *entityId) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 0; }
    return it->second.faulted ? 0u : 1u;
}
