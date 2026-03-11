/// CharacterControllerSystem.swift
/// Owns character controller runtime state, input queues, and fixed-step updates.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct CharacterTerrainSample {
    public var normal: SIMD3<Float>
    public var height: Float
    public var material: UInt32?

    public init(normal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                height: Float = 0.0,
                material: UInt32? = nil) {
        self.normal = normal
        self.height = height
        self.material = material
    }
}

public struct CharacterGroundState {
    public var isGrounded: Bool
    public var groundNormal: SIMD3<Float>
    public var groundBodyId: UInt64
    public var groundVelocity: SIMD3<Float>
    public var isMovingPlatform: Bool
    public var terrainSample: CharacterTerrainSample?

    public init(isGrounded: Bool = false,
                groundNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                groundBodyId: UInt64 = 0,
                groundVelocity: SIMD3<Float> = .zero,
                isMovingPlatform: Bool = false,
                terrainSample: CharacterTerrainSample? = nil) {
        self.isGrounded = isGrounded
        self.groundNormal = groundNormal
        self.groundBodyId = groundBodyId
        self.groundVelocity = groundVelocity
        self.isMovingPlatform = isMovingPlatform
        self.terrainSample = terrainSample
    }
}

public struct CharacterLocomotionOutput {
    public var desiredVelocity: SIMD3<Float>
    public var actualVelocity: SIMD3<Float>
    public var grounded: Bool
    public var groundNormal: SIMD3<Float>
    public var groundBodyId: UInt64
    public var rootMotionDeltaMagnitude: Float
    public var rootMotionEnabled: Bool
    public var rootMotionActive: Bool
    public var rootMotionStateName: String

    public init(desiredVelocity: SIMD3<Float> = .zero,
                actualVelocity: SIMD3<Float> = .zero,
                grounded: Bool = false,
                groundNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                groundBodyId: UInt64 = 0,
                rootMotionDeltaMagnitude: Float = 0.0,
                rootMotionEnabled: Bool = false,
                rootMotionActive: Bool = false,
                rootMotionStateName: String = "") {
        self.desiredVelocity = desiredVelocity
        self.actualVelocity = actualVelocity
        self.grounded = grounded
        self.groundNormal = groundNormal
        self.groundBodyId = groundBodyId
        self.rootMotionDeltaMagnitude = rootMotionDeltaMagnitude
        self.rootMotionEnabled = rootMotionEnabled
        self.rootMotionActive = rootMotionActive
        self.rootMotionStateName = rootMotionStateName
    }
}

public struct CharacterControllerDebugVisualization {
    public var enabled: Bool
    public var groundNormal: SIMD3<Float>
    public var basisForward: SIMD3<Float>
    public var basisRight: SIMD3<Float>

    public init(enabled: Bool = false,
                groundNormal: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0),
                basisForward: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 1.0),
                basisRight: SIMD3<Float> = SIMD3<Float>(1.0, 0.0, 0.0)) {
        self.enabled = enabled
        self.groundNormal = groundNormal
        self.basisForward = basisForward
        self.basisRight = basisRight
    }
}

public struct CharacterControllerPreStepContext {
    public let scene: EngineScene
    public let entity: Entity
    public let fixedDelta: Float
    public let desiredHorizontalVelocity: SIMD3<Float>
    public let groundState: CharacterGroundState
}

public struct CharacterControllerPostStepContext {
    public let scene: EngineScene
    public let entity: Entity
    public let fixedDelta: Float
    public let locomotion: CharacterLocomotionOutput
    public let groundState: CharacterGroundState
}

public protocol CharacterGroundProvider {
    func resolveGround(scene: EngineScene,
                       physicsSystem: PhysicsSystem,
                       entity: Entity,
                       controller: CharacterControllerComponent,
                       characterHandle: UInt64) -> CharacterGroundState
}

public protocol CharacterControllerStepHook {
    func preStep(_ context: CharacterControllerPreStepContext)
    func postStep(_ context: CharacterControllerPostStepContext)
}

public final class CharacterControllerSystem {
    private struct CharacterInterpolationState {
        var prevPosition: SIMD3<Float>
        var currPosition: SIMD3<Float>
        var prevRotation: SIMD4<Float>
        var currRotation: SIMD4<Float>
        var initialized: Bool
    }

