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
#include <Jolt/Physics/Collision/ShapeFilter.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cfloat>
#include <cmath>
#include <cstring>
#include <sstream>
#include <mutex>
#include <unordered_map>
#include <vector>
#include <thread>

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
        struct CharacterRecord {
            Ref<CharacterVirtual> character;
            ObjectLayer objectLayer = 0;
            BodyID ignoreBodyID;
            bool hasIgnoreBodyID = false;
            Vec3 up = Vec3::sAxisY();
            float gravity = -9.81f;
            float stepOffset = 0.25f;
            float jumpSpeed = 5.5f;
            float maxStrength = 100.0f;
            float radius = 0.35f;
            float height = 1.8f;
            CharacterVirtual::ExtendedUpdateSettings updateSettings;
        };

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
        std::unordered_map<uint64_t, CharacterRecord> characters;
        std::atomic<uint64_t> nextCharacterHandle;
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
        , nextCharacterHandle(1)
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

    static RefConst<Shape> BuildCharacterCapsuleShape(float radius, float height) {
        const float safeRadius = std::max(0.02f, radius);
        const float safeHeight = std::max(safeRadius * 2.0f + 0.02f, height);
        const float capsuleHalfHeight = std::max(0.02f, safeHeight * 0.5f - safeRadius);
        RefConst<Shape> capsule = CapsuleShapeSettings(capsuleHalfHeight, safeRadius).Create().Get();
        // CharacterBaseSettings expects the bottom of the shape at local y = 0.
        // A capsule shape is centered at origin by default, so translate it up.
        RotatedTranslatedShapeSettings translated(Vec3(0.0f, capsuleHalfHeight + safeRadius, 0.0f),
                                                  Quat::sIdentity(),
                                                  capsule);
        return translated.Create().Get();
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
    const RVec3 position(posX, posY, posZ);
    const Quat rotation(rotX, rotY, rotZ, rotW);
    bodyInterface.SetPositionAndRotation(bodyId,
                                         position,
                                         rotation,
                                         activate != 0 ? EActivation::Activate : EActivation::DontActivate);
}

