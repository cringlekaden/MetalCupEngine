/// TransformAuthorityService.swift
/// Central authority for transform mutation routing and local/world conversion.
/// Created by Kaden Cringle.

import Foundation
import simd

public final class TransformAuthorityService {
    private unowned let scene: EngineScene
    private var illegalScriptTransformWarnings: Set<UUID> = []
#if DEBUG
    private var debugFrameBaseline: [UUID: TransformComponent] = [:]
    private var debugAuthorizedWrites: Set<UUID> = []
#endif

    public init(scene: EngineScene) {
        self.scene = scene
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
        guard var localTransform = scene.ecs.get(TransformComponent.self, for: entity) else { return false }
        let rigidbody = scene.ecs.get(RigidbodyComponent.self, for: entity)

        if let rigidbody, rigidbody.isEnabled {
            switch rigidbody.motionType {
            case .dynamic:
                if source != .physics {
                    if source == .script,
                       illegalScriptTransformWarnings.insert(entity.id).inserted {
                        EngineLoggerContext.log("Script attempted direct transform write on dynamic body \(entity.id.uuidString). Routed to physics body transform.",
                                                level: .warning,
                                                category: .scene)
                    }
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
}