    private var characterMoveRequests: [UUID: SIMD2<Float>] = [:]
    private var characterLookRequests: [UUID: SIMD2<Float>] = [:]
    private var characterSprintRequests: [UUID: Bool] = [:]
    private var characterJumpRequests: Set<UUID> = []
    private var characterHandlesByEntity: [UUID: UInt64] = [:]
    private var characterInterpolationStates: [UUID: CharacterInterpolationState] = [:]
    private var renderInterpolationAlpha: Float = 0.0
    private var renderWorldTransformCache: [UUID: TransformComponent] = [:]
    private var locomotionOutputsByEntity: [UUID: CharacterLocomotionOutput] = [:]
    private var debugVisualizationByEntity: [UUID: CharacterControllerDebugVisualization] = [:]
    private var groundProvider: CharacterGroundProvider = DefaultCharacterGroundProvider()
    private var stepHook: CharacterControllerStepHook?

    public init() {}

    public func enqueueMove(entityId: UUID, direction: SIMD3<Float>) {
        characterMoveRequests[entityId] = SIMD2<Float>(direction.x, direction.z)
    }

    public func enqueueMoveInput(entityId: UUID, input: SIMD2<Float>) {
        characterMoveRequests[entityId] = input
    }

    public func enqueueSprint(entityId: UUID, isSprinting: Bool) {
        characterSprintRequests[entityId] = isSprinting
    }

    public func enqueueLookInput(entityId: UUID, delta: SIMD2<Float>) {
        let previous = characterLookRequests[entityId] ?? .zero
        characterLookRequests[entityId] = previous + delta
    }

    public func enqueueJump(entityId: UUID) {
        characterJumpRequests.insert(entityId)
    }

    public func isGrounded(scene: EngineScene, entityId: UUID) -> Bool {
        guard let entity = scene.ecs.entity(with: entityId),
              let controller = scene.ecs.get(CharacterControllerComponent.self, for: entity) else {
            return false
        }
        return controller.isGrounded
    }

    public func velocity(scene: EngineScene, entityId: UUID) -> SIMD3<Float> {
        guard let entity = scene.ecs.entity(with: entityId),
              let controller = scene.ecs.get(CharacterControllerComponent.self, for: entity) else {
            return .zero
        }
        return controller.velocity
    }

    public func locomotionOutput(entityId: UUID) -> CharacterLocomotionOutput {
        locomotionOutputsByEntity[entityId] ?? CharacterLocomotionOutput()
    }

    public func debugVisualization(entityId: UUID) -> CharacterControllerDebugVisualization {
        debugVisualizationByEntity[entityId] ?? CharacterControllerDebugVisualization()
    }

    public func setDebugDrawEnabled(entityId: UUID, isEnabled: Bool) {
        var state = debugVisualizationByEntity[entityId] ?? CharacterControllerDebugVisualization()
        state.enabled = isEnabled
        debugVisualizationByEntity[entityId] = state
    }

    public func isDebugDrawEnabled(entityId: UUID) -> Bool {
        debugVisualizationByEntity[entityId]?.enabled ?? false
    }

    public func setGroundProvider(_ provider: CharacterGroundProvider?) {
        groundProvider = provider ?? DefaultCharacterGroundProvider()
    }

    public func setStepHook(_ hook: CharacterControllerStepHook?) {
        stepHook = hook
    }

    public func setRenderInterpolationAlpha(_ alpha: Float, scene: EngineScene) {
        renderInterpolationAlpha = simd_clamp(alpha, 0.0, 1.0)
        rebuildRenderWorldTransformCache(scene: scene)
    }

    public func renderWorldTransform(scene: EngineScene, entity: Entity) -> TransformComponent {
        if let cached = renderWorldTransformCache[entity.id] {
            return cached
        }
        return scene.ecs.worldTransform(for: entity)
    }