extern "C" void MCEPhysicsMoveKinematic(void *worldPtr,
                                        uint64_t bodyIdValue,
                                        float posX, float posY, float posZ,
                                        float rotX, float rotY, float rotZ, float rotW,
                                        float dt) {
    if (!worldPtr || bodyIdValue == 0 || dt <= 0.0f) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    if (bodyInterface.GetMotionType(bodyId) != EMotionType::Kinematic) { return; }
    bodyInterface.MoveKinematic(bodyId,
                                RVec3(posX, posY, posZ),
                                Quat(rotX, rotY, rotZ, rotW),
                                dt);
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

extern "C" uint32_t MCEPhysicsCapsuleCastClosest(void *worldPtr,
                                                 float originX, float originY, float originZ,
                                                 float rotX, float rotY, float rotZ, float rotW,
                                                 float dirX, float dirY, float dirZ,
                                                 float halfHeight,
                                                 float radius,
                                                 float maxDistance,
                                                 float *positionOut,
                                                 float *normalOut,
                                                 float *distanceOut,
                                                 uint64_t *bodyIdOut,
                                                 uint64_t *userDataOut) {
    if (!worldPtr || !positionOut || !normalOut || !distanceOut || !bodyIdOut || !userDataOut) { return 0; }
    if (maxDistance <= 0.0f || radius <= 0.0f || halfHeight <= 0.0f) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    Vec3 dir(dirX, dirY, dirZ);
    if (dir.LengthSq() < 1.0e-8f) { return 0; }
    dir = dir.Normalized();

    CapsuleShapeSettings capsuleSettings(halfHeight, radius);
    RefConst<Shape> shape = capsuleSettings.Create().Get();
    if (!shape) { return 0; }

    const RMat44 startTransform = RMat44::sRotationTranslation(Quat(rotX, rotY, rotZ, rotW),
                                                               RVec3(originX, originY, originZ));
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

extern "C" uint64_t MCECharacter_Create(void *worldPtr,
                                        float radius,
                                        float height,
                                        float posX, float posY, float posZ,
                                        float rotX, float rotY, float rotZ, float rotW,
                                        uint32_t objectLayer,
                                        uint64_t ignoreBodyId) {
    if (!worldPtr) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    JoltWorld::CharacterRecord record;
    record.objectLayer = ObjectLayerFromCollisionLayer(objectLayer, world->layerCount);
    record.radius = std::max(0.02f, radius);
    record.height = std::max(record.radius * 2.0f + 0.02f, height);
    record.hasIgnoreBodyID = ignoreBodyId != 0;
    if (record.hasIgnoreBodyID) {
        record.ignoreBodyID = BodyID(ignoreBodyId);
    }

    CharacterVirtualSettings settings;
    settings.mShape = BuildCharacterCapsuleShape(record.radius, record.height);
    if (!settings.mShape) { return 0; }
    settings.mUp = record.up;
    settings.mSupportingVolume = Plane(record.up, -record.radius);
    settings.mMaxSlopeAngle = DegreesToRadians(50.0f);
    settings.mMass = 70.0f;
    settings.mMaxStrength = record.maxStrength;
    settings.mPredictiveContactDistance = std::max(0.02f, record.radius * 0.5f);
    settings.mCollisionTolerance = 1.0e-3f;
    settings.mEnhancedInternalEdgeRemoval = true;

    record.character = new CharacterVirtual(&settings,
                                            RVec3(posX, posY, posZ),
                                            Quat(rotX, rotY, rotZ, rotW),
                                            0,
                                            &world->physicsSystem);
    if (record.character == nullptr) {
        return 0;
    }
    record.character->SetUp(record.up);
    record.updateSettings.mWalkStairsStepUp = record.up * record.stepOffset;
    record.updateSettings.mStickToFloorStepDown = -record.up * std::max(0.0f, record.stepOffset + 0.05f);

    const uint64_t handle = world->nextCharacterHandle.fetch_add(1, std::memory_order_relaxed);
    world->characters.emplace(handle, std::move(record));
    return handle;
}

extern "C" void MCECharacter_Destroy(void *worldPtr, uint64_t handle) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    world->characters.erase(handle);
}

extern "C" void MCECharacter_SetShapeCapsule(void *worldPtr, uint64_t handle, float radius, float height) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    JoltWorld::CharacterRecord &record = it->second;
    record.radius = std::max(0.02f, radius);
    record.height = std::max(record.radius * 2.0f + 0.02f, height);
    RefConst<Shape> shape = BuildCharacterCapsuleShape(record.radius, record.height);
    if (!shape) { return; }
    TempAllocatorMalloc allocator;
    const auto &broadPhaseLayerFilter = world->physicsSystem.GetDefaultBroadPhaseLayerFilter(record.objectLayer);
    const auto &objectLayerFilter = world->physicsSystem.GetDefaultLayerFilter(record.objectLayer);
    IgnoreSingleBodyFilter ignoreBodyFilter(record.hasIgnoreBodyID ? record.ignoreBodyID : BodyID());
    BodyFilter bodyFilter;
    const BodyFilter &resolvedBodyFilter = record.hasIgnoreBodyID ? static_cast<const BodyFilter &>(ignoreBodyFilter) : bodyFilter;
    ShapeFilter shapeFilter;
    if (record.character->SetShape(shape,
                                   FLT_MAX,
                                   broadPhaseLayerFilter,
                                   objectLayerFilter,
                                   resolvedBodyFilter,
                                   shapeFilter,
                                   allocator)) {
        record.character->SetInnerBodyShape(shape);
    }
}

extern "C" void MCECharacter_SetMaxSlope(void *worldPtr, uint64_t handle, float radians) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    const float minSlope = DegreesToRadians(1.0f);
    const float maxSlope = DegreesToRadians(89.0f);
    it->second.character->SetMaxSlopeAngle(std::clamp(radians, minSlope, maxSlope));
}

extern "C" void MCECharacter_SetStepOffset(void *worldPtr, uint64_t handle, float meters) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    JoltWorld::CharacterRecord &record = it->second;
    record.stepOffset = std::max(0.0f, meters);
    record.updateSettings.mWalkStairsStepUp = record.up * record.stepOffset;
    record.updateSettings.mStickToFloorStepDown = -record.up * std::max(0.0f, record.stepOffset + 0.05f);
}

