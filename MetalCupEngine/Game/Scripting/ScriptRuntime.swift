/// ScriptRuntime.swift
/// Defines scripting lifecycle contracts consumed by a future scripting host.
/// Created by Codex.

import Foundation

public protocol ScriptRuntime: AnyObject {
    func onSceneStart(scene: EngineScene)
    func onSceneStop(scene: EngineScene)
    func onEntityCreated(entityId: UUID)
    func onEntityDestroyed(entityId: UUID)
    func onComponentAdded(entityId: UUID, type: SceneECSComponentType)
    func onComponentRemoved(entityId: UUID, type: SceneECSComponentType)
    func onUpdate(dt: Float)
    func onFixedUpdate(dt: Float)
    func onLateUpdate(dt: Float)
    func onPhysicsEvents(events: [PhysicsScriptEvent])
}

public final class NullScriptRuntime: ScriptRuntime {
    public init() {}

    public func onSceneStart(scene: EngineScene) {}
    public func onSceneStop(scene: EngineScene) {}
    public func onEntityCreated(entityId: UUID) {}
    public func onEntityDestroyed(entityId: UUID) {}
    public func onComponentAdded(entityId: UUID, type: SceneECSComponentType) {}
    public func onComponentRemoved(entityId: UUID, type: SceneECSComponentType) {}
    public func onUpdate(dt: Float) {}
    public func onFixedUpdate(dt: Float) {}
    public func onLateUpdate(dt: Float) {}
    public func onPhysicsEvents(events: [PhysicsScriptEvent]) {}
}
