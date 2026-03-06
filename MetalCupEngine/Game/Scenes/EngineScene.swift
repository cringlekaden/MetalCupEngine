/// EngineScene.swift
/// Scene update and render submission pipeline.
/// Created by Kaden Cringle.

import MetalKit
import simd
import Foundation

public enum TransformMutationSource: CustomStringConvertible {
    case script
    case editor
    case physics
    case characterController
    case engineSystem
    case serialization
    case prefab

    public var description: String {
        switch self {
        case .script: return "script"
        case .editor: return "editor"
        case .physics: return "physics"
        case .characterController: return "characterController"
        case .engineSystem: return "engineSystem"
        case .serialization: return "serialization"
        case .prefab: return "prefab"
        }
    }
}

public struct FixedStepMode: OptionSet {
    public let rawValue: Int

    public static let executeScripts = FixedStepMode(rawValue: 1 << 0)
    public static let dispatchScriptEvents = FixedStepMode(rawValue: 1 << 1)
    public static let editorView = FixedStepMode(rawValue: 1 << 2)
    public static let cloneIsolation = FixedStepMode(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public class EngineScene {
    public enum TransformAuthorityMode: CustomStringConvertible {
        case edit
        case play
        case simulate

        public var description: String {
            switch self {
            case .edit: return "Edit"
            case .play: return "Play"
            case .simulate: return "Simulate"
            }
        }
    }

    public enum SimulateAnimationPolicy {
        /// Option A: simulate previews should keep animation advancing even when runtime scripts are disabled.
        case animateWithoutScripts
        /// Option B fallback: freeze animation unless scripts are enabled.
        case requireScriptExecution
    }

    public struct FixedStepDiagnostics {
        public var renderDeltaTime: Float
        public var fixedDeltaTime: Float
        public var fixedStepsThisFrame: Int
        public var fixedStepsLastSecond: Int
        public var accumulatorBefore: Float
        public var accumulatorAfter: Float
        public var interpolationAlpha: Float

        public init(renderDeltaTime: Float = 0.0,
                    fixedDeltaTime: Float = 1.0 / 60.0,
                    fixedStepsThisFrame: Int = 0,
                    fixedStepsLastSecond: Int = 0,
                    accumulatorBefore: Float = 0.0,
                    accumulatorAfter: Float = 0.0,
                    interpolationAlpha: Float = 0.0) {
            self.renderDeltaTime = renderDeltaTime
            self.fixedDeltaTime = fixedDeltaTime
            self.fixedStepsThisFrame = fixedStepsThisFrame
            self.fixedStepsLastSecond = fixedStepsLastSecond
            self.accumulatorBefore = accumulatorBefore
            self.accumulatorAfter = accumulatorAfter
            self.interpolationAlpha = interpolationAlpha
        }
    }

    public let ecs: SceneECS
    public let runtime = SceneRuntime()
    public var prefabSystem: PrefabSystem?
    public private(set) var physicsSystem: PhysicsSystem?
    public weak var engineContext: EngineContext?

    public let id: UUID
    public private(set) var name: String
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    private let _editorCameraController = EditorCameraController()
    private var lastFrameContext: FrameContext?
    public lazy var transformAuthority = TransformAuthorityService(scene: self)
    private lazy var scriptSystem = ScriptSystemAdapter(scene: self)
    private let sceneSerializationService = SceneSerializationService()
    private let updateScheduler = SceneUpdateScheduler()
    private let animationSystem = AnimationSystem()
    private let audioSceneSystem = AudioSceneSystem()

    private let characterSystem = CharacterControllerSystem()
    private var fixedStepDiagnostics = FixedStepDiagnostics()
    private var isExecutingFixedStep: Bool = false
    private var currentInputKeys: [Bool] = []
    private var previousInputKeys: [Bool] = []
    public private(set) var transformAuthorityMode: TransformAuthorityMode = .edit

    public var environmentMapHandle: AssetHandle?

    public init(id: UUID = UUID(),
                name: String,
                environmentMapHandle: AssetHandle?,
                prefabSystem: PrefabSystem? = nil,
                engineContext: EngineContext? = nil,
                shouldBuildScene: Bool = true) {
        self.id = id
        self.name = name
        self.environmentMapHandle = environmentMapHandle
        self.ecs = SceneECS()
        self.prefabSystem = prefabSystem
        self.engineContext = engineContext
        if shouldBuildScene {
            buildScene()
        }
    }

    public func onUpdate(frame: FrameContext, isPlaying: Bool = true, isPaused: Bool = false) {
        updateScene(frame: frame,
                    isPlaying: isPlaying,
                    isPaused: isPaused,
                    runRuntimeScripts: isPlaying && !isPaused,
                    animateInSimulateWhenScriptsDisabled: false)
    }

    public func updateEdit(frame: FrameContext) {
#if DEBUG
        if runtime.isPlaying {
            assertionFailure("updateEdit should not run while runtime is playing.")
        }
#endif
        runtime.stop()
        transformAuthorityMode = .edit
        updateScene(frame: frame,
                    isPlaying: false,
                    isPaused: false,
                    runRuntimeScripts: false,
                    animateInSimulateWhenScriptsDisabled: false)
    }

    public func updateSimulate(frame: FrameContext,
                               scriptsEnabled: Bool = false,
                               animationPolicy: SimulateAnimationPolicy = .animateWithoutScripts) {
#if DEBUG
        if runtime.isPlaying {
            assertionFailure("updateSimulate should not run while runtime is playing.")
        }
#endif
        runtime.stop()
        transformAuthorityMode = .simulate
        let animateWithoutScripts = (animationPolicy == .animateWithoutScripts)
        updateScene(frame: frame,
                    isPlaying: false,
                    isPaused: false,
                    runRuntimeScripts: scriptsEnabled,
                    animateInSimulateWhenScriptsDisabled: animateWithoutScripts)
    }

    public func updatePlay(frame: FrameContext, isPaused: Bool) {
#if DEBUG
        if !runtime.isPlaying {
            assertionFailure("updatePlay requires runtime to be in play mode.")
        }
#endif
        transformAuthorityMode = .play
        updateScene(frame: frame,
                    isPlaying: true,
                    isPaused: isPaused,
                    runRuntimeScripts: !isPaused,
                    animateInSimulateWhenScriptsDisabled: false)
    }

    private func updateScene(frame: FrameContext,
                             isPlaying: Bool,
                             isPaused: Bool,
                             runRuntimeScripts: Bool,
                             animateInSimulateWhenScriptsDisabled: Bool) {
        let request = SceneUpdateScheduler.UpdateRequest(
            frame: frame,
            isPlaying: isPlaying,
            isPaused: isPaused,
            runRuntimeScripts: runRuntimeScripts,
            animateInSimulateWhenScriptsDisabled: animateInSimulateWhenScriptsDisabled
        )
        let pipeline = SceneUpdateScheduler.UpdatePipeline(
            beginDebugFrame: {
#if DEBUG
                self.transformAuthority.beginDebugBypassDetectionFrame()
#endif
            },
            endDebugFrame: {
#if DEBUG
                self.transformAuthority.assertNoExternalTransformWrites()
#endif
            },
            updateInputSnapshot: { frame in
                self.previousInputKeys = self.currentInputKeys
                self.currentInputKeys = frame.input.keys
                self.lastFrameContext = frame
            },
            ensureCamera: {
                self.ensureCameraEntity()
            },
            updateCamera: { isPlaying, frame in
                self.updateCamera(isPlaying: isPlaying, frame: frame)
            },
            updateSceneConstants: { frame in
                self.updateSceneConstantsForFrame(frame)
            },
            updateSky: {
                SkySystem.update(scene: self)
            },
            handleRuntimeCursorToggle: { isPlaying in
                guard isPlaying, self.inputWasKeyPressed(KeyCodes.escape.rawValue) else { return }
                runtimeToggleCursorLockOverride()
            },
            scriptUpdate: { dt, runRuntimeScripts in
                self.scriptSystem.update(dt: dt, runRuntimeScripts: runRuntimeScripts)
            },
            animationUpdate: { dt, isPlaying, runRuntimeScripts, animateInSimulateWhenScriptsDisabled in
                let shouldAnimate = isPlaying || runRuntimeScripts || animateInSimulateWhenScriptsDisabled
                guard shouldAnimate else { return }
                self.animationSystem.update(scene: self, dt: dt)
            },
            audioUpdate: { frame in
                self.audioSceneSystem.update(scene: self, frame: frame)
            },
            runtimeUpdate: { isPlaying, isPaused, totalTime in
                guard isPlaying, !isPaused else { return }
                self.updateLightOrbits(totalTime: totalTime)
                self.doUpdate()
            },
            syncLights: {
                self.syncLights()
            }
        )
        updateScheduler.runUpdate(request: request, pipeline: pipeline)
    }

    func runtimeUpdate(isPlaying: Bool, isPaused: Bool, frame: FrameContext) {
        if isPlaying {
            runtime.play()
            if isPaused {
                runtime.pause()
            } else {
                runtime.resume()
            }
            updatePlay(frame: frame, isPaused: isPaused)
        } else {
            updateEdit(frame: frame)
        }
    }

    func runtimeFixedUpdate() {
        onFixedUpdate()
    }

    public func onFixedUpdate() {
        doFixedUpdate()
    }

    public func onRender(encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        SceneRenderer.renderScene(into: encoder, scene: self, frameContext: frameContext)
    }

    @discardableResult
    public func render(view: SceneView, context: RenderContext, frameContext: RendererFrameContext) -> RenderOutputs {
        SceneRenderer.render(scene: self, view: view, context: context, frameContext: frameContext)
    }

    @discardableResult
    public func render(view: SceneView, context: RenderContext) -> RenderOutputs {
        guard let engineContext else {
            return RenderOutputs(color: context.colorTarget, depth: context.depthTarget, pickingId: context.idTarget)
        }
        let storage = RendererFrameContextStorage(engineContext: engineContext)
        let frameContext = storage.beginFrame()
        return render(view: view, context: context, frameContext: frameContext)
    }

    public func renderPreview(encoder: MTLRenderCommandEncoder, cameraEntity: Entity, viewportSize: SIMD2<Float>, frameContext: RendererFrameContext) {
        guard ecs.get(TransformComponent.self, for: cameraEntity) != nil,
              let camera = ecs.get(CameraComponent.self, for: cameraEntity) else { return }
        let worldTransform = ecs.worldTransform(for: cameraEntity)
        let snapshot = makeRenderFrameSnapshot(frameToken: frameContext.currentFrameCounter(), layerFilterMask: .all)
        SceneRenderer.renderPreview(
            encoder: encoder,
            snapshot: snapshot,
            camera: camera,
            worldTransform: worldTransform,
            viewportSize: viewportSize,
            frameContext: frameContext
        )
    }

    public func renderPreview(encoder: MTLRenderCommandEncoder, cameraEntity: Entity, viewportSize: SIMD2<Float>) {
        guard let engineContext else { return }
        let storage = RendererFrameContextStorage(engineContext: engineContext)
        let frameContext = storage.beginFrame()
        renderPreview(encoder: encoder, cameraEntity: cameraEntity, viewportSize: viewportSize, frameContext: frameContext)
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        mask: LayerMask? = nil,
                        includeTriggers: Bool = false) -> Entity? {
        guard let hit = raycastHit(origin: origin,
                                   direction: direction,
                                   maxDistance: 1000.0,
                                   mask: mask,
                                   includeTriggers: includeTriggers),
              let entityId = hit.entityId,
              let entity = ecs.entity(with: entityId) else { return nil }
        return entity
    }

    public func raycastHit(origin: SIMD3<Float>,
                           direction: SIMD3<Float>,
                           maxDistance: Float = 1000.0,
                           mask: LayerMask? = nil,
                           includeTriggers: Bool = false) -> PhysicsRaycastHit? {
        guard let physicsSystem else { return nil }
        let effectiveMask = mask ?? physicsSystem.defaultGameplayLayerMask()
        return physicsSystem.raycast(origin: origin,
                                     direction: direction,
                                     maxDistance: maxDistance,
                                     layerMask: effectiveMask,
                                     includeTriggers: includeTriggers)
    }

    public func raycastForEditorPicking(origin: SIMD3<Float>,
                                        direction: SIMD3<Float>,
                                        mask: LayerMask? = nil) -> Entity? {
        raycast(origin: origin, direction: direction, mask: mask, includeTriggers: false)
    }

    public func physicsTriggerEvents() -> [PhysicsOverlapEvent] {
        physicsSystem?.recentOverlapEvents() ?? []
    }

    public func physicsCollisionEvents() -> [PhysicsCollisionEvent] {
        physicsSystem?.recentCollisionEvents() ?? []
    }

    public func physicsScriptEventQueueTelemetry() -> PhysicsSystem.ScriptEventQueueTelemetry {
        physicsSystem?.scriptEventQueueStats() ?? .init()
    }

    public func raycast(hitEntity: Entity?, mask: LayerMask = .all) -> Entity? {
        guard let entity = hitEntity else { return nil }
        let layer = layerIndex(for: entity)
        return mask.contains(layerIndex: layer) ? entity : nil
    }

    @discardableResult
    public func setLocalTransform(_ transform: TransformComponent,
                                  for entity: Entity,
                                  source: TransformMutationSource) -> Bool {
        transformAuthority.setLocalTransform(entity: entity, transform: transform, source: source)
    }

    @discardableResult
    public func setWorldTransform(_ worldTransform: TransformComponent,
                                  for entity: Entity,
                                  source: TransformMutationSource) -> Bool {
        transformAuthority.setWorldTransform(entity: entity, transform: worldTransform, source: source)
    }

    public func requestCharacterMove(entityId: UUID, direction: SIMD3<Float>) {
        characterSystem.enqueueMove(entityId: entityId, direction: direction)
    }

    public func requestCharacterMoveInput(entityId: UUID, input: SIMD2<Float>) {
        characterSystem.enqueueMoveInput(entityId: entityId, input: input)
    }

    public func requestCharacterSprint(entityId: UUID, isSprinting: Bool) {
        characterSystem.enqueueSprint(entityId: entityId, isSprinting: isSprinting)
    }

    public func requestCharacterLookInput(entityId: UUID, delta: SIMD2<Float>) {
        characterSystem.enqueueLookInput(entityId: entityId, delta: delta)
    }

    public func requestCharacterJump(entityId: UUID) {
        characterSystem.enqueueJump(entityId: entityId)
    }

    public func setCharacterGroundProvider(_ provider: CharacterGroundProvider?) {
        characterSystem.setGroundProvider(provider)
    }

    public func setCharacterStepHook(_ hook: CharacterControllerStepHook?) {
        characterSystem.setStepHook(hook)
    }

    public func isCharacterGrounded(entityId: UUID) -> Bool {
        characterSystem.isGrounded(scene: self, entityId: entityId)
    }

    public func characterVelocity(entityId: UUID) -> SIMD3<Float> {
        characterSystem.velocity(scene: self, entityId: entityId)
    }

    public func characterLocomotionOutput(entityId: UUID) -> CharacterLocomotionOutput {
        characterSystem.locomotionOutput(entityId: entityId)
    }

    public func setCharacterDebugDrawEnabled(entityId: UUID, isEnabled: Bool) {
        characterSystem.setDebugDrawEnabled(entityId: entityId, isEnabled: isEnabled)
    }

    public func isCharacterDebugDrawEnabled(entityId: UUID) -> Bool {
        characterSystem.isDebugDrawEnabled(entityId: entityId)
    }

    public func characterDebugVisualization(entityId: UUID) -> CharacterControllerDebugVisualization {
        characterSystem.debugVisualization(entityId: entityId)
    }

    public func setFixedStepDiagnostics(_ diagnostics: FixedStepDiagnostics) {
        fixedStepDiagnostics = diagnostics
        characterSystem.setRenderInterpolationAlpha(diagnostics.interpolationAlpha, scene: self)
    }

    public func latestFixedStepDiagnostics() -> FixedStepDiagnostics {
        fixedStepDiagnostics
    }

    public func renderWorldTransform(for entity: Entity) -> TransformComponent {
        characterSystem.renderWorldTransform(scene: self, entity: entity)
    }

    public func makeRenderFrameSnapshot(frameToken: UInt64, layerFilterMask: LayerMask) -> RenderFrameSnapshot {
        let animationPreparation = animationSystem.prepareSnapshot(scene: self, layerFilterMask: layerFilterMask)
        let entries = ecs.viewTransformMeshRendererArray()
        var renderables: [RenderFrameSnapshot.Renderable] = []
        renderables.reserveCapacity(entries.count)
        for (entity, _, meshRenderer) in entries {
            let layer = ecs.get(LayerComponent.self, for: entity)?.index ?? LayerCatalog.defaultLayerIndex
            if !layerFilterMask.contains(layerIndex: layer) { continue }
            renderables.append(
                RenderFrameSnapshot.Renderable(
                    entity: entity,
                    meshHandle: meshRenderer.meshHandle,
                    meshRenderer: meshRenderer,
                    inheritedMaterialHandle: ecs.get(MaterialComponent.self, for: entity)?.materialHandle,
                    worldTransform: renderWorldTransform(for: entity)
                )
            )
        }
        let activeSkyLight = ecs.activeSkyLight()?.1
        let lightData = _lightManager.snapshotLightData()
        let directionalLights = lightData.filter { $0.type == 2 }
        let localLights = lightData.filter { $0.type != 2 }
        let shadowLightDirection = resolveDirectionalShadowLightDirection(activeSkyLight: activeSkyLight)
        var hasher = Hasher()
        hasher.combine(frameToken)
        hasher.combine(layerFilterMask.rawValue)
        hasher.combine(renderables.count)
        hasher.combine(directionalLights.count)
        hasher.combine(localLights.count)
        hasher.combine(animationPreparation.skinnedEntityCount)
        hasher.combine(activeSkyLight != nil)
        hasher.combine(_sceneConstants.cameraPositionAndIBL.x.bitPattern)
        hasher.combine(_sceneConstants.cameraPositionAndIBL.y.bitPattern)
        hasher.combine(_sceneConstants.cameraPositionAndIBL.z.bitPattern)

        return RenderFrameSnapshot(
            sceneKey: ObjectIdentifier(self),
            frameToken: frameToken,
            signature: UInt64(bitPattern: Int64(hasher.finalize())),
            sceneConstants: _sceneConstants,
            activeSkyLight: activeSkyLight,
            directionalLights: directionalLights,
            localLights: localLights,
            directionalShadowLightDirection: shadowLightDirection,
            animationPayload: animationPreparation.payload,
            renderables: renderables
        )
    }

    private func resolveDirectionalShadowLightDirection(activeSkyLight: SkyLightComponent?) -> SIMD3<Float>? {
        if let sky = activeSkyLight,
           sky.enabled,
           sky.mode == .procedural,
           let sunEntity = ecs.firstEntity(with: SkySunTag.self),
           let sunLight = ecs.get(LightComponent.self, for: sunEntity),
           sunLight.type == .directional,
           sunLight.castsShadows {
            return SkySystem.sunRayDirection(azimuthDegrees: sky.azimuthDegrees,
                                             elevationDegrees: sky.elevationDegrees)
        }

        var direction: SIMD3<Float>?
        ecs.viewLights { entity, _, light in
            if direction != nil { return }
            guard light.type == .directional, light.castsShadows else { return }
            let worldTransform = ecs.worldTransform(for: entity)
            direction = TransformMath.directionalLightDirection(from: worldTransform.rotation)
        }
        return direction
    }

    func updateCameras() {
        updateCamera(isPlaying: false, frame: currentFrameForUpdates())
    }

    public func refreshRuntimeCamera(frame: FrameContext) {
        updateCamera(isPlaying: true, frame: frame)
    }

    public func updateAspectRatio() {
        updateCamera(isPlaying: false, frame: currentFrameForUpdates())
    }

    func buildScene() {}

    func doUpdate() {}

    func doFixedUpdate() {
        _ = runFixedStep(mode: [.executeScripts, .dispatchScriptEvents])
    }

    @discardableResult
    public func runPlayFixedStep(fixedDeltaOverride: Float? = nil) -> Float {
#if DEBUG
        if !runtime.isPlaying {
            assertionFailure("runPlayFixedStep called while runtime is not playing.")
        }
#endif
        return runFixedStep(mode: [.executeScripts, .dispatchScriptEvents], fixedDeltaOverride: fixedDeltaOverride)
    }

    @discardableResult
    public func runSimulateFixedStep(fixedDeltaOverride: Float? = nil) -> Float {
#if DEBUG
        if runtime.isPlaying {
            assertionFailure("runSimulateFixedStep called while runtime is playing.")
        }
#endif
        return runFixedStep(mode: [], fixedDeltaOverride: fixedDeltaOverride)
    }

    @discardableResult
    public func runFixedStep(mode: FixedStepMode,
                             fixedDeltaOverride: Float? = nil) -> Float {
        let defaultDelta: Float = 1.0 / 60.0
        let fixedDelta = fixedDeltaOverride
            ?? engineContext?.physicsSettings.fixedDeltaTime
            ?? lastFrameContext?.time.fixedDeltaTime
            ?? defaultDelta
        let request = SceneUpdateScheduler.FixedRequest(mode: mode, fixedDelta: fixedDelta)
        let pipeline = SceneUpdateScheduler.FixedPipeline(
            profiler: engineContext?.renderer?.profiler,
            scriptFixedPrePhysics: { executeScripts, fixedDelta in
                self.scriptSystem.fixedPrePhysics(dt: fixedDelta, executeScripts: executeScripts)
            },
            characterFixed: { fixedDelta in
                self.characterSystem.fixedStep(scene: self, fixedDelta: fixedDelta)
            },
            physicsStep: { fixedDelta in
                self.physicsSystem?.fixedUpdate(scene: self, fixedDeltaTime: fixedDelta)
            },
            drainPhysicsEvents: { dispatchEvents in
                guard dispatchEvents else { return nil }
                return self.physicsSystem?.drainEvents()
            },
            scriptFixedPostPhysics: { executeScripts, dispatchEvents, fixedDelta, events in
                self.scriptSystem.enqueuePhysicsEvents(events)
                self.scriptSystem.fixedPostPhysics(dt: fixedDelta,
                                                   executeScripts: executeScripts,
                                                   dispatchEvents: dispatchEvents)
            }
        )
        isExecutingFixedStep = true
        defer { isExecutingFixedStep = false }
        return updateScheduler.runFixedStep(request: request, pipeline: pipeline)
    }

    public func notifyScriptSceneStart() {
        scriptSystem.onSceneStart()
    }

    public func notifyScriptSceneStop() {
        scriptSystem.onSceneStop()
    }

    public func startPhysics(settings: PhysicsSettings) {
        guard physicsSystem == nil else { return }
        characterSystem.prepareForPhysicsStart(scene: self)
        guard let system = PhysicsSystem(settings: settings) else { return }
        system.buildBodies(scene: self)
        physicsSystem = system
        system.syncSettingsIfNeeded(scene: self)
        system.pullTransformsFromPhysics(scene: self)
    }

    public func stopPhysics() {
        guard let system = physicsSystem else { return }
        characterSystem.destroyAllCharacters(using: system)
        system.destroyBodies(scene: self)
        physicsSystem = nil
    }

    public func rebuildPhysicsBody(for entity: Entity) -> Bool {
        guard let system = physicsSystem else { return false }
        return system.rebuildBody(entity: entity, scene: self)
    }

    public func toDocument(rendererSettingsOverride: RendererSettingsDTO? = nil,
                           physicsSettingsOverride: PhysicsSettingsDTO? = nil,
                           includeEditorEntities: Bool = true) -> SceneDocument {
        sceneSerializationService.toDocument(scene: self,
                                             rendererSettingsOverride: rendererSettingsOverride,
                                             physicsSettingsOverride: physicsSettingsOverride,
                                             includeEditorEntities: includeEditorEntities)
    }

    public func apply(document: SceneDocument) {
        sceneSerializationService.apply(document: document, to: self)
    }

    
    @discardableResult
    public func instantiate(prefab: PrefabDocument, prefabHandle: AssetHandle?) -> [Entity] {
        sceneSerializationService.instantiate(prefab: prefab, prefabHandle: prefabHandle, into: self)
    }

    var sceneName: String { name }

    func setSceneName(_ value: String) {
        name = value
    }

    func prepareForSceneDocumentApply() {
        characterSystem.resetForSceneApply()
    }

    func ensureSceneCameraEntity() {
        ensureCameraEntity()
    }

    func resetSceneEditorCameraController() {
        _editorCameraController.reset()
    }

    private func ensureCameraEntity() {
        if findEditorCamera() != nil { return }
        let entity = ecs.createEntity(name: "Editor Camera")
        _ = transformAuthority.setLocalTransform(entity: entity,
                                                 transform: TransformComponent(position: SIMD3<Float>(0, 3, 10)),
                                                 source: .engineSystem)
        ecs.add(CameraComponent(isPrimary: true, isEditor: true), to: entity)
    }

    private func updateCamera(isPlaying: Bool, frame: FrameContext) {
        guard var active = resolveActiveCamera(isPlaying: isPlaying) else { return }
        if active.shouldUpdateEditorCamera {
            _editorCameraController.update(transform: &active.transform, frame: frame)
            _ = transformAuthority.setLocalTransform(entity: active.entity,
                                                     transform: active.transform,
                                                     source: .engineSystem)
        }
        let worldTransform = renderWorldTransform(for: active.entity)
        let viewportSize = frame.input.viewportSize
        let aspectRatio: Float = {
            let width = max(1.0, viewportSize.x)
            let height = max(1.0, viewportSize.y)
            return height == 0 ? 1.0 : width / height
        }()
        applyCameraConstants(transform: worldTransform, camera: active.camera, aspectRatio: aspectRatio)
    }

    private func resolveActiveCamera(isPlaying: Bool) -> (entity: Entity, transform: TransformComponent, camera: CameraComponent, shouldUpdateEditorCamera: Bool)? {
        let selected: (Entity, TransformComponent, CameraComponent)? = {
            if !isPlaying {
                if let editorCamera = findEditorCamera() {
                    return editorCamera
                }
                return ecs.activeCamera(allowEditor: true, preferEditor: true)
            }
            return ecs.activeCamera(allowEditor: false) ?? ecs.activeCamera(allowEditor: true)
        }()
        guard let selected else { return nil }
        let shouldUpdateEditorCamera = !isPlaying && selected.2.isEditor
        return (selected.0, selected.1, selected.2, shouldUpdateEditorCamera)
    }

    private func findEditorCamera() -> (Entity, TransformComponent, CameraComponent)? {
        var result: (Entity, TransformComponent, CameraComponent)?
        ecs.viewCameras { entity, transform, camera in
            if result != nil { return }
            guard camera.isEditor, let transform else { return }
            result = (entity, transform, camera)
        }
        return result
    }

    private func applyCameraConstants(transform: TransformComponent, camera: CameraComponent, aspectRatio: Float) {
        _sceneConstants.viewMatrix = SceneRenderer.viewMatrix(from: transform)
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0
        _sceneConstants.skyViewMatrix[3][1] = 0
        _sceneConstants.skyViewMatrix[3][2] = 0
        _sceneConstants.projectionMatrix = SceneRenderer.projectionMatrix(from: camera, aspectRatio: aspectRatio)
        _sceneConstants.inverseProjectionMatrix = simd_inverse(_sceneConstants.projectionMatrix)
        _sceneConstants.cameraPositionAndIBL = SIMD4<Float>(transform.position, 1.0)
    }

    private func updateSceneConstantsForFrame(_ frame: FrameContext) {
        _sceneConstants.totalGameTime = frame.time.totalTime
        let assetManager = engineContext?.assets
        let hasEnvironment: Bool = {
            guard let (_, sky) = ecs.activeSkyLight(), sky.enabled else { return false }
            switch sky.mode {
            case .hdri:
                return sky.hdriHandle.flatMap { assetManager?.texture(handle: $0) } != nil
            case .procedural:
                return true
            }
        }()
        let settings = engineContext?.rendererSettings ?? RendererSettings()
        let skyIntensity = ecs.activeSkyLight()?.1.intensity ?? 1.0
        let iblIntensity = (hasEnvironment && settings.iblEnabled != 0) ? settings.iblIntensity * skyIntensity : 0.0
        _sceneConstants.cameraPositionAndIBL.w = iblIntensity
    }

    public func onEvent(_ event: Event) {}

    private func updateLightOrbits(totalTime: Float) {
        let t = totalTime
        ecs.viewLightOrbits { entity, transform, orbit in
            let angle = t * orbit.speed + orbit.phase
            let centerPosition: SIMD3<Float> = {
                guard let centerId = orbit.centerEntityId,
                      let centerEntity = ecs.entity(with: centerId),
                      ecs.get(TransformComponent.self, for: centerEntity) != nil else {
                    return .zero
                }
                return ecs.worldTransform(for: centerEntity).position
            }()

            if var light = ecs.get(LightComponent.self, for: entity), light.type == .directional {
                if ecs.get(SkySunTag.self, for: entity) != nil {
                    return
                }
                if orbit.affectsDirection {
                    let lightRayDirection = SIMD3<Float>(
                        cos(angle) * orbit.radius,
                        orbit.height,
                        sin(angle) * orbit.radius
                    )
                    if simd_length_squared(lightRayDirection) > 0,
                       var transform {
                        transform.rotation = TransformMath.rotationForDirectionalLight(direction: simd_normalize(lightRayDirection))
                        _ = transformAuthority.setLocalTransform(entity: entity,
                                                                 transform: transform,
                                                                 source: .engineSystem)
                    }
                }
                return
            }

            guard var transform else { return }
            transform.position = SIMD3<Float>(
                centerPosition.x + cos(angle) * orbit.radius,
                centerPosition.y + orbit.height,
                centerPosition.z + sin(angle) * orbit.radius
            )
            _ = transformAuthority.setLocalTransform(entity: entity,
                                                     transform: transform,
                                                     source: .engineSystem)

            if orbit.affectsDirection,
               let light = ecs.get(LightComponent.self, for: entity),
               light.type == .spot {
                let direction = centerPosition - transform.position
                if simd_length_squared(direction) > 0 {
                    transform.rotation = TransformMath.rotationForDirectionalLight(direction: simd_normalize(direction))
                    _ = transformAuthority.setLocalTransform(entity: entity,
                                                             transform: transform,
                                                             source: .engineSystem)
                }
            }
        }
    }

    private func syncLights() {
        var lightData: [LightData] = []
        let activeSky = ecs.activeSkyLight()
        let activeSkyRayDirection: SIMD3<Float>? = {
            guard let (_, sky) = activeSky, sky.enabled, sky.mode == .procedural else { return nil }
            return SkySystem.sunRayDirection(azimuthDegrees: sky.azimuthDegrees,
                                             elevationDegrees: sky.elevationDegrees)
        }()
        ecs.viewLights { entity, _, light in
            var data = light.data
            let worldTransform = ecs.worldTransform(for: entity)
            switch light.type {
            case .point:
                data.type = 0
                data.direction = light.direction
            case .spot:
                data.type = 1
                data.direction = TransformMath.directionalLightDirection(from: worldTransform.rotation)
            case .directional:
                data.type = 2
                if ecs.get(SkySunTag.self, for: entity) != nil,
                   let activeSkyRayDirection {
                    data.direction = activeSkyRayDirection
                } else {
                    data.direction = TransformMath.directionalLightDirection(from: worldTransform.rotation)
                }
            }
            data.position = worldTransform.position
            data.range = light.range
            data.innerConeCos = light.innerConeCos
            data.outerConeCos = light.outerConeCos
            lightData.append(data)
        }
        _lightManager.setLights(lightData)
    }

    private func currentFrameForUpdates() -> FrameContext {
        if let lastFrameContext { return lastFrameContext }
        let frameTime = FrameTime(
            deltaTime: 0.0,
            unscaledDeltaTime: 0.0,
            timeScale: 1.0,
            fixedDeltaTime: 1.0 / 60.0,
            frameCount: 0,
            totalTime: 0.0,
            unscaledTotalTime: 0.0
        )
        let inputState = InputState(
            mousePosition: .zero,
            mouseDelta: .zero,
            scrollDelta: 0,
            mouseButtons: [],
            keys: [],
            viewportOrigin: .zero,
            viewportSize: .zero,
            textInput: ""
        )
        return FrameContext(time: frameTime, input: inputState)
    }

    public func inputIsKeyDown(_ keyCode: UInt16) -> Bool {
        let index = Int(keyCode)
        guard index >= 0, index < currentInputKeys.count else { return false }
        return currentInputKeys[index]
    }

    public func inputWasKeyPressed(_ keyCode: UInt16) -> Bool {
        let index = Int(keyCode)
        guard index >= 0, index < currentInputKeys.count else { return false }
        let current = currentInputKeys[index]
        let previous = index < previousInputKeys.count ? previousInputKeys[index] : false
        return current && !previous
    }

    public func inputMouseDelta() -> SIMD2<Float> {
        lastFrameContext?.input.mouseDelta ?? .zero
    }

    public func resetRuntimeInputState() {
        characterSystem.resetRuntimeInputState()
        previousInputKeys.removeAll(keepingCapacity: true)
        currentInputKeys.removeAll(keepingCapacity: true)
    }

    private func layerIndex(for entity: Entity) -> Int32 {
        return ecs.get(LayerComponent.self, for: entity)?.index ?? LayerCatalog.defaultLayerIndex
    }

    func getSceneConstants() -> SceneConstants {
        _sceneConstants
    }

    func setSceneConstants(_ value: SceneConstants) {
        _sceneConstants = value
    }

    func getLightManager() -> LightManager {
        _lightManager
    }

}
