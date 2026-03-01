/// ScriptRuntime.swift
/// Defines scripting lifecycle contracts and the Lua runtime host.
/// Created by Codex.

import Foundation
import simd

private typealias LuaLogCallback = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void
private typealias LuaEntityExistsCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UInt32
private typealias LuaEntityGetNameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int32) -> UInt32
private typealias LuaEntityGetTransformCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> UInt32
private typealias LuaEntitySetTransformCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<Float>?, UnsafePointer<Float>?, UnsafePointer<Float>?) -> UInt32

private func writeCString(_ string: String, to buffer: UnsafeMutablePointer<CChar>?, max: Int32) -> Int32 {
    guard let buffer, max > 0 else { return 0 }
    return string.withCString { ptr in
        let length = min(Int(max - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return Int32(length)
    }
}

@_silgen_name("MCELuaRuntimeCreate")
private func MCELuaRuntimeCreate(_ hostContext: UnsafeMutableRawPointer?,
                                 _ logCallback: LuaLogCallback?,
                                 _ existsCallback: LuaEntityExistsCallback?,
                                 _ getNameCallback: LuaEntityGetNameCallback?,
                                 _ getTransformCallback: LuaEntityGetTransformCallback?,
                                 _ setTransformCallback: LuaEntitySetTransformCallback?) -> UnsafeMutableRawPointer?

@_silgen_name("MCELuaRuntimeDestroy")
private func MCELuaRuntimeDestroy(_ runtime: UnsafeMutableRawPointer?)

@_silgen_name("MCELuaRuntimeInstantiate")
private func MCELuaRuntimeInstantiate(_ runtime: UnsafeMutableRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ scriptPath: UnsafePointer<CChar>?,
                                      _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                      _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeReload")
private func MCELuaRuntimeReload(_ runtime: UnsafeMutableRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ scriptPath: UnsafePointer<CChar>?,
                                 _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                 _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeUpdate")
private func MCELuaRuntimeUpdate(_ runtime: UnsafeMutableRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ dt: Float,
                                 _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                 _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeFixedUpdate")
private func MCELuaRuntimeFixedUpdate(_ runtime: UnsafeMutableRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ dt: Float,
                                      _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                      _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeDestroyInstance")
private func MCELuaRuntimeDestroyInstance(_ runtime: UnsafeMutableRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                          _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeHasInstance")
private func MCELuaRuntimeHasInstance(_ runtime: UnsafeMutableRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?) -> UInt32

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

private struct ScriptBindingState: Equatable {
    let enabled: Bool
    let handle: AssetHandle?
}

private enum LuaCallPhase {
    case update
    case fixedUpdate
}

public final class LuaScriptRuntime: ScriptRuntime {
    private weak var engineContext: EngineContext?
    private weak var activeScene: EngineScene?
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var trackedBindings: [UUID: ScriptBindingState] = [:]

    public init(engineContext: EngineContext) {
        self.engineContext = engineContext
    }

    deinit {
        teardownRuntime()
    }

    public func onSceneStart(scene: EngineScene) {
        activeScene = scene
        ensureRuntime()
        trackedBindings.removeAll(keepingCapacity: true)
        instantiateAllScripts(scene: scene)
    }

    public func onSceneStop(scene: EngineScene) {
        destroyAllInstances(scene: scene)
        trackedBindings.removeAll(keepingCapacity: true)
        activeScene = nil
        teardownRuntime()
    }

    public func onEntityCreated(entityId: UUID) {}

    public func onEntityDestroyed(entityId: UUID) {
        guard runtimeHandle != nil else { return }
        destroyInstance(entityId: entityId)
        trackedBindings.removeValue(forKey: entityId)
    }

    public func onComponentAdded(entityId: UUID, type: SceneECSComponentType) {
        guard type == .script,
              let scene = activeScene,
              runtimeHandle != nil,
              let entity = scene.ecs.entity(with: entityId),
              let component = scene.ecs.get(ScriptComponent.self, for: entity) else { return }
        trackedBindings[entityId] = ScriptBindingState(enabled: component.enabled, handle: component.scriptAssetHandle)
        instantiateOrRefresh(entity: entity, component: component, forceReload: true)
    }

    public func onComponentRemoved(entityId: UUID, type: SceneECSComponentType) {
        guard type == .script else { return }
        destroyInstance(entityId: entityId)
        trackedBindings.removeValue(forKey: entityId)
    }

    public func onUpdate(dt: Float) {
        guard let scene = activeScene,
              runtimeHandle != nil else { return }
        syncBindings(scene: scene)
        runScripts(scene: scene, dt: dt, phase: .update)
    }

    public func onFixedUpdate(dt: Float) {
        guard let scene = activeScene,
              runtimeHandle != nil else { return }
        syncBindings(scene: scene)
        runScripts(scene: scene, dt: dt, phase: .fixedUpdate)
    }

    public func onLateUpdate(dt: Float) {}

    public func onPhysicsEvents(events: [PhysicsScriptEvent]) {}

    public func reloadScriptInstance(entityId: UUID) -> Bool {
        guard let scene = activeScene,
              runtimeHandle != nil,
              let entity = scene.ecs.entity(with: entityId),
              let component = scene.ecs.get(ScriptComponent.self, for: entity) else {
            return false
        }
        return instantiateOrRefresh(entity: entity, component: component, forceReload: true)
    }

    private func ensureRuntime() {
        guard runtimeHandle == nil else { return }
        let hostContext = Unmanaged.passUnretained(self).toOpaque()
        runtimeHandle = MCELuaRuntimeCreate(hostContext,
                                            MCELuaHostLog,
                                            MCELuaHostEntityExists,
                                            MCELuaHostEntityGetName,
                                            MCELuaHostEntityGetTransform,
                                            MCELuaHostEntitySetTransform)
    }

    private func teardownRuntime() {
        guard runtimeHandle != nil else { return }
        MCELuaRuntimeDestroy(runtimeHandle)
        runtimeHandle = nil
    }

    private func instantiateAllScripts(scene: EngineScene) {
        scene.ecs.viewDeterministic(ScriptComponent.self) { [weak self] entity, component in
            guard let self else { return }
            trackedBindings[entity.id] = ScriptBindingState(enabled: component.enabled, handle: component.scriptAssetHandle)
            _ = instantiateOrRefresh(entity: entity, component: component, forceReload: true)
        }
    }

    private func syncBindings(scene: EngineScene) {
        var seenEntities: Set<UUID> = []
        scene.ecs.viewDeterministic(ScriptComponent.self) { [weak self] entity, component in
            guard let self else { return }
            seenEntities.insert(entity.id)
            let newBinding = ScriptBindingState(enabled: component.enabled, handle: component.scriptAssetHandle)
            let previous = trackedBindings[entity.id]
            if previous != newBinding {
                _ = instantiateOrRefresh(entity: entity, component: component, forceReload: true)
                trackedBindings[entity.id] = newBinding
            }
        }
        for staleId in trackedBindings.keys where !seenEntities.contains(staleId) {
            destroyInstance(entityId: staleId)
            trackedBindings.removeValue(forKey: staleId)
        }
    }

    private func runScripts(scene: EngineScene, dt: Float, phase: LuaCallPhase) {
        scene.ecs.viewDeterministic(ScriptComponent.self) { [weak self] entity, component in
            guard let self else { return }
            guard component.enabled, component.scriptAssetHandle != nil else { return }
            guard let runtimeHandle else { return }
            var script = component
            let entityId = entity.id.uuidString
            var errorBuffer = [CChar](repeating: 0, count: 2048)
            let ok: UInt32 = entityId.withCString { entityCString in
                switch phase {
                case .update:
                    return MCELuaRuntimeUpdate(runtimeHandle,
                                               entityCString,
                                               dt,
                                               &errorBuffer,
                                               Int32(errorBuffer.count))
                case .fixedUpdate:
                    return MCELuaRuntimeFixedUpdate(runtimeHandle,
                                                    entityCString,
                                                    dt,
                                                    &errorBuffer,
                                                    Int32(errorBuffer.count))
                }
            }
            script.hasInstance = entityId.withCString { entityCString in
                MCELuaRuntimeHasInstance(runtimeHandle, entityCString) != 0
            }
            if ok == 0 {
                let errorText = String(cString: errorBuffer)
                script.runtimeState = .error
                script.lastError = errorText
                script.hasInstance = false
                script.instanceHandle = 0
                logScriptError(entityId: entity.id, scriptHandle: component.scriptAssetHandle, message: errorText)
            } else if script.hasInstance {
                script.runtimeState = .loaded
                script.lastError = ""
                script.instanceHandle = 1
            }
            scene.ecs.add(script, to: entity)
        }
    }

    @discardableResult
    private func instantiateOrRefresh(entity: Entity, component: ScriptComponent, forceReload: Bool) -> Bool {
        guard let scene = activeScene,
              let runtimeHandle else { return false }
        var script = component
        script.lastError = ""
        script.instanceHandle = 0
        script.hasInstance = false

        if !script.enabled {
            script.runtimeState = .disabled
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            return true
        }

        guard let scriptHandle = script.scriptAssetHandle else {
            script.runtimeState = .disabled
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            return false
        }

        guard let scriptURL = engineContext?.assetDatabase?.assetURL(for: scriptHandle) else {
            let message = "Script asset could not be resolved."
            script.runtimeState = .error
            script.lastError = message
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            logScriptError(entityId: entity.id, scriptHandle: scriptHandle, message: message)
            return false
        }

        var errorBuffer = [CChar](repeating: 0, count: 2048)
        let result: UInt32 = entity.id.uuidString.withCString { entityIdCString in
            scriptURL.path.withCString { pathCString in
                if forceReload {
                    return MCELuaRuntimeReload(runtimeHandle,
                                               entityIdCString,
                                               pathCString,
                                               &errorBuffer,
                                               Int32(errorBuffer.count))
                }
                return MCELuaRuntimeInstantiate(runtimeHandle,
                                               entityIdCString,
                                               pathCString,
                                               &errorBuffer,
                                               Int32(errorBuffer.count))
            }
        }

        if result == 0 {
            let message = String(cString: errorBuffer)
            script.runtimeState = .error
            script.lastError = message
            script.hasInstance = false
            script.instanceHandle = 0
            scene.ecs.add(script, to: entity)
            logScriptError(entityId: entity.id, scriptHandle: scriptHandle, message: message)
            return false
        }

        script.runtimeState = .loaded
        script.lastError = ""
        script.hasInstance = true
        script.instanceHandle = 1
        scene.ecs.add(script, to: entity)
        return true
    }

    private func destroyAllInstances(scene: EngineScene) {
        scene.ecs.viewDeterministic(ScriptComponent.self) { [weak self] entity, component in
            guard let self else { return }
            destroyInstance(entityId: entity.id)
            var script = component
            script.runtimeState = script.enabled ? .unloaded : .disabled
            script.hasInstance = false
            script.instanceHandle = 0
            scene.ecs.add(script, to: entity)
        }
    }

    private func destroyInstance(entityId: UUID) {
        guard let runtimeHandle else { return }
        var errorBuffer = [CChar](repeating: 0, count: 2048)
        _ = entityId.uuidString.withCString { entityIdCString in
            MCELuaRuntimeDestroyInstance(runtimeHandle, entityIdCString, &errorBuffer, Int32(errorBuffer.count))
        }
    }

    private func logScriptError(entityId: UUID, scriptHandle: AssetHandle?, message: String) {
        let handleText = scriptHandle?.rawValue.uuidString ?? "None"
        EngineLoggerContext.log("Lua script error [Entity=\(entityId.uuidString), Script=\(handleText)]: \(message)",
                                level: .error,
                                category: .scene)
    }

    fileprivate func callbackEntity(_ idCString: UnsafePointer<CChar>?) -> (scene: EngineScene, entity: Entity)? {
        guard let activeScene,
              let idCString,
              let uuid = UUID(uuidString: String(cString: idCString)),
              let entity = activeScene.ecs.entity(with: uuid) else {
            return nil
        }
        return (activeScene, entity)
    }

    fileprivate func callbackLog(level: Int32, message: String) {
        let resolvedLevel: MCLogLevel
        switch level {
        case 2:
            resolvedLevel = .error
        case 1:
            resolvedLevel = .warning
        default:
            resolvedLevel = .info
        }
        EngineLoggerContext.log("[Lua] \(message)", level: resolvedLevel, category: .scene)
    }
}

@_cdecl("MCELuaHostLog")
func MCELuaHostLog(_ hostContext: UnsafeMutableRawPointer?, _ level: Int32, _ message: UnsafePointer<CChar>?) {
    guard let hostContext else { return }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    runtime.callbackLog(level: level, message: message.map { String(cString: $0) } ?? "")
}

@_cdecl("MCELuaHostEntityExists")
func MCELuaHostEntityExists(_ hostContext: UnsafeMutableRawPointer?, _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let hostContext else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    return runtime.callbackEntity(entityId) != nil ? 1 : 0
}

@_cdecl("MCELuaHostEntityGetName")
func MCELuaHostEntityGetName(_ hostContext: UnsafeMutableRawPointer?,
                             _ entityId: UnsafePointer<CChar>?,
                             _ buffer: UnsafeMutablePointer<CChar>?,
                             _ bufferSize: Int32) -> UInt32 {
    guard let hostContext,
          let buffer,
          bufferSize > 0 else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId) else { return 0 }
    let name = resolved.scene.ecs.get(NameComponent.self, for: resolved.entity)?.name ?? "Entity"
    return writeCString(name, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCELuaHostEntityGetTransform")
func MCELuaHostEntityGetTransform(_ hostContext: UnsafeMutableRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ positionOut: UnsafeMutablePointer<Float>?,
                                  _ rotationEulerOut: UnsafeMutablePointer<Float>?,
                                  _ scaleOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let hostContext,
          let positionOut,
          let rotationEulerOut,
          let scaleOut else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId),
          let transform = resolved.scene.ecs.get(TransformComponent.self, for: resolved.entity) else { return 0 }
    let euler = TransformMath.eulerFromQuaternionXYZ(transform.rotation)
    positionOut[0] = transform.position.x
    positionOut[1] = transform.position.y
    positionOut[2] = transform.position.z
    rotationEulerOut[0] = euler.x
    rotationEulerOut[1] = euler.y
    rotationEulerOut[2] = euler.z
    scaleOut[0] = transform.scale.x
    scaleOut[1] = transform.scale.y
    scaleOut[2] = transform.scale.z
    return 1
}

@_cdecl("MCELuaHostEntitySetTransform")
func MCELuaHostEntitySetTransform(_ hostContext: UnsafeMutableRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ position: UnsafePointer<Float>?,
                                  _ rotationEuler: UnsafePointer<Float>?,
                                  _ scale: UnsafePointer<Float>?) -> UInt32 {
    guard let hostContext,
          let position,
          let rotationEuler,
          let scale else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId) else { return 0 }
    let transform = TransformComponent(position: SIMD3<Float>(position[0], position[1], position[2]),
                                       rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rotationEuler[0], rotationEuler[1], rotationEuler[2])),
                                       scale: SIMD3<Float>(scale[0], scale[1], scale[2]))
    resolved.scene.ecs.add(transform, to: resolved.entity)
    return 1
}
