/// ScriptSystemAdapter.swift
/// Scene-facing scripting adapter that owns script change dispatch glue.
/// Created by Kaden Cringle.

import Foundation

public final class ScriptSystemAdapter {
    private unowned let scene: EngineScene

    public init(scene: EngineScene) {
        self.scene = scene
    }

    public func onSceneStart() {
        scene.engineContext?.scriptRuntime.onSceneStart(scene: scene)
        dispatchSceneChanges()
    }

    public func onSceneStop() {
        scene.engineContext?.scriptRuntime.onSceneStop(scene: scene)
    }

    public func update(dt: Float, runRuntimeScripts: Bool) {
        dispatchSceneChanges()
        guard runRuntimeScripts else { return }
        scene.engineContext?.scriptRuntime.onUpdate(dt: dt)
    }

    public func fixedUpdate(dt: Float) {
        dispatchSceneChanges()
        guard dt > 0 else { return }
        scene.engineContext?.scriptRuntime.onFixedUpdate(dt: dt)
    }

    public func dispatchPhysicsEvents(_ events: [PhysicsScriptEvent]) {
        guard !events.isEmpty else { return }
        scene.engineContext?.scriptRuntime.onPhysicsEvents(events: events)
    }

    private func dispatchSceneChanges() {
        guard let runtime = scene.engineContext?.scriptRuntime else {
            _ = scene.ecs.drainChanges()
            return
        }
        let changes = scene.ecs.drainChangesDeterministic()
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
            }
        }
    }
}