    public func fixedStep(scene: EngineScene, fixedDelta: Float) {
        guard let physicsSystem = scene.physicsSystem else {
            scene.ecs.viewDeterministic(CharacterControllerComponent.self) { entity, _ in
                guard var controller = scene.ecs.get(CharacterControllerComponent.self, for: entity) else { return }
                controller.characterHandle = 0
                controller.isGrounded = false
                controller.velocity = .zero
                controller.lookInput = .zero
                controller.jumpBufferTimer = 0.0
                controller.jumpConsumedOnGroundContact = false
                scene.ecs.add(controller, to: entity)
            }
            characterHandlesByEntity.removeAll(keepingCapacity: true)
            characterInterpolationStates.removeAll(keepingCapacity: true)
            renderWorldTransformCache.removeAll(keepingCapacity: true)
            locomotionOutputsByEntity.removeAll(keepingCapacity: true)
            debugVisualizationByEntity.removeAll(keepingCapacity: true)
            characterJumpRequests.removeAll(keepingCapacity: true)
            characterLookRequests.removeAll(keepingCapacity: true)
            return
        }

        var activeEntityIDs: Set<UUID> = []
        activeEntityIDs.reserveCapacity(characterHandlesByEntity.count + 8)
        scene.ecs.viewDeterministic(CharacterControllerComponent.self) { entity, component in
            activeEntityIDs.insert(entity.id)
            guard var controller = scene.ecs.get(CharacterControllerComponent.self, for: entity),
                  let transform = scene.ecs.get(TransformComponent.self, for: entity) else { return }
            let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity)
            if !component.isEnabled {
                if controller.characterHandle != 0 {
                    physicsSystem.destroyCharacter(handle: controller.characterHandle)
                }
                controller.characterHandle = 0
                controller.runtimeConfigApplied = false
                controller.isGrounded = false
                controller.velocity = .zero
                controller.lookInput = .zero
                controller.jumpBufferTimer = 0.0
                controller.jumpConsumedOnGroundContact = false
                characterInterpolationStates.removeValue(forKey: entity.id)
                locomotionOutputsByEntity[entity.id] = CharacterLocomotionOutput()
                debugVisualizationByEntity[entity.id] = CharacterControllerDebugVisualization(enabled: isDebugDrawEnabled(entityId: entity.id))
                scene.ecs.add(controller, to: entity)
                characterHandlesByEntity.removeValue(forKey: entity.id)
                return
            }

            let moveInput = characterMoveRequests[entity.id] ?? controller.moveInput
            let lookInput = characterLookRequests[entity.id] ?? controller.lookInput
            let sprinting = characterSprintRequests[entity.id] ?? controller.wantsSprint
            controller.moveInput = moveInput
            controller.lookInput = lookInput
            controller.wantsSprint = sprinting

            var rootMotionDelta = RootMotionDelta()
            var rootMotionDeltaMagnitude: Float = 0.0
            var rootMotionEnabled = false
            var rootMotionActive = false
            var rootMotionStateName = ""
            if let rootMotion = resolveRootMotionForController(scene: scene, entity: entity, controller: controller) {
                rootMotionEnabled = rootMotion.enableRootMotion
                rootMotionActive = rootMotion.enableRootMotion && rootMotion.usesRootMotion
                rootMotionStateName = rootMotion.currentStateName
                rootMotionDelta = sanitizeRootMotionDelta(rootMotion.delta)
                rootMotionDeltaMagnitude = simd_length(rootMotionDelta.deltaPos)
            }

            let characterForwardAxis = TransformMath.localForward
            if !controller.lookInitialized {
                let currentRotation = simd_quatf(vector: transform.rotation)
                let currentForward = currentRotation.act(characterForwardAxis)
                controller.yawRadians = atan2(currentForward.x, currentForward.z)
                controller.pitchRadians = 0.0
                controller.lookInitialized = true
            }

            let lookSensitivity = max(0.0, controller.lookSensitivity)
            let yawDelta = rootMotionActive ? 0.0 : (-lookInput.x * lookSensitivity)
            controller.yawRadians += yawDelta
            let minPitch = controller.minPitchDegrees * (.pi / 180.0)
            let maxPitch = controller.maxPitchDegrees * (.pi / 180.0)
            controller.pitchRadians = simd_clamp(controller.pitchRadians + lookInput.y * lookSensitivity,
                                                 min(minPitch, maxPitch),
                                                 max(minPitch, maxPitch))
            controller.lookInput = .zero

            let upAxis = SIMD3<Float>(0.0, 1.0, 0.0)
            var yawQuat = simd_quatf(angle: controller.yawRadians, axis: upAxis)
            if rootMotionActive {
                yawQuat = simd_normalize(simd_quatf(vector: rootMotionDelta.deltaRot) * yawQuat)
                var rootedForward = yawQuat.act(characterForwardAxis)
                rootedForward.y = 0.0
                if simd_length_squared(rootedForward) > 1.0e-6 {
                    rootedForward = simd_normalize(rootedForward)
                    controller.yawRadians = atan2(rootedForward.x, rootedForward.z)
                }
            }
            let yawRotation = TransformMath.normalizedQuaternion(yawQuat.vector)

            let effectiveMoveInput = rootMotionActive ? SIMD2<Float>.zero : moveInput

            let normalizedInput: SIMD2<Float> = {
                let len = simd_length(effectiveMoveInput)
                guard len > 1e-5 else { return .zero }
                return effectiveMoveInput / min(1.0, len)
            }()

            var forward = yawQuat.act(characterForwardAxis)
            forward.y = 0.0
            if simd_length_squared(forward) > 1.0e-6 {
                forward = simd_normalize(forward)
            } else {
                forward = characterForwardAxis
            }
            var right = simd_cross(upAxis, forward)
            if simd_length_squared(right) > 1.0e-6 {
                right = simd_normalize(right)
            } else {
                right = SIMD3<Float>(1.0, 0.0, 0.0)
            }

            var desiredHorizontal = right * (-normalizedInput.x) + forward * normalizedInput.y
            if simd_length_squared(desiredHorizontal) > 1e-6 {
                desiredHorizontal = simd_normalize(desiredHorizontal)
            }
            let speedMultiplier = sprinting ? max(1.0, controller.sprintMultiplier) : 1.0
            let horizontalVelocity = desiredHorizontal * max(0.0, controller.moveSpeed) * speedMultiplier
            let desiredHorizontalVelocity = SIMD3<Float>(horizontalVelocity.x, 0.0, horizontalVelocity.z)
            let worldRootDelta = yawQuat.act(rootMotionDelta.deltaPos)
            let rootHorizontalDisplacement = SIMD3<Float>(worldRootDelta.x, 0.0, worldRootDelta.z)

            let worldTransform = scene.ecs.worldTransform(for: entity)
            let createdCharacterThisTick: Bool
            if controller.characterHandle == 0 {
                let desc = PhysicsCharacterCreation(radius: controller.radius,
                                                    height: controller.height,
                                                    position: worldTransform.position,
                                                    rotation: yawRotation,
                                                    collisionLayer: rigidbody?.collisionLayer ?? 0,
                                                    ignoreBodyId: rigidbody?.bodyId ?? 0)
                controller.characterHandle = physicsSystem.createCharacter(desc: desc)
                if controller.characterHandle == 0 {
                    scene.ecs.add(controller, to: entity)
                    return
                }
                createdCharacterThisTick = true
            } else {
                createdCharacterThisTick = false
            }
            characterHandlesByEntity[entity.id] = controller.characterHandle

            let gravityY = controller.useGravityOverride ? controller.gravity : (scene.engineContext?.physicsSettings.gravity.y ?? -9.81)
            let worldUpAxis = SIMD3<Float>(0.0, 1.0, 0.0)
            let slopeRadians = controller.maxSlope * (.pi / 180.0)
            let shouldApplyConfig = createdCharacterThisTick || !controller.runtimeConfigApplied
            if shouldApplyConfig || abs(controller.runtimeAppliedRadius - controller.radius) > 1.0e-4 || abs(controller.runtimeAppliedHeight - controller.height) > 1.0e-4 {
                physicsSystem.setCharacterShapeCapsule(handle: controller.characterHandle, radius: controller.radius, height: controller.height)
                controller.runtimeAppliedRadius = controller.radius
                controller.runtimeAppliedHeight = controller.height
            }
            if shouldApplyConfig || abs(controller.runtimeAppliedMaxSlope - slopeRadians) > 1.0e-4 {
                physicsSystem.setCharacterMaxSlope(handle: controller.characterHandle, radians: slopeRadians)
                controller.runtimeAppliedMaxSlope = slopeRadians
            }
            if shouldApplyConfig || abs(controller.runtimeAppliedStepOffset - controller.stepOffset) > 1.0e-4 {
                physicsSystem.setCharacterStepOffset(handle: controller.characterHandle, meters: max(0.0, controller.stepOffset))
                controller.runtimeAppliedStepOffset = controller.stepOffset
            }
            if shouldApplyConfig || abs(controller.runtimeAppliedGravity - gravityY) > 1.0e-4 {
                physicsSystem.setCharacterGravity(handle: controller.characterHandle, value: gravityY)
                controller.runtimeAppliedGravity = gravityY
            }
            if shouldApplyConfig || abs(controller.runtimeAppliedJumpSpeed - controller.jumpSpeed) > 1.0e-4 {
                physicsSystem.setCharacterJumpSpeed(handle: controller.characterHandle, value: max(0.0, controller.jumpSpeed))
                controller.runtimeAppliedJumpSpeed = controller.jumpSpeed
            }
            if shouldApplyConfig || abs(controller.runtimeAppliedPushStrength - controller.pushStrength) > 1.0e-4 {
                physicsSystem.setCharacterPushStrength(handle: controller.characterHandle, value: max(0.0, controller.pushStrength))
                controller.runtimeAppliedPushStrength = controller.pushStrength
            }
            if shouldApplyConfig {
                physicsSystem.setCharacterUpVector(handle: controller.characterHandle, up: worldUpAxis)
                controller.runtimeConfigApplied = true
            }

            let wasGrounded = physicsSystem.characterIsGrounded(handle: controller.characterHandle)
            let preGroundState = groundProvider.resolveGround(scene: scene,
                                                              physicsSystem: physicsSystem,
                                                              entity: entity,
                                                              controller: controller,
                                                              characterHandle: controller.characterHandle)
            stepHook?.preStep(.init(scene: scene,
                                    entity: entity,
                                    fixedDelta: fixedDelta,
                                    desiredHorizontalVelocity: desiredHorizontalVelocity,
                                    groundState: preGroundState))
            if !wasGrounded {
                controller.jumpConsumedOnGroundContact = false
            }
            controller.jumpBufferTimer = max(0.0, controller.jumpBufferTimer - fixedDelta)
            if characterJumpRequests.contains(entity.id) {
                controller.jumpBufferTimer = 0.12
            }
            let jumpRequested = wasGrounded
                && !controller.jumpConsumedOnGroundContact
                && controller.jumpBufferTimer > 0.0
            if jumpRequested {
                controller.jumpConsumedOnGroundContact = true
                controller.jumpBufferTimer = 0.0
            }

            var desiredVelocity = desiredHorizontalVelocity
            if !rootMotionActive, !wasGrounded {
                let airControl = simd_clamp(controller.airControl, 0.0, 1.0)
                if airControl < 0.999 {
                    let currentHorizontal = SIMD3<Float>(controller.velocity.x, 0.0, controller.velocity.z)
                    desiredVelocity = simd_mix(currentHorizontal, desiredVelocity, SIMD3<Float>(repeating: airControl))
                }
            }

            let startPosition = worldTransform.position
            var updated = rootMotionActive
                ? physicsSystem.updateCharacterDisplacement(handle: controller.characterHandle,
                                                            dt: fixedDelta,
                                                            desiredDisplacement: rootHorizontalDisplacement,
                                                            jumpRequested: jumpRequested)
                : physicsSystem.updateCharacter(handle: controller.characterHandle,
                                               dt: fixedDelta,
                                               desiredVelocity: desiredVelocity,
                                               jumpRequested: jumpRequested)
            if !updated {
                physicsSystem.destroyCharacter(handle: controller.characterHandle)
                let desc = PhysicsCharacterCreation(radius: controller.radius,
                                                    height: controller.height,
                                                    position: startPosition,
                                                    rotation: yawRotation,
                                                    collisionLayer: rigidbody?.collisionLayer ?? 0,
                                                    ignoreBodyId: rigidbody?.bodyId ?? 0)
                controller.characterHandle = physicsSystem.createCharacter(desc: desc)
                characterHandlesByEntity[entity.id] = controller.characterHandle
                if controller.characterHandle != 0 {
                    controller.runtimeConfigApplied = false
                    updated = rootMotionActive
                        ? physicsSystem.updateCharacterDisplacement(handle: controller.characterHandle,
                                                                    dt: fixedDelta,
                                                                    desiredDisplacement: rootHorizontalDisplacement,
                                                                    jumpRequested: jumpRequested)
                        : physicsSystem.updateCharacter(handle: controller.characterHandle,
                                                       dt: fixedDelta,
                                                       desiredVelocity: desiredVelocity,
                                                       jumpRequested: jumpRequested)
                }
            }
            guard updated,
                  let finalPosition = physicsSystem.characterPosition(handle: controller.characterHandle) else {
                scene.ecs.add(controller, to: entity)
                return
            }

            let resolvedTransform = TransformComponent(position: finalPosition,
                                                       rotation: yawRotation,
                                                       scale: worldTransform.scale)
            _ = scene.transformAuthority.setWorldTransform(entity: entity,
                                                           transform: resolvedTransform,
                                                           source: .characterController)

            let postGroundState = groundProvider.resolveGround(scene: scene,
                                                               physicsSystem: physicsSystem,
                                                               entity: entity,
                                                               controller: controller,
                                                               characterHandle: controller.characterHandle)
            controller.isGrounded = postGroundState.isGrounded
            controller.lastGroundBodyId = postGroundState.groundBodyId
            let actualVelocity = fixedDelta > 1.0e-6
                ? (finalPosition - startPosition) / fixedDelta
                : .zero
            controller.velocity = actualVelocity
            controller.lookInput = .zero
            let debugEnabled = isDebugDrawEnabled(entityId: entity.id)
            debugVisualizationByEntity[entity.id] = CharacterControllerDebugVisualization(enabled: debugEnabled,
                                                                                          groundNormal: postGroundState.groundNormal,
                                                                                          basisForward: forward,
                                                                                          basisRight: right)
            let debugDesiredVelocity = rootMotionActive && fixedDelta > 1.0e-6
                ? (rootHorizontalDisplacement / fixedDelta)
                : desiredVelocity
            let locomotionOutput = CharacterLocomotionOutput(desiredVelocity: debugDesiredVelocity,
                                                             actualVelocity: actualVelocity,
                                                             grounded: postGroundState.isGrounded,
                                                             groundNormal: postGroundState.groundNormal,
                                                             groundBodyId: postGroundState.groundBodyId,
                                                             rootMotionDeltaMagnitude: rootMotionDeltaMagnitude,
                                                             rootMotionEnabled: rootMotionEnabled,
                                                             rootMotionActive: rootMotionActive,
                                                             rootMotionStateName: rootMotionStateName)
            locomotionOutputsByEntity[entity.id] = locomotionOutput

            stepHook?.postStep(.init(scene: scene,
                                     entity: entity,
                                     fixedDelta: fixedDelta,
                                     locomotion: locomotionOutput,
                                     groundState: postGroundState))
            let updatedRotation = TransformMath.normalizedQuaternion(yawRotation)
            var interpolation = characterInterpolationStates[entity.id] ?? CharacterInterpolationState(prevPosition: finalPosition,
                                                                                                      currPosition: finalPosition,
                                                                                                      prevRotation: updatedRotation,
                                                                                                      currRotation: updatedRotation,
                                                                                                      initialized: false)
            if !interpolation.initialized {
                interpolation.prevPosition = startPosition
                interpolation.currPosition = finalPosition
                interpolation.prevRotation = updatedRotation
                interpolation.currRotation = updatedRotation
                interpolation.initialized = true
            } else {
                interpolation.prevPosition = interpolation.currPosition
                interpolation.prevRotation = interpolation.currRotation
                interpolation.currPosition = finalPosition
                interpolation.currRotation = updatedRotation
            }
            characterInterpolationStates[entity.id] = interpolation

            if let pivotEntityId = controller.cameraPivotEntityId,
               let pivotEntity = scene.ecs.entity(with: pivotEntityId),
               var pivotTransform = scene.ecs.get(TransformComponent.self, for: pivotEntity) {
                let pitchQuat = simd_quatf(angle: controller.pitchRadians, axis: SIMD3<Float>(1.0, 0.0, 0.0))
                pivotTransform.rotation = pitchQuat.vector
                _ = scene.transformAuthority.setLocalTransform(entity: pivotEntity,
                                                               transform: pivotTransform,
                                                               source: .characterController)
            }

            scene.ecs.add(controller, to: entity)
        }

