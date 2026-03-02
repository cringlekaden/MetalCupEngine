/// EngineScene.swift
/// Scene update and render submission pipeline.
/// Created by Kaden Cringle

import MetalKit
import simd

public enum TransformMutationSource {
    case script
    case editor
    case physics
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
    private var _cachedBatchResult: Any?
    private var _cachedBatchFrameToken: UInt64 = UInt64.max
    private var lastFrameContext: FrameContext?

    private var debugFrameCounter: UInt64 = 0
    private var illegalScriptTransformWarnings: Set<UUID> = []
    private var characterMoveRequests: [UUID: SIMD3<Float>] = [:]
    private var characterJumpRequests: Set<UUID> = []

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
        debugFrameCounter &+= 1
        lastFrameContext = frame
        dispatchScriptChanges()
        // Update order: camera -> scene constants -> sky system -> scene update -> light sync.
        ensureCameraEntity()
        updateCamera(isPlaying: isPlaying, frame: frame)
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
        SkySystem.update(scene: ecs)
        let shouldRunScripts = isPlaying && !isPaused
        if shouldRunScripts {
            engineContext?.scriptRuntime.onUpdate(dt: frame.time.deltaTime)
        }
        if isPlaying && !isPaused {
            updateLightOrbits(totalTime: frame.time.totalTime)
            doUpdate()
        }
        if shouldRunScripts {
            engineContext?.scriptRuntime.onLateUpdate(dt: frame.time.deltaTime)
        }
        syncLights()
    }

    func runtimeUpdate(isPlaying: Bool, isPaused: Bool, frame: FrameContext) {
        onUpdate(frame: frame, isPlaying: isPlaying, isPaused: isPaused)
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
        SceneRenderer.renderPreview(
            encoder: encoder,
            scene: self,
            cameraEntity: cameraEntity,
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
                        mask: LayerMask = .all,
                        includeTriggers: Bool = true) -> Entity? {
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
                           mask: LayerMask = .all,
                           includeTriggers: Bool = true) -> PhysicsRaycastHit? {
        guard let physicsSystem else { return nil }
        return physicsSystem.raycast(origin: origin,
                                     direction: direction,
                                     maxDistance: maxDistance,
                                     layerMask: mask,
                                     includeTriggers: includeTriggers)
    }

    public func raycastForEditorPicking(origin: SIMD3<Float>,
                                        direction: SIMD3<Float>,
                                        mask: LayerMask = .all) -> Entity? {
        raycast(origin: origin, direction: direction, mask: mask, includeTriggers: false)
    }

    public func physicsTriggerEvents() -> [PhysicsOverlapEvent] {
        physicsSystem?.recentOverlapEvents() ?? []
    }

    public func physicsCollisionEvents() -> [PhysicsCollisionEvent] {
        physicsSystem?.recentCollisionEvents() ?? []
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
        guard ecs.get(TransformComponent.self, for: entity) != nil else { return false }
        let worldTransform: TransformComponent
        if let parent = ecs.getParent(entity) {
            let parentWorld = ecs.worldMatrix(for: parent)
            let localMatrix = TransformMath.makeMatrix(position: transform.position,
                                                       rotation: transform.rotation,
                                                       scale: transform.scale)
            let worldMatrix = parentWorld * localMatrix
            let decomposed = TransformMath.decomposeMatrix(worldMatrix)
            worldTransform = TransformComponent(position: decomposed.position,
                                               rotation: decomposed.rotation,
                                               scale: decomposed.scale)
        } else {
            worldTransform = transform
        }
        return setWorldTransform(worldTransform, for: entity, source: source)
    }

    @discardableResult
    public func setWorldTransform(_ worldTransform: TransformComponent,
                                  for entity: Entity,
                                  source: TransformMutationSource) -> Bool {
        guard var localTransform = ecs.get(TransformComponent.self, for: entity) else { return false }
        let rigidbody = ecs.get(RigidbodyComponent.self, for: entity)

        if let rigidbody, rigidbody.isEnabled {
            switch rigidbody.motionType {
            case .dynamic:
                guard source == .physics else {
                    if source == .script {
                        if illegalScriptTransformWarnings.insert(entity.id).inserted {
                            EngineLoggerContext.log("Script attempted direct transform write on dynamic body \(entity.id.uuidString). Routed to physics body transform.",
                                                    level: .warning,
                                                    category: .scene)
                        }
                    }
                    return physicsSystem?.setBodyTransform(entity: entity,
                                                           scene: self,
                                                           position: worldTransform.position,
                                                           rotation: worldTransform.rotation,
                                                           activate: true) ?? false
                }
            case .kinematic:
                if source != .physics {
                    _ = physicsSystem?.setBodyTransform(entity: entity,
                                                        scene: self,
                                                        position: worldTransform.position,
                                                        rotation: worldTransform.rotation,
                                                        activate: true)
                }
            case .staticBody:
                if source != .physics {
                    _ = physicsSystem?.setBodyTransform(entity: entity,
                                                        scene: self,
                                                        position: worldTransform.position,
                                                        rotation: worldTransform.rotation,
                                                        activate: false)
                }
            }
        }

        if let parent = ecs.getParent(entity) {
            let parentWorldMatrix = ecs.worldMatrix(for: parent)
            let desiredWorldMatrix = TransformMath.makeMatrix(position: worldTransform.position,
                                                              rotation: worldTransform.rotation,
                                                              scale: worldTransform.scale)
            let desiredLocalMatrix = simd_inverse(parentWorldMatrix) * desiredWorldMatrix
            let decomposed = TransformMath.decomposeMatrix(desiredLocalMatrix)
            localTransform.position = decomposed.position
            localTransform.rotation = decomposed.rotation
            localTransform.scale = decomposed.scale
        } else {
            localTransform = worldTransform
        }

        ecs.add(localTransform, to: entity)
        return true
    }

    public func requestCharacterMove(entityId: UUID, direction: SIMD3<Float>) {
        characterMoveRequests[entityId] = direction
    }

    public func requestCharacterJump(entityId: UUID) {
        characterJumpRequests.insert(entityId)
    }

    public func isCharacterGrounded(entityId: UUID) -> Bool {
        guard let entity = ecs.entity(with: entityId),
              ecs.get(CharacterControllerComponent.self, for: entity) != nil,
              let physicsSystem else { return false }
        return physicsSystem.isGrounded(entity: entity, scene: self, probeDistance: 0.25)
    }

    private func applyCharacterControllers() {
        guard let physicsSystem else {
            characterMoveRequests.removeAll(keepingCapacity: true)
            characterJumpRequests.removeAll(keepingCapacity: true)
            return
        }
        ecs.viewDeterministic(CharacterControllerComponent.self) { [weak self] entity, controller in
            guard let self, controller.isEnabled else { return }
            guard var velocity = physicsSystem.bodyVelocity(entity: entity, scene: self) else { return }
            let input = characterMoveRequests[entity.id] ?? SIMD3<Float>(repeating: 0.0)
            let inputLength = simd_length(input)
            let moveDir = inputLength > 1e-5 ? input / inputLength : SIMD3<Float>(repeating: 0.0)
            let targetHorizontal = SIMD3<Float>(moveDir.x * controller.moveSpeed, 0.0, moveDir.z * controller.moveSpeed)
            velocity.x = targetHorizontal.x
            velocity.z = targetHorizontal.z

            if characterJumpRequests.contains(entity.id),
               physicsSystem.isGrounded(entity: entity, scene: self, probeDistance: max(0.1, controller.stepOffset)) {
                velocity.y = controller.jumpForce
            }

            _ = physicsSystem.setBodyLinearVelocity(entity: entity, scene: self, velocity: velocity)
        }
        characterMoveRequests.removeAll(keepingCapacity: true)
        characterJumpRequests.removeAll(keepingCapacity: true)
    }

    func updateCameras() {
        updateCamera(isPlaying: false, frame: currentFrameForUpdates())
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
    public func runFixedStep(mode: FixedStepMode,
                             fixedDeltaOverride: Float? = nil) -> Float {
        let defaultDelta: Float = 1.0 / 60.0
        let fixedDelta = fixedDeltaOverride
            ?? engineContext?.physicsSettings.fixedDeltaTime
            ?? lastFrameContext?.time.fixedDeltaTime
            ?? defaultDelta
        dispatchScriptChanges()
        if mode.contains(.executeScripts) {
            engineContext?.scriptRuntime.onFixedUpdate(dt: fixedDelta)
        }
        applyCharacterControllers()
        physicsSystem?.fixedUpdate(scene: self, fixedDeltaTime: fixedDelta)
        if mode.contains(.dispatchScriptEvents),
           let events = physicsSystem?.drainEvents(),
           !events.isEmpty {
            engineContext?.scriptRuntime.onPhysicsEvents(events: events)
        }
        return fixedDelta
    }

    private func dispatchScriptChanges() {
        guard let runtime = engineContext?.scriptRuntime else {
            _ = ecs.drainChanges()
            return
        }
        let changes = ecs.drainChangesDeterministic()
        guard !changes.isEmpty else { return }
        for change in changes {
            switch change.kind {
            case .entityCreated:
                runtime.onEntityCreated(entityId: change.entityId)
            case .entityDestroyed:
                runtime.onEntityDestroyed(entityId: change.entityId)
            case .componentAdded:
                if let type = change.componentType {
                    runtime.onComponentAdded(entityId: change.entityId, type: type)
                }
            case .componentRemoved:
                if let type = change.componentType {
                    runtime.onComponentRemoved(entityId: change.entityId, type: type)
                }
            case .componentEnabled, .componentDisabled:
                if let type = change.componentType, type == .script {
                    if change.kind == .componentEnabled {
                        runtime.onComponentAdded(entityId: change.entityId, type: type)
                    } else {
                        runtime.onComponentRemoved(entityId: change.entityId, type: type)
                    }
                }
                continue
            }
        }
    }

    public func notifyScriptSceneStart() {
        engineContext?.scriptRuntime.onSceneStart(scene: self)
        dispatchScriptChanges()
    }

    public func notifyScriptSceneStop() {
        engineContext?.scriptRuntime.onSceneStop(scene: self)
    }

    public func startPhysics(settings: PhysicsSettings) {
        guard physicsSystem == nil else { return }
        guard let system = PhysicsSystem(settings: settings) else { return }
        system.buildBodies(scene: self)
        physicsSystem = system
        system.syncSettingsIfNeeded(scene: self)
        system.pullTransformsFromPhysics(scene: self)
    }

    public func stopPhysics() {
        guard let system = physicsSystem else { return }
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
        func overrideSet(for entity: Entity) -> Set<PrefabOverrideType> {
            return ecs.get(PrefabOverrideComponent.self, for: entity)?.overridden ?? []
        }

        func shouldSerializeOverride(_ type: PrefabOverrideType, for entity: Entity) -> Bool {
            return overrideSet(for: entity).contains(type)
        }

        func transformDTO(for entity: Entity) -> TransformComponentDTO? {
            return ecs.get(TransformComponent.self, for: entity).map { component in
                TransformComponentDTO(
                    position: Vector3DTO(component.position),
                    rotationQuat: Vector4DTO(component.rotation),
                    scale: Vector3DTO(component.scale)
                )
            }
        }

        func shouldSerializeEntity(_ entity: Entity) -> Bool {
            guard !includeEditorEntities else { return true }
            if let camera = ecs.get(CameraComponent.self, for: entity), camera.isEditor {
                return false
            }
            return true
        }

        let entities = ecs.allEntities().filter(shouldSerializeEntity).map { entity -> EntityDocument in
            let prefabLink = ecs.get(PrefabInstanceComponent.self, for: entity)
            let prefabOverrides = ecs.get(PrefabOverrideComponent.self, for: entity)
            let prefabOverridesDTO: PrefabOverrideComponentDTO? = prefabOverrides.map {
                PrefabOverrideComponentDTO(overriddenComponents: $0.overridden.map { $0.rawValue })
            }
            let parentId = ecs.getParent(entity)?.id

            if let prefabLink {
                let components = ComponentsDocument(
                    name: shouldSerializeOverride(.name, for: entity)
                        ? ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) }
                        : nil,
                    transform: transformDTO(for: entity),
                    layer: shouldSerializeOverride(.layer, for: entity)
                        ? ecs.get(LayerComponent.self, for: entity).map { LayerComponentDTO(layerIndex: $0.index) }
                        : nil,
                    prefabLink: PrefabLinkComponentDTO(
                        prefabHandle: prefabLink.prefabHandle,
                        prefabEntityId: prefabLink.prefabEntityId,
                        instanceId: prefabLink.instanceId
                    ),
                    prefabOverrides: prefabOverridesDTO,
                    meshRenderer: shouldSerializeOverride(.meshRenderer, for: entity)
                        ? ecs.get(MeshRendererComponent.self, for: entity).map { component in
                            MeshRendererComponentDTO(
                                meshHandle: component.meshHandle,
                                materialHandle: component.materialHandle,
                                submeshMaterialHandles: component.submeshMaterialHandles,
                                material: component.material.map { MaterialDTO(material: $0) },
                                albedoMapHandle: component.albedoMapHandle,
                                normalMapHandle: component.normalMapHandle,
                                metallicMapHandle: component.metallicMapHandle,
                                roughnessMapHandle: component.roughnessMapHandle,
                                mrMapHandle: component.mrMapHandle,
                                ormMapHandle: component.ormMapHandle,
                                aoMapHandle: component.aoMapHandle,
                                emissiveMapHandle: component.emissiveMapHandle
                            )
                        }
                        : nil,
                    materialComponent: shouldSerializeOverride(.material, for: entity)
                        ? ecs.get(MaterialComponent.self, for: entity).map { MaterialComponentDTO(materialHandle: $0.materialHandle) }
                        : nil,
                    rigidbody: shouldSerializeOverride(.rigidbody, for: entity)
                        ? ecs.get(RigidbodyComponent.self, for: entity).map { component in
                            RigidbodyComponentDTO(
                                enabled: component.isEnabled,
                                motionType: component.motionType.rawValue,
                                mass: component.mass,
                                friction: component.friction,
                                restitution: component.restitution,
                                linearDamping: component.linearDamping,
                                angularDamping: component.angularDamping,
                                gravityFactor: component.gravityFactor,
                                allowSleeping: component.allowSleeping,
                                ccdEnabled: component.ccdEnabled,
                                collisionLayer: component.collisionLayer
                            )
                        }
                        : nil,
                    collider: shouldSerializeOverride(.collider, for: entity)
                        ? ecs.get(ColliderComponent.self, for: entity).map { component in
                            ColliderComponentDTO(component: component)
                        }
                        : nil,
                    light: shouldSerializeOverride(.light, for: entity)
                        ? ecs.get(LightComponent.self, for: entity).map { component in
                            LightComponentDTO(
                                type: LightTypeDTO(from: component.type),
                                data: LightDataDTO(from: component.data),
                                direction: Vector3DTO(component.direction),
                                range: component.range,
                                innerConeCos: component.innerConeCos,
                                outerConeCos: component.outerConeCos,
                                castsShadows: component.castsShadows
                            )
                        }
                        : nil,
                    lightOrbit: shouldSerializeOverride(.lightOrbit, for: entity)
                        ? ecs.get(LightOrbitComponent.self, for: entity).map { LightOrbitComponentDTO(component: $0) }
                        : nil,
                    camera: shouldSerializeOverride(.camera, for: entity)
                        ? ecs.get(CameraComponent.self, for: entity).map { CameraComponentDTO(component: $0) }
                        : nil,
                    script: shouldSerializeOverride(.script, for: entity)
                        ? ecs.get(ScriptComponent.self, for: entity).map { ScriptComponentDTO(component: $0) }
                        : nil,
                    characterController: ecs.get(CharacterControllerComponent.self, for: entity).map { CharacterControllerComponentDTO(component: $0) },
                    sky: shouldSerializeOverride(.sky, for: entity)
                        ? ecs.get(SkyComponent.self, for: entity).map { SkyComponentDTO(environmentMapHandle: $0.environmentMapHandle) }
                        : nil,
                    skyLight: shouldSerializeOverride(.skyLight, for: entity)
                        ? ecs.get(SkyLightComponent.self, for: entity).map { component in
                            SkyLightComponentDTO(
                                mode: component.mode.rawValue,
                                enabled: component.enabled,
                                intensity: component.intensity,
                                skyTint: Vector3DTO(component.skyTint),
                                turbidity: component.turbidity,
                                azimuthDegrees: component.azimuthDegrees,
                                elevationDegrees: component.elevationDegrees,
                                sunSizeDegrees: component.sunSizeDegrees,
                                zenithTint: Vector3DTO(component.zenithTint),
                                horizonTint: Vector3DTO(component.horizonTint),
                                gradientStrength: component.gradientStrength,
                                hazeDensity: component.hazeDensity,
                                hazeFalloff: component.hazeFalloff,
                                hazeHeight: component.hazeHeight,
                                ozoneStrength: component.ozoneStrength,
                                ozoneTint: Vector3DTO(component.ozoneTint),
                                sunHaloSize: component.sunHaloSize,
                                sunHaloIntensity: component.sunHaloIntensity,
                                sunHaloSoftness: component.sunHaloSoftness,
                                cloudsEnabled: component.cloudsEnabled,
                                cloudsCoverage: component.cloudsCoverage,
                                cloudsSoftness: component.cloudsSoftness,
                                cloudsScale: component.cloudsScale,
                                cloudsSpeed: component.cloudsSpeed,
                                cloudsWindX: component.cloudsWindDirection.x,
                                cloudsWindY: component.cloudsWindDirection.y,
                                cloudsHeight: component.cloudsHeight,
                                cloudsThickness: component.cloudsThickness,
                                cloudsBrightness: component.cloudsBrightness,
                                cloudsSunInfluence: component.cloudsSunInfluence,
                                hdriHandle: component.hdriHandle,
                                realtimeUpdate: component.realtimeUpdate
                            )
                        }
                        : nil,
                    skyLightTag: shouldSerializeOverride(.skyLightTag, for: entity) && ecs.has(SkyLightTag.self, entity) ? TagComponentDTO() : nil,
                    skySunTag: shouldSerializeOverride(.skySunTag, for: entity) && ecs.has(SkySunTag.self, entity) ? TagComponentDTO() : nil
                )
                return EntityDocument(id: entity.id, parentId: parentId, components: components)
            }

            let components = ComponentsDocument(
                name: ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) },
                transform: transformDTO(for: entity),
                layer: ecs.get(LayerComponent.self, for: entity).map { component in
                    LayerComponentDTO(layerIndex: component.index)
                },
                meshRenderer: ecs.get(MeshRendererComponent.self, for: entity).map { component in
                    MeshRendererComponentDTO(
                        meshHandle: component.meshHandle,
                        materialHandle: component.materialHandle,
                        submeshMaterialHandles: component.submeshMaterialHandles,
                        material: component.material.map { MaterialDTO(material: $0) },
                        albedoMapHandle: component.albedoMapHandle,
                        normalMapHandle: component.normalMapHandle,
                        metallicMapHandle: component.metallicMapHandle,
                        roughnessMapHandle: component.roughnessMapHandle,
                        mrMapHandle: component.mrMapHandle,
                        ormMapHandle: component.ormMapHandle,
                        aoMapHandle: component.aoMapHandle,
                        emissiveMapHandle: component.emissiveMapHandle
                    )
                },
                materialComponent: ecs.get(MaterialComponent.self, for: entity).map { component in
                    MaterialComponentDTO(materialHandle: component.materialHandle)
                },
                rigidbody: ecs.get(RigidbodyComponent.self, for: entity).map { component in
                    RigidbodyComponentDTO(
                        enabled: component.isEnabled,
                        motionType: component.motionType.rawValue,
                        mass: component.mass,
                        friction: component.friction,
                        restitution: component.restitution,
                        linearDamping: component.linearDamping,
                        angularDamping: component.angularDamping,
                        gravityFactor: component.gravityFactor,
                        allowSleeping: component.allowSleeping,
                        ccdEnabled: component.ccdEnabled,
                        collisionLayer: component.collisionLayer
                    )
                },
                collider: ecs.get(ColliderComponent.self, for: entity).map { component in
                    ColliderComponentDTO(component: component)
                },
                light: ecs.get(LightComponent.self, for: entity).map { component in
                    LightComponentDTO(
                        type: LightTypeDTO(from: component.type),
                        data: LightDataDTO(from: component.data),
                        direction: Vector3DTO(component.direction),
                        range: component.range,
                        innerConeCos: component.innerConeCos,
                        outerConeCos: component.outerConeCos,
                        castsShadows: component.castsShadows
                    )
                },
                lightOrbit: ecs.get(LightOrbitComponent.self, for: entity).map { component in
                    LightOrbitComponentDTO(component: component)
                },
                camera: ecs.get(CameraComponent.self, for: entity).map { component in
                    CameraComponentDTO(component: component)
                },
                script: ecs.get(ScriptComponent.self, for: entity).map { component in
                    ScriptComponentDTO(component: component)
                },
                characterController: ecs.get(CharacterControllerComponent.self, for: entity).map { component in
                    CharacterControllerComponentDTO(component: component)
                },
                sky: ecs.get(SkyComponent.self, for: entity).map { component in
                    SkyComponentDTO(environmentMapHandle: component.environmentMapHandle)
                },
                skyLight: ecs.get(SkyLightComponent.self, for: entity).map { component in
                    SkyLightComponentDTO(
                        mode: component.mode.rawValue,
                        enabled: component.enabled,
                        intensity: component.intensity,
                        skyTint: Vector3DTO(component.skyTint),
                        turbidity: component.turbidity,
                        azimuthDegrees: component.azimuthDegrees,
                        elevationDegrees: component.elevationDegrees,
                        sunSizeDegrees: component.sunSizeDegrees,
                        zenithTint: Vector3DTO(component.zenithTint),
                        horizonTint: Vector3DTO(component.horizonTint),
                        gradientStrength: component.gradientStrength,
                        hazeDensity: component.hazeDensity,
                        hazeFalloff: component.hazeFalloff,
                        hazeHeight: component.hazeHeight,
                        ozoneStrength: component.ozoneStrength,
                        ozoneTint: Vector3DTO(component.ozoneTint),
                        sunHaloSize: component.sunHaloSize,
                        sunHaloIntensity: component.sunHaloIntensity,
                        sunHaloSoftness: component.sunHaloSoftness,
                        cloudsEnabled: component.cloudsEnabled,
                        cloudsCoverage: component.cloudsCoverage,
                        cloudsSoftness: component.cloudsSoftness,
                        cloudsScale: component.cloudsScale,
                        cloudsSpeed: component.cloudsSpeed,
                        cloudsWindX: component.cloudsWindDirection.x,
                        cloudsWindY: component.cloudsWindDirection.y,
                        cloudsHeight: component.cloudsHeight,
                        cloudsThickness: component.cloudsThickness,
                        cloudsBrightness: component.cloudsBrightness,
                        cloudsSunInfluence: component.cloudsSunInfluence,
                        hdriHandle: component.hdriHandle,
                        realtimeUpdate: component.realtimeUpdate
                    )
                },
                skyLightTag: ecs.get(SkyLightTag.self, for: entity).map { _ in TagComponentDTO() },
                skySunTag: ecs.get(SkySunTag.self, for: entity).map { _ in TagComponentDTO() }
            )
            return EntityDocument(id: entity.id, parentId: parentId, components: components)
        }
        return SceneDocument(
            id: id,
            name: name,
            entities: entities,
            rendererSettingsOverride: rendererSettingsOverride,
            physicsSettingsOverride: physicsSettingsOverride
        )
    }

    public func apply(document: SceneDocument) {
        ecs.clear()
        name = document.name
        let physicsDefaults = engineContext?.physicsSettings ?? PhysicsSettings()
        var prefabHandles = Set<AssetHandle>()
        var entitiesById: [UUID: Entity] = [:]
        for entityDoc in document.entities {
            let entity = ecs.createEntity(id: entityDoc.id, name: entityDoc.components.name?.name)
            entitiesById[entity.id] = entity
            if let transform = entityDoc.components.transform {
                let component = TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotationQuat.toSIMD(),
                    scale: transform.scale.toSIMD()
                )
                ecs.add(component, to: entity)
            } else {
                ecs.add(TransformComponent(), to: entity)
            }

            if let prefabLink = entityDoc.components.prefabLink {
                let component = PrefabInstanceComponent(
                    prefabHandle: prefabLink.prefabHandle,
                    prefabEntityId: prefabLink.prefabEntityId,
                    instanceId: prefabLink.instanceId
                )
                ecs.add(component, to: entity)
                prefabHandles.insert(prefabLink.prefabHandle)
                if let overrides = entityDoc.components.prefabOverrides {
                    let overrideSet = Set(overrides.overriddenComponents.compactMap { PrefabOverrideType(rawValue: $0) })
                    ecs.add(PrefabOverrideComponent(overridden: overrideSet), to: entity)
                }
                if let layer = entityDoc.components.layer {
                    ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
                }
                if let name = entityDoc.components.name {
                    ecs.add(NameComponent(name: name.name), to: entity)
                }
                if let meshRenderer = entityDoc.components.meshRenderer {
                    let component = MeshRendererComponent(
                        meshHandle: meshRenderer.meshHandle,
                        materialHandle: meshRenderer.materialHandle,
                        submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                        material: meshRenderer.material?.toMaterial(),
                        albedoMapHandle: meshRenderer.albedoMapHandle,
                        normalMapHandle: meshRenderer.normalMapHandle,
                        metallicMapHandle: meshRenderer.metallicMapHandle,
                        roughnessMapHandle: meshRenderer.roughnessMapHandle,
                        mrMapHandle: meshRenderer.mrMapHandle,
                        ormMapHandle: meshRenderer.ormMapHandle,
                        aoMapHandle: meshRenderer.aoMapHandle,
                        emissiveMapHandle: meshRenderer.emissiveMapHandle
                    )
                    ecs.add(component, to: entity)
                }
                if let materialComponent = entityDoc.components.materialComponent {
                    ecs.add(MaterialComponent(materialHandle: materialComponent.materialHandle), to: entity)
                }
                if let rigidbody = entityDoc.components.rigidbody {
                    ecs.add(rigidbody.toComponent(defaults: physicsDefaults), to: entity)
                }
                if let collider = entityDoc.components.collider {
                    ecs.add(collider.toComponent(), to: entity)
                }
                if let light = entityDoc.components.light {
                    let component = LightComponent(
                        type: light.type.toLightType(),
                        data: light.data.toLightData(),
                        direction: light.direction.toSIMD(),
                        range: light.range,
                        innerConeCos: light.innerConeCos,
                        outerConeCos: light.outerConeCos,
                        castsShadows: light.castsShadows
                    )
                    ecs.add(component, to: entity)
#if DEBUG
                    MC_ASSERT(component.castsShadows == light.castsShadows, "Light castsShadows mismatch after load.")
#endif
                }
                if let lightOrbit = entityDoc.components.lightOrbit {
                    ecs.add(lightOrbit.toComponent(), to: entity)
                }
                if let camera = entityDoc.components.camera {
                    ecs.add(camera.toComponent(), to: entity)
                }
                if let script = entityDoc.components.script {
                    ecs.add(script.toComponent(), to: entity)
                }
                if let controller = entityDoc.components.characterController {
                    ecs.add(controller.toComponent(), to: entity)
                }
                if let sky = entityDoc.components.sky {
                    ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
                }
                if let skyLight = entityDoc.components.skyLight {
                    let component = SkyLightComponent(
                        mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
                        enabled: skyLight.enabled,
                        intensity: skyLight.intensity,
                        skyTint: skyLight.skyTint.toSIMD(),
                        turbidity: skyLight.turbidity,
                        azimuthDegrees: skyLight.azimuthDegrees,
                        elevationDegrees: skyLight.elevationDegrees,
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                        needsRebuild: true,
                        rebuildRequested: false,
                        realtimeUpdate: skyLight.realtimeUpdate,
                        lastRebuildTime: 0.0
                    )
                    ecs.add(component, to: entity)
                }
                if entityDoc.components.skyLightTag != nil {
                    ecs.add(SkyLightTag(), to: entity)
                }
                if entityDoc.components.skySunTag != nil {
                    ecs.add(SkySunTag(), to: entity)
                }
                continue
            }

            if let layer = entityDoc.components.layer {
                ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                ecs.add(LayerComponent(), to: entity)
            }
            if let meshRenderer = entityDoc.components.meshRenderer {
                let component = MeshRendererComponent(
                    meshHandle: meshRenderer.meshHandle,
                    materialHandle: meshRenderer.materialHandle,
                    submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                    material: meshRenderer.material?.toMaterial(),
                    albedoMapHandle: meshRenderer.albedoMapHandle,
                    normalMapHandle: meshRenderer.normalMapHandle,
                    metallicMapHandle: meshRenderer.metallicMapHandle,
                    roughnessMapHandle: meshRenderer.roughnessMapHandle,
                    mrMapHandle: meshRenderer.mrMapHandle,
                    ormMapHandle: meshRenderer.ormMapHandle,
                    aoMapHandle: meshRenderer.aoMapHandle,
                    emissiveMapHandle: meshRenderer.emissiveMapHandle
                )
                ecs.add(component, to: entity)
            }
            if let materialComponent = entityDoc.components.materialComponent {
                let component = MaterialComponent(materialHandle: materialComponent.materialHandle)
                ecs.add(component, to: entity)
            }
            if let rigidbody = entityDoc.components.rigidbody {
                ecs.add(rigidbody.toComponent(defaults: physicsDefaults), to: entity)
            }
            if let collider = entityDoc.components.collider {
                ecs.add(collider.toComponent(), to: entity)
            }
            if let light = entityDoc.components.light {
                let component = LightComponent(
                    type: light.type.toLightType(),
                    data: light.data.toLightData(),
                    direction: light.direction.toSIMD(),
                    range: light.range,
                    innerConeCos: light.innerConeCos,
                    outerConeCos: light.outerConeCos,
                    castsShadows: light.castsShadows
                )
                ecs.add(component, to: entity)
            }
            if let lightOrbit = entityDoc.components.lightOrbit {
                ecs.add(lightOrbit.toComponent(), to: entity)
            }
            if let camera = entityDoc.components.camera {
                ecs.add(camera.toComponent(), to: entity)
            }
            if let rigidbody = entityDoc.components.rigidbody {
                ecs.add(rigidbody.toComponent(), to: entity)
            }
            if let collider = entityDoc.components.collider {
                ecs.add(collider.toComponent(), to: entity)
            }
            if let script = entityDoc.components.script {
                ecs.add(script.toComponent(), to: entity)
            }
            if let controller = entityDoc.components.characterController {
                ecs.add(controller.toComponent(), to: entity)
            }
            if let sky = entityDoc.components.sky {
                ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
            }
            if let skyLight = entityDoc.components.skyLight {
                let component = SkyLightComponent(
                    mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
                    enabled: skyLight.enabled,
                    intensity: skyLight.intensity,
                    skyTint: skyLight.skyTint.toSIMD(),
                    turbidity: skyLight.turbidity,
                    azimuthDegrees: skyLight.azimuthDegrees,
                    elevationDegrees: skyLight.elevationDegrees,
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                    needsRebuild: true,
                    rebuildRequested: false,
                    realtimeUpdate: skyLight.realtimeUpdate,
                    lastRebuildTime: 0.0
                )
                ecs.add(component, to: entity)
            }
            if entityDoc.components.skyLightTag != nil {
                ecs.add(SkyLightTag(), to: entity)
            }
            if entityDoc.components.skySunTag != nil {
                ecs.add(SkySunTag(), to: entity)
            }
        }
        // Rebuild hierarchy in stored order. Missing parent IDs are treated as roots.
        for entityDoc in document.entities {
            guard let entity = entitiesById[entityDoc.id] else { continue }
            if let parentId = entityDoc.parentId, let parent = entitiesById[parentId] {
                _ = ecs.setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = ecs.unparent(entity, keepWorldTransform: false)
            }
        }
        if !prefabHandles.isEmpty {
            prefabSystem?.applyPrefabs(handles: prefabHandles, to: self)
        }
        ensureCameraEntity()
        _editorCameraController.reset()
    }

    @discardableResult
    public func instantiate(prefab: PrefabDocument, prefabHandle: AssetHandle?) -> [Entity] {
        var created: [Entity] = []
        created.reserveCapacity(prefab.entities.count)
        let instanceId = UUID()
        var entityByLocalId: [UUID: Entity] = [:]

        for entityDoc in prefab.entities {
            let entityName = entityDoc.components.name?.name ?? "Entity"
            let entity = ecs.createEntity(name: entityName)
            created.append(entity)
            entityByLocalId[entityDoc.localId] = entity

            if let transform = entityDoc.components.transform {
                let component = TransformComponent(
                    position: transform.position.toSIMD(),
                    rotation: transform.rotationQuat.toSIMD(),
                    scale: transform.scale.toSIMD()
                )
                ecs.add(component, to: entity)
            } else {
                ecs.add(TransformComponent(), to: entity)
            }
            if let layer = entityDoc.components.layer {
                ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
            } else {
                ecs.add(LayerComponent(), to: entity)
            }
            if let prefabHandle {
                let link = PrefabInstanceComponent(prefabHandle: prefabHandle, prefabEntityId: entityDoc.localId, instanceId: instanceId)
                ecs.add(link, to: entity)
            } else {
                EngineLoggerContext.log(
                    "Prefab instantiate missing handle for \(prefab.name)",
                    level: .warning,
                    category: .scene
                )
            }
            if let meshRenderer = entityDoc.components.meshRenderer {
                let component = MeshRendererComponent(
                    meshHandle: meshRenderer.meshHandle,
                    materialHandle: meshRenderer.materialHandle,
                    submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                    material: meshRenderer.material?.toMaterial(),
                    albedoMapHandle: meshRenderer.albedoMapHandle,
                    normalMapHandle: meshRenderer.normalMapHandle,
                    metallicMapHandle: meshRenderer.metallicMapHandle,
                    roughnessMapHandle: meshRenderer.roughnessMapHandle,
                    mrMapHandle: meshRenderer.mrMapHandle,
                    ormMapHandle: meshRenderer.ormMapHandle,
                    aoMapHandle: meshRenderer.aoMapHandle,
                    emissiveMapHandle: meshRenderer.emissiveMapHandle
                )
                ecs.add(component, to: entity)
            }
            if let materialComponent = entityDoc.components.materialComponent {
                let component = MaterialComponent(materialHandle: materialComponent.materialHandle)
                ecs.add(component, to: entity)
            }
            if let light = entityDoc.components.light {
                let component = LightComponent(
                    type: light.type.toLightType(),
                    data: light.data.toLightData(),
                    direction: light.direction.toSIMD(),
                    range: light.range,
                    innerConeCos: light.innerConeCos,
                    outerConeCos: light.outerConeCos
                )
                ecs.add(component, to: entity)
            }
            if let lightOrbit = entityDoc.components.lightOrbit {
                ecs.add(lightOrbit.toComponent(), to: entity)
            }
            if let camera = entityDoc.components.camera {
                ecs.add(camera.toComponent(), to: entity)
            }
            if let script = entityDoc.components.script {
                ecs.add(script.toComponent(), to: entity)
            }
            if let sky = entityDoc.components.sky {
                ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
            }
            if let skyLight = entityDoc.components.skyLight {
                let component = SkyLightComponent(
                    mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
                    enabled: skyLight.enabled,
                    intensity: skyLight.intensity,
                    skyTint: skyLight.skyTint.toSIMD(),
                    turbidity: skyLight.turbidity,
                    azimuthDegrees: skyLight.azimuthDegrees,
                    elevationDegrees: skyLight.elevationDegrees,
                    sunSizeDegrees: skyLight.sunSizeDegrees,
                    zenithTint: skyLight.zenithTint.toSIMD(),
                    horizonTint: skyLight.horizonTint.toSIMD(),
                    gradientStrength: skyLight.gradientStrength,
                    hazeDensity: skyLight.hazeDensity,
                    hazeFalloff: skyLight.hazeFalloff,
                    hazeHeight: skyLight.hazeHeight,
                    ozoneStrength: skyLight.ozoneStrength,
                    ozoneTint: skyLight.ozoneTint.toSIMD(),
                    sunHaloSize: skyLight.sunHaloSize,
                    sunHaloIntensity: skyLight.sunHaloIntensity,
                    sunHaloSoftness: skyLight.sunHaloSoftness,
                    cloudsEnabled: skyLight.cloudsEnabled,
                    cloudsCoverage: skyLight.cloudsCoverage,
                    cloudsSoftness: skyLight.cloudsSoftness,
                    cloudsScale: skyLight.cloudsScale,
                    cloudsSpeed: skyLight.cloudsSpeed,
                    cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                    cloudsHeight: skyLight.cloudsHeight,
                    cloudsThickness: skyLight.cloudsThickness,
                    cloudsBrightness: skyLight.cloudsBrightness,
                    cloudsSunInfluence: skyLight.cloudsSunInfluence,
                    hdriHandle: skyLight.hdriHandle,
                    needsRebuild: true,
                    rebuildRequested: false,
                    realtimeUpdate: skyLight.realtimeUpdate,
                    lastRebuildTime: 0.0
                )
                ecs.add(component, to: entity)
            }
            if entityDoc.components.skyLightTag != nil {
                ecs.add(SkyLightTag(), to: entity)
            }
            if entityDoc.components.skySunTag != nil {
                ecs.add(SkySunTag(), to: entity)
            }
        }

        for entityDoc in prefab.entities {
            guard let entity = entityByLocalId[entityDoc.localId] else { continue }
            if let parentLocalId = entityDoc.parentLocalId,
               let parent = entityByLocalId[parentLocalId] {
                _ = ecs.setParent(entity, parent, keepWorldTransform: false)
            } else {
                _ = ecs.unparent(entity, keepWorldTransform: false)
            }
        }

        ensureCameraEntity()
        return created
    }

    private func ensureCameraEntity() {
        if findEditorCamera() != nil { return }
        let entity = ecs.createEntity(name: "Editor Camera")
        ecs.add(TransformComponent(position: SIMD3<Float>(0, 3, 10)), to: entity)
        ecs.add(CameraComponent(isPrimary: true, isEditor: true), to: entity)
    }

    private func updateCamera(isPlaying: Bool, frame: FrameContext) {
        guard var active = resolveActiveCamera(isPlaying: isPlaying) else { return }
        if active.shouldUpdateEditorCamera {
            _editorCameraController.update(transform: &active.transform, frame: frame)
            ecs.add(active.transform, to: active.entity)
        }
        let worldTransform = ecs.worldTransform(for: active.entity)
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
                        ecs.add(transform, to: entity)
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
            ecs.add(transform, to: entity)

            if orbit.affectsDirection,
               let light = ecs.get(LightComponent.self, for: entity),
               light.type == .spot {
                let direction = centerPosition - transform.position
                if simd_length_squared(direction) > 0 {
                    transform.rotation = TransformMath.rotationForDirectionalLight(direction: simd_normalize(direction))
                    ecs.add(transform, to: entity)
                }
            }
        }
    }

    private func syncLights() {
        var lightData: [LightData] = []
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
                data.direction = TransformMath.directionalLightDirection(from: worldTransform.rotation)
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

    func getCachedBatchResult() -> Any? {
        _cachedBatchResult
    }

    func setCachedBatchResult(_ result: Any?) {
        _cachedBatchResult = result
    }

    func getCachedBatchFrameToken() -> UInt64 {
        _cachedBatchFrameToken
    }

    func setCachedBatchFrameToken(_ token: UInt64) {
        _cachedBatchFrameToken = token
    }

}
