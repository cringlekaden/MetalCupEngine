/// TransformAuthorityService.swift
/// Central authority for transform mutation routing and local/world conversion.
/// Created by Kaden Cringle.

import Foundation
import simd

#if DEBUG
public enum TransformAuthorityDebug {
    /// Central debug toggle for policy diagnostics. Kept off by default to avoid log clutter.
    public static var policyDiagnosticsEnabled: Bool = false
}
#endif

/// Central authority for all external transform mutation.
/// Rules:
/// - Allowed mutation sources are validated against scene mode (Edit/Play/Simulate).
/// - Parent/local/world conversions are handled only here.
/// - Rigidbody-backed transforms are routed through physics first, then synchronized to ECS local space.
public final class TransformAuthorityService {
    private unowned let scene: EngineScene
    private var forbiddenSourceModeWarnings: Set<String> = []
    private var dynamicRouteWarnings: Set<String> = []

    private static let editAllowedSources: Set<TransformMutationSource> = [
        .editor, .serialization, .prefab, .engineSystem
    ]
    private static let playAllowedSources: Set<TransformMutationSource> = [
        .script, .physics, .characterController, .engineSystem
    ]
    private static let simulateAllowedSources: Set<TransformMutationSource> = [
        .script, .physics, .characterController, .engineSystem
    ]
#if DEBUG
    private var debugFrameBaseline: [UUID: TransformComponent] = [:]
    private var debugAuthorizedWrites: Set<UUID> = []
    private var debugEditorMutationCount: Int = 0
#endif

    public init(scene: EngineScene) {
        self.scene = scene
    }

    @discardableResult
    public func ensureLocalTransform(entity: Entity,
                                     default transform: TransformComponent = TransformComponent(),
                                     source: TransformMutationSource) -> Bool {
        validateMutationSource(source, entity: entity, operation: "ensureLocalTransform")
        if scene.ecs.get(TransformComponent.self, for: entity) == nil {
#if DEBUG
            debugAuthorizedWrites.insert(entity.id)
            if source == .editor {
                debugEditorMutationCount += 1
            }
#endif
            scene.ecs.add(transform, to: entity)
            return true
        }
        return setLocalTransform(entity: entity, transform: transform, source: source)
    }

    @discardableResult
    public func setLocalTransform(entity: Entity,
                                  transform: TransformComponent,
                                  source: TransformMutationSource) -> Bool {
        guard scene.ecs.get(TransformComponent.self, for: entity) != nil else { return false }
        let worldTransform = worldTransform(fromLocal: transform, for: entity)
        return setWorldTransform(entity: entity, transform: worldTransform, source: source)
    }

    @discardableResult
    public func setWorldTransform(entity: Entity,
                                  transform worldTransform: TransformComponent,
                                  source: TransformMutationSource) -> Bool {
        validateMutationSource(source, entity: entity, operation: "setWorldTransform")
        guard var localTransform = scene.ecs.get(TransformComponent.self, for: entity) else { return false }
        let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity)

        if let rigidbody, rigidbody.isEnabled {
            switch rigidbody.motionType {
            case .dynamic:
                if source != .physics {
                    noteDynamicBodyRoute(source: source, entity: entity)
                    let appliedToPhysics = scene.physicsSystem?.setBodyTransform(entity: entity,
                                                                                 scene: scene,
                                                                                 position: worldTransform.position,
                                                                                 rotation: worldTransform.rotation,
                                                                                 activate: true) ?? false
                    if source == .script {
                        return appliedToPhysics
                    }
                }
            case .kinematic:
                if source != .physics {
                    _ = scene.physicsSystem?.setBodyTransform(entity: entity,
                                                              scene: scene,
                                                              position: worldTransform.position,
                                                              rotation: worldTransform.rotation,
                                                              activate: true)
                }
            case .staticBody:
                if source != .physics {
                    _ = scene.physicsSystem?.setBodyTransform(entity: entity,
                                                              scene: scene,
                                                              position: worldTransform.position,
                                                              rotation: worldTransform.rotation,
                                                              activate: false)
                }
            }
        }

