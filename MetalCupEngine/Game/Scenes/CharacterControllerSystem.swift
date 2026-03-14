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
    private struct LocalMovementIntent {
        let raw: SIMD2<Float>
        let direction: SIMD2<Float>
        let magnitude: Float
    }

    private struct PlanarMovementBasis {
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
    }

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
    private struct RuntimeAnimationDiagnosticsState {
        var currentState: String
        var nextState: String
        var rootMotionActive: Bool
        var grounded: Bool
        var jumpTriggerLatched: Bool
        var translationSourceJointIndex: Int
        var rotationSourceJointIndex: Int
        var consumeJointIndex: Int
    }
    private var runtimeDiagnosticsByEntity: [UUID: RuntimeAnimationDiagnosticsState] = [:]
    private var loggedRootMotionFailureKeys: Set<String> = []
    private var timelineSecondsByEntity: [UUID: Float] = [:]
    private var jumpStartEntryTimeByEntity: [UUID: Float] = [:]
    private var jumpImpulseTimeByEntity: [UUID: Float] = [:]
    private var lastCardinalIntentKeyByEntity: [UUID: String] = [:]
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

            let timelineSeconds = (timelineSecondsByEntity[entity.id] ?? 0.0) + fixedDelta
            timelineSecondsByEntity[entity.id] = timelineSeconds

            let requestedInput = characterMoveRequests[entity.id] ?? controller.moveInput
            let lookInput = characterLookRequests[entity.id] ?? controller.lookInput
            let sprinting = characterSprintRequests[entity.id] ?? controller.wantsSprint
            let movementIntent = makeLocalMovementIntent(from: requestedInput)
            let rawInputIntent = movementIntent.raw
            let movementMagnitude = movementIntent.magnitude
            let movementDirectionLocal = movementIntent.direction
            let movementIntentLocal = movementIntent.raw
            controller.moveInput = movementIntentLocal
            controller.lookInput = lookInput
            controller.wantsSprint = sprinting

            var rootMotionDelta = RootMotionDelta()
            var rootMotionDeltaMagnitude: Float = 0.0
            var rootMotionDeltaRotationMagnitude: Float = 0.0
            var rootMotionEnabled = false
            var rootMotionUsesCurrentState = false
            var rootMotionActive = false
            var rootMotionStateName = ""
            var nextStateName = ""
            var jumpTriggerLatched = false
            var jumpStateSampleTime: Float = 0.0
            var jumpStateNormalizedTime: Float = 0.0
            var rootMotionTranslationSourceJointName = ""
            var rootMotionTranslationSourceJointIndex = -1
            var rootMotionRotationSourceJointName = ""
            var rootMotionRotationSourceJointIndex = -1
            var rootMotionConsumeJointName = ""
            var rootMotionConsumeJointIndex = -1
            var rootMotionSourceEntityID: UUID? = nil
            var rootMotionSourceWorldScale: Float = 1.0
            if let rootMotion = resolveRootMotionForController(scene: scene, entity: entity, controller: controller) {
                rootMotionEnabled = rootMotion.enableRootMotion
                rootMotionUsesCurrentState = rootMotion.usesRootMotion
                rootMotionActive = rootMotion.enableRootMotion && rootMotion.usesRootMotion
                rootMotionStateName = rootMotion.currentStateName
                nextStateName = rootMotion.nextStateName
                jumpTriggerLatched = rootMotion.jumpTriggerLatched
                jumpStateSampleTime = rootMotion.sampleTime
                jumpStateNormalizedTime = runtimeStatePlaybackNormalized(sampleTime: rootMotion.sampleTime,
                                                                        duration: rootMotion.sampleDuration)
                rootMotionDelta = sanitizeRootMotionDelta(rootMotion.delta)
                rootMotionDeltaMagnitude = simd_length(rootMotionDelta.deltaPos)
                rootMotionDeltaRotationMagnitude = rootMotionRotationMagnitudeRadians(rootMotionDelta)
                rootMotionTranslationSourceJointName = rootMotion.translationSourceJointName
                rootMotionTranslationSourceJointIndex = rootMotion.translationSourceJointIndex
                rootMotionRotationSourceJointName = rootMotion.rotationSourceJointName
                rootMotionRotationSourceJointIndex = rootMotion.rotationSourceJointIndex
                rootMotionConsumeJointName = rootMotion.consumeJointName
                rootMotionConsumeJointIndex = rootMotion.consumeJointIndex
                rootMotionSourceEntityID = rootMotion.sourceEntityID
                rootMotionSourceWorldScale = rootMotion.sourceWorldScale
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
            let yawDelta = -lookInput.x * lookSensitivity
            controller.yawRadians += yawDelta
            let minPitch = controller.minPitchDegrees * (.pi / 180.0)
            let maxPitch = controller.maxPitchDegrees * (.pi / 180.0)
            controller.pitchRadians = simd_clamp(controller.pitchRadians + lookInput.y * lookSensitivity,
                                                 min(minPitch, maxPitch),
                                                 max(minPitch, maxPitch))
            controller.lookInput = .zero

            let upAxis = SIMD3<Float>(0.0, 1.0, 0.0)
            let cameraYawQuat = simd_quatf(angle: controller.yawRadians, axis: upAxis)
            var characterYawQuat = cameraYawQuat
            if rootMotionActive, rootMotionDeltaRotationMagnitude > 1.0e-5 {
                characterYawQuat = simd_normalize(simd_quatf(vector: rootMotionDelta.deltaRot) * characterYawQuat)
                var rootedForward = characterYawQuat.act(characterForwardAxis)
                rootedForward.y = 0.0
                if simd_length_squared(rootedForward) > 1.0e-6 {
                    rootedForward = simd_normalize(rootedForward)
                    controller.yawRadians = atan2(rootedForward.x, rootedForward.z)
                }
            }
            let yawRotation = TransformMath.normalizedQuaternion(characterYawQuat.vector)

            let normalizedInput = movementDirectionLocal

            let basis = makePlanarMovementBasis(cameraYawQuat: cameraYawQuat, fallbackForward: characterForwardAxis)
            let forward = basis.forward
            let right = basis.right

            var desiredHorizontal = projectLocalIntentDirectionToWorld(normalizedInput, basis: basis)
            if simd_length_squared(desiredHorizontal) > 1.0e-6 {
                desiredHorizontal = simd_normalize(desiredHorizontal)
            }
            let speedMultiplier = sprinting ? max(1.0, controller.sprintMultiplier) : 1.0
            let horizontalVelocity = desiredHorizontal * max(0.0, controller.moveSpeed) * speedMultiplier
            let desiredHorizontalVelocity = SIMD3<Float>(horizontalVelocity.x, 0.0, horizontalVelocity.z)
            let worldTransform = scene.ecs.worldTransform(for: entity)
            let controllerScale = worldTransform.scale.x
            let animatorVisualScale = rootMotionSourceWorldScale
            let rawLocalRootDelta = SIMD3<Float>(rootMotionDelta.deltaPos.x, 0.0, rootMotionDelta.deltaPos.z)
            let locomotionStateActive = rootMotionStateName.caseInsensitiveCompare("Locomotion") == .orderedSame
            let rootPlanarMagnitude = simd_length(SIMD2<Float>(rawLocalRootDelta.x, rawLocalRootDelta.z))
            let localRootDelta: SIMD3<Float>
            if locomotionStateActive {
                let localIntent = SIMD2<Float>(normalizedInput.x, normalizedInput.y)
                if simd_length_squared(localIntent) > 1.0e-10, rootPlanarMagnitude > 1.0e-10 {
                    let intentDirection = simd_normalize(localIntent)
                    let correctedX = -intentDirection.x
                    localRootDelta = SIMD3<Float>(correctedX * rootPlanarMagnitude,
                                                  0.0,
                                                  intentDirection.y * rootPlanarMagnitude)
                } else {
                    localRootDelta = .zero
                }
            } else {
                localRootDelta = rawLocalRootDelta
            }
            let scaledRootDelta = localRootDelta * animatorVisualScale
            let worldRootDelta = projectLocalRootDeltaToWorld(scaledRootDelta, basis: basis)
            var rootHorizontalDisplacement = SIMD3<Float>(worldRootDelta.x, 0.0, worldRootDelta.z)
            var usedRootMotionFallbackDisplacement = false
            if rootMotionActive && simd_length_squared(rootHorizontalDisplacement) <= 1.0e-10 {
                if simd_length_squared(movementDirectionLocal) > 1.0e-10 {
                    var fallbackDirection = projectLocalIntentDirectionToWorld(movementDirectionLocal, basis: basis)
                    if simd_length_squared(fallbackDirection) > 1.0e-6 {
                        fallbackDirection = simd_normalize(fallbackDirection)
                    }
                    let fallbackVelocity = fallbackDirection * max(0.0, controller.moveSpeed) * speedMultiplier
                    rootHorizontalDisplacement = fallbackVelocity * fixedDelta
                    usedRootMotionFallbackDisplacement = true
                }
            }
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
            let movingJumpLeadTime: Float = 0.08
            let standingJumpLeadTime: Float = 0.18
            let jumpBufferWindow: Float = 0.12
            let movementIntentMagnitude = simd_length(movementIntentLocal)
            let jumpStartLeadTime = movementIntentMagnitude < 0.2 ? standingJumpLeadTime : movingJumpLeadTime
            controller.jumpBufferTimer = max(0.0, controller.jumpBufferTimer - fixedDelta)
            if characterJumpRequests.contains(entity.id) {
                controller.jumpBufferTimer = jumpBufferWindow + jumpStartLeadTime
                EngineLoggerContext.log(
                    "AnimCC jump input entity=\(entity.id.uuidString) jumpType=\(movementIntentMagnitude < 0.2 ? "standing" : "moving") currentState=\(rootMotionStateName.isEmpty ? "<none>" : rootMotionStateName) nextState=\(nextStateName.isEmpty ? "<none>" : nextStateName) grounded=\(wasGrounded) jumpTriggerLatched=\(jumpTriggerLatched) jumpLeadTime=\(jumpStartLeadTime)",
                    level: .debug,
                    category: .scene
                )
            }
            let jumpImpulseReady = controller.jumpBufferTimer > 0.0 && controller.jumpBufferTimer <= jumpBufferWindow
            let standingJump = movementIntentMagnitude < 0.2
            let inJumpStartState = rootMotionStateName.caseInsensitiveCompare("JumpStart") == .orderedSame
            let jumpStartReadyForImpulse = !standingJump
                || ((inJumpStartState && (jumpStateNormalizedTime >= 0.08 || jumpStateSampleTime >= 0.10))
                    || controller.jumpBufferTimer <= 0.01)
            let jumpRequested = wasGrounded
                && !controller.jumpConsumedOnGroundContact
                && jumpImpulseReady
                && jumpStartReadyForImpulse
            var jumpTriggerConsumedThisFrame = false
            if jumpRequested {
                controller.jumpConsumedOnGroundContact = true
                controller.jumpBufferTimer = 0.0
                jumpTriggerConsumedThisFrame = true
                jumpImpulseTimeByEntity[entity.id] = timelineSeconds
                EngineLoggerContext.log(
                    "AnimCC jump impulse entity=\(entity.id.uuidString) state=\(rootMotionStateName.isEmpty ? "<none>" : rootMotionStateName) grounded=\(wasGrounded) impulseTime=\(timelineSeconds)",
                    level: .debug,
                    category: .scene
                )
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
            let appliedDisplacement = finalPosition - startPosition
            let appliedDisplacementMagnitude = simd_length(appliedDisplacement)
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

            let currentDiagnostics = RuntimeAnimationDiagnosticsState(currentState: rootMotionStateName,
                                                                     nextState: nextStateName,
                                                                     rootMotionActive: rootMotionActive,
                                                                     grounded: postGroundState.isGrounded,
                                                                     jumpTriggerLatched: jumpTriggerLatched,
                                                                     translationSourceJointIndex: rootMotionTranslationSourceJointIndex,
                                                                     rotationSourceJointIndex: rootMotionRotationSourceJointIndex,
                                                                     consumeJointIndex: rootMotionConsumeJointIndex)
            let previousDiagnostics = runtimeDiagnosticsByEntity[entity.id]
            let didStateChange = previousDiagnostics?.currentState != currentDiagnostics.currentState
                || previousDiagnostics?.nextState != currentDiagnostics.nextState
            let didRootMotionToggle = previousDiagnostics?.rootMotionActive != currentDiagnostics.rootMotionActive
            let didRootMotionChannelChange = previousDiagnostics?.translationSourceJointIndex != currentDiagnostics.translationSourceJointIndex
                || previousDiagnostics?.rotationSourceJointIndex != currentDiagnostics.rotationSourceJointIndex
                || previousDiagnostics?.consumeJointIndex != currentDiagnostics.consumeJointIndex
            if didStateChange || didRootMotionToggle || didRootMotionChannelChange {
                let playbackSummary: String
                if ["JumpStart", "Airborne", "Land"].contains(rootMotionStateName) {
                    playbackSummary = " playbackTime=\(jumpStateSampleTime) normalized=\(jumpStateNormalizedTime)"
                } else {
                    playbackSummary = ""
                }
                EngineLoggerContext.log(
                    "AnimCC state entity=\(entity.id.uuidString) currentState=\(rootMotionStateName.isEmpty ? "<none>" : rootMotionStateName) nextState=\(nextStateName.isEmpty ? "<none>" : nextStateName) usesRootMotion=\(rootMotionUsesCurrentState) rootMotionActive=\(rootMotionActive) translationSourceJoint=\(rootMotionTranslationSourceJointName.isEmpty ? "<none>" : rootMotionTranslationSourceJointName)#\(rootMotionTranslationSourceJointIndex) rotationSourceJoint=\(rootMotionRotationSourceJointName.isEmpty ? "<none>" : rootMotionRotationSourceJointName)#\(rootMotionRotationSourceJointIndex) consumeJoint=\(rootMotionConsumeJointName.isEmpty ? "<none>" : rootMotionConsumeJointName)#\(rootMotionConsumeJointIndex) controllerScale=\(controllerScale) animatorVisualScale=\(animatorVisualScale) animatorSourceEntity=\(rootMotionSourceEntityID?.uuidString ?? "<none>") localRootDelta=\(localRootDelta) scaledRootDelta=\(scaledRootDelta) worldRootDelta=\(worldRootDelta) rootDeltaTranslationMag=\(rootMotionDeltaMagnitude) appliedWorldDelta=\(rootHorizontalDisplacement) rawInputDirection=\(rawInputIntent) normalizedDirection=\(normalizedInput) movementMagnitude=\(movementMagnitude) movementDirection=\(desiredHorizontal) forward=\(forward) right=\(right) cameraYaw=\(controller.yawRadians) rootDeltaRotationMag=\(rootMotionDeltaRotationMagnitude) appliedDisplacementMag=\(appliedDisplacementMagnitude) fallbackDisplacement=\(usedRootMotionFallbackDisplacement) grounded=\(postGroundState.isGrounded) jumpTriggerLatched=\(jumpTriggerLatched) jumpTriggerConsumed=\(jumpTriggerConsumedThisFrame)\(playbackSummary)",
                    level: .debug,
                    category: .scene
                )
            }
            runtimeDiagnosticsByEntity[entity.id] = currentDiagnostics

            let intentMagnitude = simd_length(normalizedInput)
            let cardinalIntentKey: String = {
                guard intentMagnitude >= 0.2 else { return "Idle" }
                let horizontal = normalizedInput.x >= 0.5 ? "D" : (normalizedInput.x <= -0.5 ? "A" : "")
                let vertical = normalizedInput.y >= 0.5 ? "W" : (normalizedInput.y <= -0.5 ? "S" : "")
                let key = vertical + horizontal
                return key.isEmpty ? "Analog" : key
            }()
            let previousCardinalIntent = lastCardinalIntentKeyByEntity[entity.id]
            let keyboardCardinals: Set<String> = ["W", "A", "S", "D", "WA", "WD", "SA", "SD"]
            if rootMotionStateName.caseInsensitiveCompare("Locomotion") == .orderedSame,
               keyboardCardinals.contains(cardinalIntentKey),
               previousCardinalIntent != cardinalIntentKey {
                lastCardinalIntentKeyByEntity[entity.id] = cardinalIntentKey
                let dotForward = simd_dot(rootHorizontalDisplacement, forward)
                let dotRight = simd_dot(rootHorizontalDisplacement, right)
                let validation = validateMovementConvention(intentKey: cardinalIntentKey,
                                                            rawInput: rawInputIntent,
                                                            normalizedDirection: normalizedInput,
                                                            localRootDelta: localRootDelta,
                                                            forward: forward,
                                                            right: right,
                                                            worldDelta: rootHorizontalDisplacement,
                                                            usedFallbackDisplacement: usedRootMotionFallbackDisplacement)
                EngineLoggerContext.log(
                    "AnimCC direction validation entity=\(entity.id.uuidString) intent=\(cardinalIntentKey) rawInput=\(rawInputIntent) localIntentBeforeNormalization=\(movementIntentLocal) normalizedLocalDirection=\(normalizedInput) movementMagnitude=\(movementMagnitude) localRootDelta=\(localRootDelta) forward=\(forward) right=\(right) worldDelta=\(rootHorizontalDisplacement) dotWorldForward=\(dotForward) dotWorldRight=\(dotRight) fallbackDisplacement=\(usedRootMotionFallbackDisplacement) validation=\(validation)",
                    level: .debug,
                    category: .scene
                )
            }

            if didStateChange,
               rootMotionStateName.caseInsensitiveCompare("JumpStart") == .orderedSame,
               previousDiagnostics?.currentState.caseInsensitiveCompare("JumpStart") != .orderedSame {
                jumpStartEntryTimeByEntity[entity.id] = timelineSeconds
                let key = "\(entity.id.uuidString)|jumpLiftOff"
                loggedRootMotionFailureKeys.remove(key)
                EngineLoggerContext.log(
                    "AnimCC JumpStart active entity=\(entity.id.uuidString) entryTime=\(timelineSeconds) playbackTime=\(jumpStateSampleTime) normalized=\(jumpStateNormalizedTime)",
                    level: .debug,
                    category: .scene
                )
            }
            if rootMotionStateName.caseInsensitiveCompare("JumpStart") == .orderedSame,
               wasGrounded,
               !postGroundState.isGrounded,
               let jumpStartEntry = jumpStartEntryTimeByEntity[entity.id] {
                let key = "\(entity.id.uuidString)|jumpLiftOff"
                if !loggedRootMotionFailureKeys.contains(key) {
                    loggedRootMotionFailureKeys.insert(key)
                    let jumpStartVisibleDuration = timelineSeconds - jumpStartEntry
                    let impulseDelay = jumpImpulseTimeByEntity[entity.id].map { timelineSeconds - $0 } ?? -1.0
                    EngineLoggerContext.log(
                        "AnimCC JumpStart liftoff entity=\(entity.id.uuidString) jumpStartDurationBeforeUngrounded=\(jumpStartVisibleDuration) impulseToUngrounded=\(impulseDelay)",
                        level: .debug,
                        category: .scene
                    )
                }
            }
            if didStateChange,
               rootMotionStateName.caseInsensitiveCompare("Airborne") == .orderedSame,
               previousDiagnostics?.currentState.caseInsensitiveCompare("Airborne") != .orderedSame {
                let jumpStartDuration = jumpStartEntryTimeByEntity[entity.id].map { timelineSeconds - $0 } ?? -1.0
                let impulseToAirborne = jumpImpulseTimeByEntity[entity.id].map { timelineSeconds - $0 } ?? -1.0
                EngineLoggerContext.log(
                    "AnimCC Airborne transition entity=\(entity.id.uuidString) jumpStartToAirborne=\(jumpStartDuration) impulseToAirborne=\(impulseToAirborne) grounded=\(postGroundState.isGrounded)",
                    level: .debug,
                    category: .scene
                )
            }

            if abs(animatorVisualScale - 1.0) > 0.25 {
                let scaleKey = "\(entity.id.uuidString)|scaleRootMotionVerification"
                if !loggedRootMotionFailureKeys.contains(scaleKey) {
                    loggedRootMotionFailureKeys.insert(scaleKey)
                    EngineLoggerContext.log(
                        "AnimCC scale verification entity=\(entity.id.uuidString) controllerScale=\(controllerScale) animatorVisualScale=\(animatorVisualScale) animatorSourceEntity=\(rootMotionSourceEntityID?.uuidString ?? "<none>") localRootDelta=\(localRootDelta) scaledRootDelta=\(scaledRootDelta) worldRootDelta=\(worldRootDelta) appliedDisplacementMag=\(appliedDisplacementMagnitude) fallbackDisplacement=\(usedRootMotionFallbackDisplacement)",
                        level: .debug,
                        category: .scene
                    )
                }
            }

            if rootMotionStateName.caseInsensitiveCompare("Locomotion") == .orderedSame,
               rootMotionEnabled,
               !rootMotionActive {
                let failureKey = "\(entity.id.uuidString)|locomotionRootMotionInactive"
                if !loggedRootMotionFailureKeys.contains(failureKey) {
                    loggedRootMotionFailureKeys.insert(failureKey)
                    EngineLoggerContext.log(
                        "AnimCC root motion inactive during locomotion entity=\(entity.id.uuidString) currentState=\(rootMotionStateName) nextState=\(nextStateName)",
                        level: .warning,
                        category: .scene
                    )
                }
            }
            if rootMotionActive,
               rootMotionDeltaMagnitude > 1.0e-4,
               appliedDisplacementMagnitude < 1.0e-5 {
                let failureKey = "\(entity.id.uuidString)|\(rootMotionStateName)|noAppliedDisplacement"
                if !loggedRootMotionFailureKeys.contains(failureKey) {
                    loggedRootMotionFailureKeys.insert(failureKey)
                    EngineLoggerContext.log(
                        "AnimCC root motion extraction/application mismatch entity=\(entity.id.uuidString) currentState=\(rootMotionStateName) rootDeltaTranslationMag=\(rootMotionDeltaMagnitude) appliedDisplacementMag=\(appliedDisplacementMagnitude) grounded=\(postGroundState.isGrounded)",
                        level: .warning,
                        category: .scene
                    )
                }
            }

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
            runtimeDiagnosticsByEntity.removeValue(forKey: entityId)
            timelineSecondsByEntity.removeValue(forKey: entityId)
            jumpStartEntryTimeByEntity.removeValue(forKey: entityId)
            jumpImpulseTimeByEntity.removeValue(forKey: entityId)
            lastCardinalIntentKeyByEntity.removeValue(forKey: entityId)
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
        runtimeDiagnosticsByEntity.removeValue(forKey: entityId)
        timelineSecondsByEntity.removeValue(forKey: entityId)
        jumpStartEntryTimeByEntity.removeValue(forKey: entityId)
        jumpImpulseTimeByEntity.removeValue(forKey: entityId)
        lastCardinalIntentKeyByEntity.removeValue(forKey: entityId)
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
        runtimeDiagnosticsByEntity.removeAll(keepingCapacity: true)
        timelineSecondsByEntity.removeAll(keepingCapacity: true)
        jumpStartEntryTimeByEntity.removeAll(keepingCapacity: true)
        jumpImpulseTimeByEntity.removeAll(keepingCapacity: true)
        lastCardinalIntentKeyByEntity.removeAll(keepingCapacity: true)
        loggedRootMotionFailureKeys.removeAll(keepingCapacity: true)
    }

    public func destroyAllCharacters(using physicsSystem: PhysicsSystem) {
        for (_, handle) in characterHandlesByEntity {
            physicsSystem.destroyCharacter(handle: handle)
        }
        characterHandlesByEntity.removeAll(keepingCapacity: true)
        characterInterpolationStates.removeAll(keepingCapacity: true)
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        locomotionOutputsByEntity.removeAll(keepingCapacity: true)
        runtimeDiagnosticsByEntity.removeAll(keepingCapacity: true)
        timelineSecondsByEntity.removeAll(keepingCapacity: true)
        jumpStartEntryTimeByEntity.removeAll(keepingCapacity: true)
        jumpImpulseTimeByEntity.removeAll(keepingCapacity: true)
        lastCardinalIntentKeyByEntity.removeAll(keepingCapacity: true)
        loggedRootMotionFailureKeys.removeAll(keepingCapacity: true)
    }

    public func resetForSceneApply() {
        characterHandlesByEntity.removeAll(keepingCapacity: true)
        characterInterpolationStates.removeAll(keepingCapacity: true)
        renderWorldTransformCache.removeAll(keepingCapacity: true)
        locomotionOutputsByEntity.removeAll(keepingCapacity: true)
        debugVisualizationByEntity.removeAll(keepingCapacity: true)
        runtimeDiagnosticsByEntity.removeAll(keepingCapacity: true)
        timelineSecondsByEntity.removeAll(keepingCapacity: true)
        jumpStartEntryTimeByEntity.removeAll(keepingCapacity: true)
        jumpImpulseTimeByEntity.removeAll(keepingCapacity: true)
        lastCardinalIntentKeyByEntity.removeAll(keepingCapacity: true)
        loggedRootMotionFailureKeys.removeAll(keepingCapacity: true)
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
        runtimeDiagnosticsByEntity.removeAll(keepingCapacity: true)
        timelineSecondsByEntity.removeAll(keepingCapacity: true)
        jumpStartEntryTimeByEntity.removeAll(keepingCapacity: true)
        jumpImpulseTimeByEntity.removeAll(keepingCapacity: true)
        lastCardinalIntentKeyByEntity.removeAll(keepingCapacity: true)
        loggedRootMotionFailureKeys.removeAll(keepingCapacity: true)
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
        let nextStateName: String
        let jumpTriggerLatched: Bool
        let sampleTime: Float
        let sampleDuration: Float
        let translationSourceJointName: String
        let translationSourceJointIndex: Int
        let rotationSourceJointName: String
        let rotationSourceJointIndex: Int
        let consumeJointName: String
        let consumeJointIndex: Int
        let sourceEntityID: UUID
        let sourceWorldScale: Float
    }

    private func resolveRootMotionForController(scene: EngineScene,
                                                entity: Entity,
                                                controller: CharacterControllerComponent) -> ResolvedRootMotion? {
        let assets = scene.engineContext?.assets
        func readRootMotion(from target: Entity) -> ResolvedRootMotion? {
            guard let animator = scene.ecs.get(AnimatorComponent.self, for: target),
                  let poseState = animator.poseRuntimeState else { return nil }
            let graph = animator.graphHandle.flatMap { assets?.compiledAnimationGraph(handle: $0) }
            let runtimeState = animator.graphRuntimeState
            var stateNameByID: [UUID: String] = [:]
            var stateByID: [UUID: AnimationGraphStateDefinition] = [:]
            if let graph {
                for node in graph.nodes {
                    guard let machine = node.stateMachine else { continue }
                    for state in machine.states {
                        stateNameByID[state.id] = state.name
                        stateByID[state.id] = state
                    }
                }
            }
            let currentStateID = runtimeState?.stateMachineCurrentStateByNodeID
                .sorted(by: { $0.key.uuidString < $1.key.uuidString })
                .first?.value
            let nextStateID = runtimeState?.stateMachineNextStateByNodeID
                .sorted(by: { $0.key.uuidString < $1.key.uuidString })
                .first?.value
            let resolvedCurrentStateName = poseState.currentStateName.isEmpty
                ? (currentStateID.flatMap { stateNameByID[$0] } ?? "")
                : poseState.currentStateName
            let resolvedNextStateName = nextStateID.flatMap { stateNameByID[$0] } ?? ""
            let jumpTriggerLatched: Bool = {
                guard let graph, let runtimeState, let jumpIndex = graph.parameterIndexByName["jumpTrigger"] else { return false }
                guard jumpIndex >= 0, jumpIndex < runtimeState.triggerParameterValues.count else { return false }
                return runtimeState.triggerParameterValues[jumpIndex] || runtimeState.triggerLatchedParameterIndices.contains(jumpIndex)
            }()
            let stateDuration: Float = {
                if let currentStateID, let clipHandle = stateByID[currentStateID]?.clipHandle,
                   let clip = assets?.animationClip(handle: clipHandle) {
                    return clip.durationSeconds
                }
                if let clipHandle = animator.clipHandle, let clip = assets?.animationClip(handle: clipHandle) {
                    return clip.durationSeconds
                }
                return 0.0
            }()
            let sourceScale = scene.ecs.worldTransform(for: target).scale.x
            return ResolvedRootMotion(delta: poseState.rootMotionDelta,
                                      usesRootMotion: poseState.usesRootMotion,
                                      enableRootMotion: animator.enableRootMotion,
                                      currentStateName: resolvedCurrentStateName,
                                      nextStateName: resolvedNextStateName,
                                      jumpTriggerLatched: jumpTriggerLatched,
                                      sampleTime: poseState.sampleTime,
                                      sampleDuration: max(0.0, stateDuration),
                                      translationSourceJointName: poseState.rootMotionTranslationBoneName,
                                      translationSourceJointIndex: poseState.rootMotionTranslationJointIndex,
                                      rotationSourceJointName: poseState.rootMotionRotationBoneName,
                                      rotationSourceJointIndex: poseState.rootMotionRotationJointIndex,
                                      consumeJointName: poseState.rootMotionConsumeBoneName,
                                      consumeJointIndex: poseState.rootMotionConsumeJointIndex,
                                      sourceEntityID: target.id,
                                      sourceWorldScale: sourceScale)
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

    private func rootMotionRotationMagnitudeRadians(_ delta: RootMotionDelta) -> Float {
        let q = simd_normalize(simd_quatf(vector: TransformMath.normalizedQuaternion(delta.deltaRot)))
        let clamped = simd_clamp(abs(q.real), 0.0, 1.0)
        return 2.0 * acos(clamped)
    }

    private func runtimeStatePlaybackNormalized(sampleTime: Float, duration: Float) -> Float {
        guard duration > 1.0e-5 else { return 0.0 }
        return simd_clamp(sampleTime / duration, 0.0, 1.0)
    }

    private func makeLocalMovementIntent(from rawInput: SIMD2<Float>) -> LocalMovementIntent {
        let magnitude = simd_length(rawInput)
        let direction = magnitude > 1.0e-5 ? (rawInput / magnitude) : .zero
        return LocalMovementIntent(raw: rawInput, direction: direction, magnitude: magnitude)
    }

    private func makePlanarMovementBasis(cameraYawQuat: simd_quatf,
                                         fallbackForward: SIMD3<Float>) -> PlanarMovementBasis {
        var forward = cameraYawQuat.act(fallbackForward)
        forward.y = 0.0
        if simd_length_squared(forward) > 1.0e-6 {
            forward = simd_normalize(forward)
        } else {
            forward = fallbackForward
        }

        var right = simd_cross(SIMD3<Float>(0.0, 1.0, 0.0), forward)
        if simd_length_squared(right) > 1.0e-6 {
            right = simd_normalize(right)
        } else {
            right = SIMD3<Float>(1.0, 0.0, 0.0)
        }
        return PlanarMovementBasis(forward: forward, right: right)
    }

    private func projectLocalIntentDirectionToWorld(_ localDirection: SIMD2<Float>,
                                                    basis: PlanarMovementBasis) -> SIMD3<Float> {
        (basis.right * localDirection.x) + (basis.forward * localDirection.y)
    }

    private func projectLocalRootDeltaToWorld(_ localRootDelta: SIMD3<Float>,
                                              basis: PlanarMovementBasis) -> SIMD3<Float> {
        (basis.right * localRootDelta.x) + (basis.forward * localRootDelta.z)
    }

    private func expectedDirectionSigns(intentKey: String) -> (forwardPositive: Bool?, rightPositive: Bool?) {
        switch intentKey {
        case "W": return (true, nil)
        case "S": return (false, nil)
        case "A": return (nil, false)
        case "D": return (nil, true)
        case "WA": return (true, false)
        case "WD": return (true, true)
        case "SA": return (false, false)
        case "SD": return (false, true)
        default: return (nil, nil)
        }
    }

    private func signedExpectationPass(value: Float,
                                       expectedPositive: Bool?,
                                       tolerance: Float = 1.0e-4) -> Bool {
        guard let expectedPositive else { return true }
        return expectedPositive ? (value > tolerance) : (value < -tolerance)
    }

    private func validateMovementConvention(intentKey: String,
                                            rawInput: SIMD2<Float>,
                                            normalizedDirection: SIMD2<Float>,
                                            localRootDelta: SIMD3<Float>,
                                            forward: SIMD3<Float>,
                                            right: SIMD3<Float>,
                                            worldDelta: SIMD3<Float>,
                                            usedFallbackDisplacement: Bool) -> String {
        let expected = expectedDirectionSigns(intentKey: intentKey)
        let rawInputPass = signedExpectationPass(value: rawInput.y, expectedPositive: expected.forwardPositive)
            && signedExpectationPass(value: rawInput.x, expectedPositive: expected.rightPositive)
        if !rawInputPass {
            return "FAIL(stage=inputMapping)"
        }

        let normalizedPass = signedExpectationPass(value: normalizedDirection.y, expectedPositive: expected.forwardPositive)
            && signedExpectationPass(value: normalizedDirection.x, expectedPositive: expected.rightPositive)
        if !normalizedPass {
            return "FAIL(stage=localDirectionNormalization)"
        }

        let localRootMagnitude = simd_length(SIMD2<Float>(localRootDelta.x, localRootDelta.z))
        if localRootMagnitude > 1.0e-4 {
            let localRootPass = signedExpectationPass(value: localRootDelta.z, expectedPositive: expected.forwardPositive)
                && signedExpectationPass(value: localRootDelta.x, expectedPositive: expected.rightPositive)
            if !localRootPass {
                return "FAIL(stage=localRootDeltaInterpretation)"
            }
        }

        let basisOrthogonalPass = abs(simd_dot(forward, right)) <= 1.0e-3
            && simd_length_squared(forward) >= 0.99
            && simd_length_squared(right) >= 0.99
        if !basisOrthogonalPass {
            return "FAIL(stage=basisGeneration)"
        }

        let dotForward = simd_dot(worldDelta, forward)
        let dotRight = simd_dot(worldDelta, right)
        let worldProjectionPass = signedExpectationPass(value: dotForward, expectedPositive: expected.forwardPositive)
            && signedExpectationPass(value: dotRight, expectedPositive: expected.rightPositive)
        if !worldProjectionPass {
            return usedFallbackDisplacement
                ? "FAIL(stage=fallbackMismatch)"
                : "FAIL(stage=worldProjection)"
        }

        return "PASS"
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