extern "C" void MCECharacter_SetGravity(void *worldPtr, uint64_t handle, float value) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    // Character gravity is always applied along -up in ExtendedUpdate.
    // Accept both +/- authored values and normalize to a downward magnitude.
    it->second.gravity = -std::fabs(value);
}

extern "C" void MCECharacter_SetJumpSpeed(void *worldPtr, uint64_t handle, float value) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    it->second.jumpSpeed = std::max(0.0f, value);
}

extern "C" void MCECharacter_SetPushStrength(void *worldPtr, uint64_t handle, float value) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    JoltWorld::CharacterRecord &record = it->second;
    record.maxStrength = std::max(0.0f, value);
    record.character->SetMaxStrength(record.maxStrength);
}

extern "C" void MCECharacter_SetUpVector(void *worldPtr, uint64_t handle, float x, float y, float z) {
    if (!worldPtr || handle == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return; }
    Vec3 up(x, y, z);
    if (up.LengthSq() <= 1.0e-8f) {
        up = Vec3::sAxisY();
    } else {
        up = up.Normalized();
    }
    JoltWorld::CharacterRecord &record = it->second;
    record.up = up;
    record.character->SetUp(up);
    record.updateSettings.mWalkStairsStepUp = up * record.stepOffset;
    record.updateSettings.mStickToFloorStepDown = -up * std::max(0.0f, record.stepOffset + 0.05f);
}

extern "C" uint32_t MCECharacter_Update(void *worldPtr,
                                        uint64_t handle,
                                        float dt,
                                        float desiredVelX,
                                        float desiredVelY,
                                        float desiredVelZ,
                                        uint32_t jumpRequested) {
    if (!worldPtr || handle == 0 || dt <= 0.0f) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    JoltWorld::CharacterRecord &record = it->second;
    // Keep supporting body velocity current before deriving desired velocity.
    record.character->UpdateGroundVelocity();
    const auto currentGroundState = record.character->GetGroundState();
    const bool onGround = currentGroundState == CharacterBase::EGroundState::OnGround;
    const Vec3 currentVelocity = record.character->GetLinearVelocity();
    Vec3 desiredVelocity(desiredVelX, desiredVelY, desiredVelZ);
    const float desiredVerticalSpeed = desiredVelocity.Dot(record.up);
    const Vec3 desiredPlanarVelocity = desiredVelocity - record.up * desiredVerticalSpeed;

    // CharacterVirtual docs/sample pattern:
    // - OnGround and moving towards ground: base from ground velocity (+ optional jump)
    // - Else: preserve current vertical velocity
    // - Then add gravity * dt and desired horizontal velocity.
    const Vec3 currentVerticalVelocity = currentVelocity.Dot(record.up) * record.up;
    const Vec3 groundVelocity = record.character->GetGroundVelocity();
    const bool movingTowardsGround =
        (currentVerticalVelocity - groundVelocity).Dot(record.up) < 0.1f;

    Vec3 velocity = onGround && movingTowardsGround
        ? groundVelocity
        : currentVerticalVelocity;

    if (jumpRequested != 0 && onGround && movingTowardsGround) {
        velocity += record.up * record.jumpSpeed;
    }

    velocity += record.up * (record.gravity * dt);
    velocity += desiredPlanarVelocity;
    record.character->SetLinearVelocity(velocity);
    const auto &broadPhaseLayerFilter = world->physicsSystem.GetDefaultBroadPhaseLayerFilter(record.objectLayer);
    const auto &objectLayerFilter = world->physicsSystem.GetDefaultLayerFilter(record.objectLayer);
    IgnoreSingleBodyFilter ignoreBodyFilter(record.hasIgnoreBodyID ? record.ignoreBodyID : BodyID());
    BodyFilter bodyFilter;
    const BodyFilter &resolvedBodyFilter = record.hasIgnoreBodyID ? static_cast<const BodyFilter &>(ignoreBodyFilter) : bodyFilter;
    ShapeFilter shapeFilter;
    TempAllocatorMalloc allocator;
    record.character->ExtendedUpdate(dt,
                                     record.up * record.gravity,
                                     record.updateSettings,
                                     broadPhaseLayerFilter,
                                     objectLayerFilter,
                                     resolvedBodyFilter,
                                     shapeFilter,
                                     allocator);
    return 1;
}