        localTransform = self.localTransform(fromWorld: worldTransform, for: entity)
#if DEBUG
        debugAuthorizedWrites.insert(entity.id)
        if source == .editor {
            debugEditorMutationCount += 1
        }
#endif
        scene.ecs.add(localTransform, to: entity)
        return true
    }

    public func worldTransform(fromLocal localTransform: TransformComponent,
                               for entity: Entity) -> TransformComponent {
        guard let parent = scene.ecs.getParent(entity) else { return localTransform }
        let parentWorld = scene.ecs.worldMatrix(for: parent)
        let localMatrix = TransformMath.makeMatrix(position: localTransform.position,
                                                   rotation: localTransform.rotation,
                                                   scale: localTransform.scale)
        let worldMatrix = parentWorld * localMatrix
        let decomposed = TransformMath.decomposeMatrix(worldMatrix)
        return TransformComponent(position: decomposed.position,
                                  rotation: decomposed.rotation,
                                  scale: decomposed.scale)
    }

    public func localTransform(fromWorld worldTransform: TransformComponent,
                               for entity: Entity) -> TransformComponent {
        guard let parent = scene.ecs.getParent(entity) else { return worldTransform }
        let parentWorldMatrix = scene.ecs.worldMatrix(for: parent)
        let desiredWorldMatrix = TransformMath.makeMatrix(position: worldTransform.position,
                                                          rotation: worldTransform.rotation,
                                                          scale: worldTransform.scale)
        let desiredLocalMatrix = simd_inverse(parentWorldMatrix) * desiredWorldMatrix
        let decomposed = TransformMath.decomposeMatrix(desiredLocalMatrix)
        return TransformComponent(position: decomposed.position,
                                  rotation: decomposed.rotation,
                                  scale: decomposed.scale)
    }

#if DEBUG
    public func assertNoExternalTransformWrites() {
        endDebugBypassDetectionFrame()
    }

    public func debugSnapshotEditorMutationCount() -> Int {
        debugEditorMutationCount
    }

    public func beginDebugBypassDetectionFrame() {
        debugAuthorizedWrites.removeAll(keepingCapacity: true)
        debugFrameBaseline.removeAll(keepingCapacity: true)
        for entity in scene.ecs.allEntities() {
            guard let transform = scene.ecs.get(TransformComponent.self, for: entity) else { continue }
            debugFrameBaseline[entity.id] = transform
        }
    }

    public func endDebugBypassDetectionFrame() {
        var bypassedEntityIds: [String] = []
        for entity in scene.ecs.allEntities() {
            guard let before = debugFrameBaseline[entity.id],
                  let after = scene.ecs.get(TransformComponent.self, for: entity) else { continue }
            guard transformChanged(before, after),
                  !debugAuthorizedWrites.contains(entity.id) else { continue }
            bypassedEntityIds.append(entity.id.uuidString)
        }
        if !bypassedEntityIds.isEmpty {
            let entityList = bypassedEntityIds.joined(separator: ", ")
            assertionFailure("EngineScene transform bypass detected; TransformComponent changed outside TransformAuthorityService for entities: \(entityList)")
        }
    }

    private func transformChanged(_ lhs: TransformComponent, _ rhs: TransformComponent) -> Bool {
        let positionDelta = simd_length_squared(lhs.position - rhs.position)
        let scaleDelta = simd_length_squared(lhs.scale - rhs.scale)
        let rotationDot = abs(simd_dot(lhs.rotation, rhs.rotation))
        return positionDelta > 1.0e-12 || scaleDelta > 1.0e-12 || rotationDot < (1.0 - 1.0e-6)
    }
#endif

    private func validateMutationSource(_ source: TransformMutationSource,
                                        entity: Entity,
                                        operation: String) {
        guard !isSourceAllowed(source, in: scene.transformAuthorityMode) else { return }
#if DEBUG
        let key = "\(scene.transformAuthorityMode.description)|\(source.description)|\(operation)|\(entity.id.uuidString)"
        if forbiddenSourceModeWarnings.insert(key).inserted {
            assertionFailure("TransformAuthority policy violation: source \(source.description) attempted \(operation) in \(scene.transformAuthorityMode.description) mode for entity \(entity.id.uuidString).")
        }
        if TransformAuthorityDebug.policyDiagnosticsEnabled {
            EngineLoggerContext.log("TransformAuthority blocked-policy write detected: source=\(source.description) mode=\(scene.transformAuthorityMode.description) operation=\(operation) entity=\(entity.id.uuidString)",
                                    level: .warning,
                                    category: .scene)
        }
#endif
    }

    private func isSourceAllowed(_ source: TransformMutationSource,
                                 in mode: EngineScene.TransformAuthorityMode) -> Bool {
        switch mode {
        case .edit:
            return Self.editAllowedSources.contains(source)
        case .play:
            return Self.playAllowedSources.contains(source)
        case .simulate:
            return Self.simulateAllowedSources.contains(source)
        }
    }

    private func noteDynamicBodyRoute(source: TransformMutationSource, entity: Entity) {
        guard source == .script || source == .editor else { return }
#if DEBUG
        let key = "\(source.description)|\(entity.id.uuidString)"
        guard dynamicRouteWarnings.insert(key).inserted else { return }
        if TransformAuthorityDebug.policyDiagnosticsEnabled {
            EngineLoggerContext.log("TransformAuthority routed \(source.description) transform write for dynamic rigidbody \(entity.id.uuidString) through physics.",
                                    level: .warning,
                                    category: .scene)
        }
#endif
    }
}
