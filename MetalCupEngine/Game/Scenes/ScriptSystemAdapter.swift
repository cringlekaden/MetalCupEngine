/// ScriptSystemAdapter.swift
/// Scene-facing scripting adapter that owns script change dispatch glue.
/// Created by Kaden Cringle.

import Foundation

public final class ScriptSystemAdapter {
    private unowned let scene: EngineScene
    private let eventBus = ScriptEventBus()

    public init(scene: EngineScene) {
        self.scene = scene
    }

    public func onSceneStart() {
        scene.engineContext?.scriptRuntime.onSceneStart(scene: scene)
        eventBus.clear()
        dispatchSceneChanges()
    }

    public func onSceneStop() {
        eventBus.clear()
        scene.engineContext?.scriptRuntime.onSceneStop(scene: scene)
    }

    public func update(dt: Float, runRuntimeScripts: Bool) {
        dispatchSceneChanges()
        guard runRuntimeScripts else { return }
        scene.engineContext?.scriptRuntime.onExecutionGroup(.update, dt: dt)
    }

    public func fixedPrePhysics(dt: Float, executeScripts: Bool) {
        dispatchSceneChanges()
        guard executeScripts, dt > 0 else { return }
        scene.engineContext?.scriptRuntime.onExecutionGroup(.fixedPrePhysics, dt: dt)
    }

    public func enqueuePhysicsEvents(_ events: [PhysicsScriptEvent]) {
        eventBus.enqueuePhysicsEvents(events, domain: .fixedStep)
    }

    public func fixedPostPhysics(dt: Float, executeScripts: Bool, dispatchEvents: Bool) {
        guard executeScripts, dt > 0 else {
            _ = eventBus.drain(domain: .fixedStep)
            return
        }
        guard dispatchEvents else {
            _ = eventBus.drain(domain: .fixedStep)
            return
        }
        let fixedEvents = eventBus.drain(domain: .fixedStep)
        if !fixedEvents.isEmpty {
            scene.engineContext?.scriptRuntime.onEvents(fixedEvents, domain: .fixedStep)
        }
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