extern "C" uint32_t MCECharacter_GetPosition(void *worldPtr, uint64_t handle, float *positionOut) {
    if (!worldPtr || handle == 0 || !positionOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const RVec3 position = it->second.character->GetPosition();
    positionOut[0] = static_cast<float>(position.GetX());
    positionOut[1] = static_cast<float>(position.GetY());
    positionOut[2] = static_cast<float>(position.GetZ());
    return 1;
}

extern "C" uint32_t MCECharacter_GetRotation(void *worldPtr, uint64_t handle, float *rotationOut) {
    if (!worldPtr || handle == 0 || !rotationOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const Quat rotation = it->second.character->GetRotation();
    rotationOut[0] = rotation.GetX();
    rotationOut[1] = rotation.GetY();
    rotationOut[2] = rotation.GetZ();
    rotationOut[3] = rotation.GetW();
    return 1;
}

extern "C" uint32_t MCECharacter_IsGrounded(void *worldPtr, uint64_t handle) {
    if (!worldPtr || handle == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const auto groundState = it->second.character->GetGroundState();
    return groundState == CharacterBase::EGroundState::OnGround ? 1 : 0;
}

extern "C" uint32_t MCECharacter_GetGroundNormal(void *worldPtr, uint64_t handle, float *normalOut) {
    if (!worldPtr || handle == 0 || !normalOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const Vec3 normal = it->second.character->GetGroundNormal();
    normalOut[0] = normal.GetX();
    normalOut[1] = normal.GetY();
    normalOut[2] = normal.GetZ();
    return 1;
}

extern "C" uint32_t MCECharacter_GetGroundVelocity(void *worldPtr, uint64_t handle, float *velocityOut) {
    if (!worldPtr || handle == 0 || !velocityOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const Vec3 velocity = it->second.character->GetGroundVelocity();
    velocityOut[0] = velocity.GetX();
    velocityOut[1] = velocity.GetY();
    velocityOut[2] = velocity.GetZ();
    return 1;
}

extern "C" uint64_t MCECharacter_GetGroundBodyID(void *worldPtr, uint64_t handle) {
    if (!worldPtr || handle == 0) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }
    const BodyID bodyID = it->second.character->GetGroundBodyID();
    if (bodyID == BodyID()) { return 0; }
    return static_cast<uint64_t>(bodyID.GetIndexAndSequenceNumber());
}

extern "C" uint32_t MCECharacter_GetContactStats(void *worldPtr,
                                                 uint64_t handle,
                                                 uint32_t *totalContactsOut,
                                                 uint32_t *dynamicContactsOut,
                                                 uint64_t *firstDynamicBodyIdOut) {
    if (!worldPtr || handle == 0 || !totalContactsOut || !dynamicContactsOut || !firstDynamicBodyIdOut) { return 0; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    auto it = world->characters.find(handle);
    if (it == world->characters.end()) { return 0; }

    const auto &contacts = it->second.character->GetActiveContacts();
    uint32_t dynamicContacts = 0;
    uint64_t firstDynamicBodyId = 0;
    for (const CharacterVirtual::Contact &contact : contacts) {
        if (contact.mBodyB == BodyID()) { continue; }
        BodyLockRead lock(world->physicsSystem.GetBodyLockInterface(), contact.mBodyB);
        if (!lock.Succeeded()) { continue; }
        const Body &body = lock.GetBody();
        if (body.GetMotionType() == EMotionType::Dynamic) {
            dynamicContacts += 1;
            if (firstDynamicBodyId == 0) {
                firstDynamicBodyId = static_cast<uint64_t>(contact.mBodyB.GetIndexAndSequenceNumber());
            }
        }
    }

    *totalContactsOut = static_cast<uint32_t>(contacts.size());
    *dynamicContactsOut = dynamicContacts;
    *firstDynamicBodyIdOut = firstDynamicBodyId;
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
