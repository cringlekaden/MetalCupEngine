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
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <unordered_map>
#include <thread>

namespace {
    using namespace JPH;

    namespace Layers {
        static constexpr ObjectLayer NON_MOVING = 0;
        static constexpr ObjectLayer MOVING = 1;
        static constexpr ObjectLayer NUM_LAYERS = 2;
    }

    namespace BroadPhaseLayers {
        static constexpr BroadPhaseLayer NON_MOVING(0);
        static constexpr BroadPhaseLayer MOVING(1);
        static constexpr uint NUM_LAYERS = 2;
    }

    class BroadPhaseLayerInterfaceImpl final : public BroadPhaseLayerInterface {
    public:
        BroadPhaseLayerInterfaceImpl() {
            mLayers[Layers::NON_MOVING] = BroadPhaseLayers::NON_MOVING;
            mLayers[Layers::MOVING] = BroadPhaseLayers::MOVING;
        }

        uint GetNumBroadPhaseLayers() const override {
            return BroadPhaseLayers::NUM_LAYERS;
        }

        BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
            return mLayers[inLayer];
        }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
        const char *GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
            if (inLayer == BroadPhaseLayers::NON_MOVING) { return "NON_MOVING"; }
            if (inLayer == BroadPhaseLayers::MOVING) { return "MOVING"; }
            return "UNKNOWN";
        }
#endif

    private:
        BroadPhaseLayer mLayers[Layers::NUM_LAYERS];
    };

    class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
    public:
        bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
            if (inLayer1 == Layers::NON_MOVING) {
                return inLayer2 == BroadPhaseLayers::MOVING;
            }
            return true;
        }
    };

    class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
    public:
        bool ShouldCollide(ObjectLayer inObject1, ObjectLayer inObject2) const override {
            if (inObject1 == Layers::NON_MOVING && inObject2 == Layers::NON_MOVING) {
                return false;
            }
            return true;
        }
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
                                  std::unordered_map<uint64_t, OverlapEvent> *activeOverlaps,
                                  std::mutex *overlapMutex)
        : mSamples(samples)
        , mWriteIndex(writeIndex)
        , mOverlapEvents(overlapEvents)
        , mOverlapWriteIndex(overlapWriteIndex)
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
            if (!mOverlapEvents || !mOverlapWriteIndex || !mActiveOverlaps || !mOverlapMutex) { return; }
            if (!inBody1.IsSensor() && !inBody2.IsSensor()) { return; }
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
                (*mActiveOverlaps)[key] = event;
            }
        }

        ContactSample *mSamples = nullptr;
        std::atomic<uint32_t> *mWriteIndex = nullptr;
        OverlapEvent *mOverlapEvents = nullptr;
        std::atomic<uint32_t> *mOverlapWriteIndex = nullptr;
        std::unordered_map<uint64_t, OverlapEvent> *mActiveOverlaps = nullptr;
        std::mutex *mOverlapMutex = nullptr;
    };

    struct JoltWorld {
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
        std::unordered_map<uint64_t, OverlapEvent> activeOverlaps;
        std::mutex overlapMutex;
        ContactCollector contactCollector;
        bool useSingleThreaded;

        JoltWorld(uint32_t tempAllocatorBytes,
                  uint32_t maxJobs,
                  uint32_t maxBarriers,
                  uint32_t numThreads,
                  bool singleThreaded)
        : tempAllocator(tempAllocatorBytes)
        , jobSystem()
        , jobSystemSingleThreaded()
        , contactWriteIndex(0)
        , overlapWriteIndex(0)
        , contactCollector(contacts, &contactWriteIndex, overlapEvents, &overlapWriteIndex, &activeOverlaps, &overlapMutex)
        , useSingleThreaded(singleThreaded) {
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

    static ObjectLayer ObjectLayerFromMotion(uint32_t motionType) {
        return motionType == 0 ? Layers::NON_MOVING : Layers::MOVING;
    }
}

extern "C" void *MCEPhysicsCreateWorld(float gravityX,
                                       float gravityY,
                                       float gravityZ,
                                       uint32_t maxBodies,
                                       uint32_t maxBodyPairs,
                                       uint32_t maxContactConstraints,
                                       uint32_t singleThreaded) {
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

    JoltWorld *world = new JoltWorld(tempAllocatorBytes, maxJobs, maxBarriers, workerThreads, useSingleThreaded);
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

extern "C" uint64_t MCEPhysicsCreateBody(void *worldPtr,
                                         uint32_t shapeType,
                                         uint32_t motionType,
                                         float posX, float posY, float posZ,
                                         float rotX, float rotY, float rotZ, float rotW,
                                         float boxHX, float boxHY, float boxHZ,
                                         float sphereRadius,
                                         float capsuleHalfHeight,
                                         float capsuleRadius,
                                         float offsetX, float offsetY, float offsetZ,
                                         float rotOffsetX, float rotOffsetY, float rotOffsetZ, float rotOffsetW,
                                         float friction,
                                         float restitution,
                                         float linearDamping,
                                         float angularDamping,
                                         float gravityFactor,
                                         float mass,
                                         uint64_t userData,
                                         uint32_t ccdEnabled,
                                         uint32_t isSensor,
                                         uint32_t allowSleeping) {
    if (!worldPtr) { return 0; }
    JoltInitializeOnce();
#if DEBUG
    if (JPH::Factory::sInstance == nullptr) {
        fprintf(stderr, "Jolt Factory initialization failed before body creation.\n");
        JPH_ASSERT(false);
    }
#endif
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);

    RefConst<Shape> shape = BuildShape(shapeType,
                                       boxHX, boxHY, boxHZ,
                                       sphereRadius,
                                       capsuleHalfHeight,
                                       capsuleRadius,
                                       offsetX, offsetY, offsetZ,
                                       rotOffsetX, rotOffsetY, rotOffsetZ, rotOffsetW);
    if (!shape) { return 0; }

    const EMotionType joltMotion = MotionTypeFromUInt(motionType);
    const ObjectLayer layer = ObjectLayerFromMotion(motionType);

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
                                           float rotX, float rotY, float rotZ, float rotW) {
    if (!worldPtr || bodyIdValue == 0) { return; }
    JoltWorld *world = static_cast<JoltWorld *>(worldPtr);
    BodyInterface &bodyInterface = world->physicsSystem.GetBodyInterface();
    BodyID bodyId(bodyIdValue);
    if (!bodyInterface.IsAdded(bodyId)) { return; }
    bodyInterface.SetPositionAndRotation(bodyId, RVec3(posX, posY, posZ), Quat(rotX, rotY, rotZ, rotW), EActivation::Activate);
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