        let staleCharacterEntities = characterHandlesByEntity.keys.filter { !activeEntityIDs.contains($0) }
        for entityId in staleCharacterEntities {
            if let handle = characterHandlesByEntity[entityId] {
                physicsSystem.destroyCharacter(handle: handle)
            }
            characterHandlesByEntity.removeValue(forKey: entityId)
            characterInterpolationStates.removeValue(forKey: entityId)
            renderWorldTransformCache.removeValue(forKey: entityId)
            locomotionOutputsByEntity.removeValue(forKey: entityId)
            debugVisualizationByEntity.removeValue(forKey: entityId)
        }
        characterJumpRequests.removeAll(keepingCapacity: true)
        characterLookRequests.removeAll(keepingCapacity: true)
    }

    public func onEntityDestroyed(_ entityId: UUID) {
        characterHandlesByEntity.removeValue(forKey: entityId)
        characterInterpolationStates.removeValue(forKey: entityId)
        renderWorldTransformCache.removeValue(forKey: entityId)
        locomotionOutputsByEntity.removeValue(forKey: entityId)
        debugVisualizationByEntity.removeValue(forKey: entityId)
    }

    public func prepareForPhysicsStart(scene: EngineScene) {
        scene.ecs.viewDeterministic(CharacterControllerComponent.self) { entity, _ in
            guard var controller = scene.ecs.get(CharacterControllerComponent.self, for: entity) else { return }
            controller.characterHandle = 0
            controller.runtimeConfigApplied = false
            scene.ecs.add(controller, to: entity)
        }
        characterHandlesByEntity.removeAll(keepingCapacity: true)
        characterInterpolationStates.removeAll(keepingCapacity: true)
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        locomotionOutputsByEntity.removeAll(keepingCapacity: true)
        debugVisualizationByEntity.removeAll(keepingCapacity: true)
    }

    public func destroyAllCharacters(using physicsSystem: PhysicsSystem) {
        for (_, handle) in characterHandlesByEntity {
            physicsSystem.destroyCharacter(handle: handle)
        }
        characterHandlesByEntity.removeAll(keepingCapacity: true)
        characterInterpolationStates.removeAll(keepingCapacity: true)
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        locomotionOutputsByEntity.removeAll(keepingCapacity: true)
    }

    public func resetForSceneApply() {
        characterHandlesByEntity.removeAll(keepingCapacity: true)
        characterInterpolationStates.removeAll(keepingCapacity: true)
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        locomotionOutputsByEntity.removeAll(keepingCapacity: true)
        debugVisualizationByEntity.removeAll(keepingCapacity: true)
        characterJumpRequests.removeAll(keepingCapacity: true)
        characterLookRequests.removeAll(keepingCapacity: true)
        characterSprintRequests.removeAll(keepingCapacity: true)
        characterMoveRequests.removeAll(keepingCapacity: true)
    }

    public func resetRuntimeInputState() {
        characterMoveRequests.removeAll(keepingCapacity: true)
        characterLookRequests.removeAll(keepingCapacity: true)
        characterSprintRequests.removeAll(keepingCapacity: true)
        characterJumpRequests.removeAll(keepingCapacity: true)
    }

    private func rebuildRenderWorldTransformCache(scene: EngineScene) {
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        guard !characterInterpolationStates.isEmpty else { return }

        let alpha = simd_clamp(renderInterpolationAlpha, 0.0, 1.0)
        for (entityId, interpolation) in characterInterpolationStates {
            guard interpolation.initialized,
                  let entity = scene.ecs.entity(with: entityId),
                  let controller = scene.ecs.get(CharacterControllerComponent.self, for: entity),
                  controller.isEnabled,
                  controller.interpolateSubtree,
                  scene.ecs.get(TransformComponent.self, for: entity) != nil else {
                continue
            }

            let prevQuat = simd_quatf(vector: interpolation.prevRotation)
            let currQuat = simd_quatf(vector: interpolation.currRotation)
            let interpolatedQuat = simd_slerp(prevQuat, currQuat, alpha)
            let interpolatedPos = simd_mix(interpolation.prevPosition, interpolation.currPosition, SIMD3<Float>(repeating: alpha))
            let rootScale = scene.ecs.worldTransform(for: entity).scale
            let rootRender = TransformComponent(position: interpolatedPos,
                                                rotation: TransformMath.normalizedQuaternion(interpolatedQuat.vector),
                                                scale: rootScale)
            renderWorldTransformCache[entity.id] = rootRender
            buildRenderWorldTransformCacheSubtree(scene: scene, root: entity, rootRenderTransform: rootRender)
        }
    }

    private func buildRenderWorldTransformCacheSubtree(scene: EngineScene,
                                                       root: Entity,
                                                       rootRenderTransform: TransformComponent) {
        var visited: Set<UUID> = [root.id]
        var queue: [(entity: Entity, world: TransformComponent)] = [(root, rootRenderTransform)]
        var queueIndex = 0

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1
            let parentMatrix = TransformMath.makeMatrix(position: current.world.position,
                                                        rotation: current.world.rotation,
                                                        scale: current.world.scale)
            for child in scene.ecs.getChildren(current.entity) {
                if visited.contains(child.id) {
                    continue
                }
                guard let childLocal = scene.ecs.get(TransformComponent.self, for: child) else { continue }
                let localMatrix = TransformMath.makeMatrix(position: childLocal.position,
                                                           rotation: childLocal.rotation,
                                                           scale: childLocal.scale)
                let childWorldMatrix = parentMatrix * localMatrix
                let decomposed = TransformMath.decomposeMatrix(childWorldMatrix)
                let childRender = TransformComponent(position: decomposed.position,
                                                     rotation: decomposed.rotation,
                                                     scale: decomposed.scale)
                renderWorldTransformCache[child.id] = childRender
                visited.insert(child.id)
                queue.append((child, childRender))
            }
        }
    }

    private func sanitizeRootMotionDelta(_ delta: RootMotionDelta) -> RootMotionDelta {
        let position = simd3IsFinite(delta.deltaPos) ? delta.deltaPos : .zero
        let rotation: SIMD4<Float>
        if simd4IsFinite(delta.deltaRot), simd_length_squared(delta.deltaRot) > 1.0e-8 {
            rotation = TransformMath.normalizedQuaternion(delta.deltaRot)
        } else {
            rotation = TransformMath.identityQuaternion
        }
        return RootMotionDelta(deltaPos: position, deltaRot: rotation)
    }

    private func simd3IsFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private func simd4IsFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private struct ResolvedRootMotion {
        let delta: RootMotionDelta
        let usesRootMotion: Bool
        let enableRootMotion: Bool
        let currentStateName: String
    }

    private func resolveRootMotionForController(scene: EngineScene,
                                                entity: Entity,
                                                controller: CharacterControllerComponent) -> ResolvedRootMotion? {
        func readRootMotion(from target: Entity) -> ResolvedRootMotion? {
            guard let animator = scene.ecs.get(AnimatorComponent.self, for: target),
                  let poseState = animator.poseRuntimeState else { return nil }
            return ResolvedRootMotion(delta: poseState.rootMotionDelta,
                                      usesRootMotion: poseState.usesRootMotion,
                                      enableRootMotion: animator.enableRootMotion,
                                      currentStateName: poseState.currentStateName)
        }
        func firstRootMotionInSubtree(root: Entity) -> ResolvedRootMotion? {
            var queue: [Entity] = [root]
            var cursor = 0
            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                if let motion = readRootMotion(from: current) {
                    return motion
                }
                let children = scene.ecs.getChildren(current)
                if !children.isEmpty {
                    queue.append(contentsOf: children)
                }
            }
            return nil
        }

        if let direct = readRootMotion(from: entity) {
            return direct
        }
        if let visualID = controller.visualEntityId,
           let visualEntity = scene.ecs.entity(with: visualID) {
            if let visual = readRootMotion(from: visualEntity) {
                return visual
            }
            if let nestedVisual = firstRootMotionInSubtree(root: visualEntity) {
                return nestedVisual
            }
        }
        if let nested = firstRootMotionInSubtree(root: entity) {
            return nested
        }
        return nil
    }
}
private struct DefaultCharacterGroundProvider: CharacterGroundProvider {
    func resolveGround(scene _: EngineScene,
                       physicsSystem: PhysicsSystem,
                       entity _: Entity,
                       controller _: CharacterControllerComponent,
                       characterHandle: UInt64) -> CharacterGroundState {
        let grounded = physicsSystem.characterIsGrounded(handle: characterHandle)
        let groundBody = grounded ? physicsSystem.characterGroundBodyId(handle: characterHandle) : 0
        let groundNormal = physicsSystem.characterGroundNormal(handle: characterHandle)
        let groundVelocity = groundBody != 0 ? (physicsSystem.bodyVelocity(bodyId: groundBody) ?? .zero) : .zero
        let movingPlatform = simd_length_squared(groundVelocity) > 1.0e-6
        return CharacterGroundState(isGrounded: grounded,
                                    groundNormal: groundNormal,
                                    groundBodyId: groundBody,
                                    groundVelocity: groundVelocity,
                                    isMovingPlatform: movingPlatform,
                                    terrainSample: nil)
    }
}
