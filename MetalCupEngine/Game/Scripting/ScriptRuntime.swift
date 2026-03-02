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
private typealias LuaEntityMoveCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Float, Float, Float) -> Void
private typealias LuaEntityJumpCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
private typealias LuaEntityIsGroundedCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UInt32
private typealias LuaAssetGetNameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int32) -> UInt32

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
                                 _ setTransformCallback: LuaEntitySetTransformCallback?,
                                 _ moveCallback: LuaEntityMoveCallback?,
                                 _ jumpCallback: LuaEntityJumpCallback?,
                                 _ isGroundedCallback: LuaEntityIsGroundedCallback?,
                                 _ assetGetNameCallback: LuaAssetGetNameCallback?) -> UnsafeMutableRawPointer?

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

@_silgen_name("MCELuaRuntimeStartInstance")
private func MCELuaRuntimeStartInstance(_ runtime: UnsafeMutableRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                        _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeHasInstance")
private func MCELuaRuntimeHasInstance(_ runtime: UnsafeMutableRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?) -> UInt32

@_silgen_name("MCELuaRuntimeDispatchPhysicsEvent")
private func MCELuaRuntimeDispatchPhysicsEvent(_ runtime: UnsafeMutableRawPointer?,
                                               _ entityId: UnsafePointer<CChar>?,
                                               _ phase: UnsafePointer<CChar>?,
                                               _ otherEntityId: UnsafePointer<CChar>?,
                                               _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                               _ errorBufferSize: Int32) -> UInt32

@_silgen_name("MCELuaRuntimeSetField")
private func MCELuaRuntimeSetField(_ runtime: UnsafeMutableRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ fieldName: UnsafePointer<CChar>?,
                                   _ fieldType: Int32,
                                   _ intValue: Int32,
                                   _ numberValue: Float,
                                   _ boolValue: UInt32,
                                   _ stringValue: UnsafePointer<CChar>?,
                                   _ vecX: Float,
                                   _ vecY: Float,
                                   _ vecZ: Float) -> UInt32

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

private enum ScriptLifecycleState: UInt8 {
    case uninitialized
    case created
    case started
    case running
    case faulted
    case destroyed
}

public final class LuaScriptRuntime: ScriptRuntime {
    fileprivate weak var engineContext: EngineContext?
    private weak var activeScene: EngineScene?
    private var runtimeHandle: UnsafeMutableRawPointer?
    private var trackedBindings: [UUID: ScriptBindingState] = [:]
    private var lifecycleStates: [UUID: ScriptLifecycleState] = [:]

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
        lifecycleStates.removeAll(keepingCapacity: true)
        instantiateAllScripts(scene: scene)
    }

    public func onSceneStop(scene: EngineScene) {
        destroyAllInstances(scene: scene)
        trackedBindings.removeAll(keepingCapacity: true)
        lifecycleStates.removeAll(keepingCapacity: true)
        activeScene = nil
        teardownRuntime()
    }

    public func onEntityCreated(entityId: UUID) {}

    public func onEntityDestroyed(entityId: UUID) {
        guard runtimeHandle != nil else { return }
        destroyInstance(entityId: entityId)
        trackedBindings.removeValue(forKey: entityId)
        lifecycleStates[entityId] = .destroyed
    }

    public func onComponentAdded(entityId: UUID, type: SceneECSComponentType) {
        guard type == .script,
              let scene = activeScene,
              runtimeHandle != nil,
              let entity = scene.ecs.entity(with: entityId),
              let component = scene.ecs.get(ScriptComponent.self, for: entity) else { return }
        trackedBindings[entityId] = ScriptBindingState(enabled: component.enabled, handle: component.scriptAssetHandle)
        lifecycleStates[entityId] = .uninitialized
        instantiateOrRefresh(entity: entity, component: component, forceReload: true)
    }

    public func onComponentRemoved(entityId: UUID, type: SceneECSComponentType) {
        guard type == .script else { return }
        destroyInstance(entityId: entityId)
        trackedBindings.removeValue(forKey: entityId)
        lifecycleStates[entityId] = .destroyed
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

    public func onPhysicsEvents(events: [PhysicsScriptEvent]) {
        guard let runtimeHandle, !events.isEmpty else { return }
        var errorBuffer = [CChar](repeating: 0, count: 2048)
        for event in events {
            let phase: String
            switch event.type {
            case .collisionEnter: phase = "OnCollisionEnter"
            case .collisionStay: phase = "OnCollisionStay"
            case .collisionExit: phase = "OnCollisionExit"
            case .triggerEnter: phase = "OnTriggerEnter"
            case .triggerStay: phase = "OnTriggerStay"
            case .triggerExit: phase = "OnTriggerExit"
            }

            dispatchPhysicsEvent(runtimeHandle: runtimeHandle,
                                 target: event.entityA,
                                 phase: phase,
                                 other: event.entityB,
                                 errorBuffer: &errorBuffer)
            dispatchPhysicsEvent(runtimeHandle: runtimeHandle,
                                 target: event.entityB,
                                 phase: phase,
                                 other: event.entityA,
                                 errorBuffer: &errorBuffer)
        }
    }

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
                                            MCELuaHostEntitySetTransform,
                                            MCELuaHostEntityMove,
                                            MCELuaHostEntityJump,
                                            MCELuaHostEntityIsGrounded,
                                            MCELuaHostAssetGetName)
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
            guard lifecycleStates[entity.id] == .running else { return }
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
                lifecycleStates[entity.id] = .faulted
                logScriptError(entityId: entity.id, scriptHandle: component.scriptAssetHandle, message: errorText)
            } else if script.hasInstance {
                script.runtimeState = .loaded
                script.lastError = ""
                script.instanceHandle = 1
                lifecycleStates[entity.id] = .running
            }
            if lifecycleStates[entity.id] == .running {
                applySerializedFields(entityId: entity.id, script: script)
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
        lifecycleStates[entity.id] = .uninitialized

        if !script.enabled {
            script.runtimeState = .disabled
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            lifecycleStates[entity.id] = .destroyed
            return true
        }

        guard let scriptHandle = script.scriptAssetHandle else {
            script.runtimeState = .disabled
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            lifecycleStates[entity.id] = .destroyed
            return false
        }

        guard let scriptURL = engineContext?.assetDatabase?.assetURL(for: scriptHandle) else {
            let message = "Script asset could not be resolved."
            script.runtimeState = .error
            script.lastError = message
            scene.ecs.add(script, to: entity)
            destroyInstance(entityId: entity.id)
            lifecycleStates[entity.id] = .faulted
            logScriptError(entityId: entity.id, scriptHandle: scriptHandle, message: message)
            return false
        }

        refreshFieldMetadataAndDefaults(script: &script, scriptURL: scriptURL)

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
            lifecycleStates[entity.id] = .faulted
            scene.ecs.add(script, to: entity)
            logScriptError(entityId: entity.id, scriptHandle: scriptHandle, message: message)
            return false
        }

        script.runtimeState = .loaded
        script.lastError = ""
        script.hasInstance = true
        script.instanceHandle = 1
        applySerializedFields(entityId: entity.id, script: script)
        var startErrorBuffer = [CChar](repeating: 0, count: 2048)
        let startResult: UInt32 = entity.id.uuidString.withCString { entityIdCString in
            MCELuaRuntimeStartInstance(runtimeHandle,
                                       entityIdCString,
                                       &startErrorBuffer,
                                       Int32(startErrorBuffer.count))
        }
        if startResult == 0 {
            let message = String(cString: startErrorBuffer)
            script.runtimeState = .error
            script.lastError = message
            script.hasInstance = false
            script.instanceHandle = 0
            lifecycleStates[entity.id] = .faulted
            scene.ecs.add(script, to: entity)
            logScriptError(entityId: entity.id, scriptHandle: scriptHandle, message: message)
            return false
        }
        lifecycleStates[entity.id] = .created
        lifecycleStates[entity.id] = .started
        lifecycleStates[entity.id] = .running
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
            lifecycleStates[entity.id] = .destroyed
        }
    }

    private func destroyInstance(entityId: UUID) {
        guard let runtimeHandle else { return }
        var errorBuffer = [CChar](repeating: 0, count: 2048)
        _ = entityId.uuidString.withCString { entityIdCString in
            MCELuaRuntimeDestroyInstance(runtimeHandle, entityIdCString, &errorBuffer, Int32(errorBuffer.count))
        }
        lifecycleStates[entityId] = .destroyed
    }

    private func dispatchPhysicsEvent(runtimeHandle: UnsafeMutableRawPointer,
                                      target: UUID,
                                      phase: String,
                                      other: UUID,
                                      errorBuffer: inout [CChar]) {
        guard lifecycleStates[target] == .running else { return }
        let ok: UInt32 = target.uuidString.withCString { targetCString in
            phase.withCString { phaseCString in
                other.uuidString.withCString { otherCString in
                    MCELuaRuntimeDispatchPhysicsEvent(runtimeHandle,
                                                     targetCString,
                                                     phaseCString,
                                                     otherCString,
                                                     &errorBuffer,
                                                     Int32(errorBuffer.count))
                }
            }
        }
        if ok == 0 {
            lifecycleStates[target] = .faulted
            let errorText = String(cString: errorBuffer)
            logScriptError(entityId: target, scriptHandle: nil, message: errorText)
        }
    }

    private func refreshFieldMetadataAndDefaults(script: inout ScriptComponent, scriptURL _: URL) {
        guard let scriptHandle = script.scriptAssetHandle else {
            script.fieldMetadata = [:]
            script.serializedFields = [:]
            script.fieldData = Data()
            return
        }
        let descriptors = ScriptMetadataCache.shared.descriptors(scriptAssetHandle: scriptHandle,
                                                                 typeName: script.typeName,
                                                                 assetDatabase: engineContext?.assetDatabase)
        guard !descriptors.isEmpty else {
            script.fieldMetadata = [:]
            script.serializedFields = [:]
            script.fieldData = Data()
            return
        }

        let decodedBlob = ScriptFieldBlobCodec.decodeFieldBlobV1(script.fieldData)
        var merged = ScriptFieldBlobCodec.mergedValues(from: script.fieldData, schemaDescriptors: descriptors)
        if !script.serializedFields.isEmpty {
            for descriptor in descriptors {
                guard let legacyValue = script.serializedFields[descriptor.name] else { continue }
                let coercedLegacy = ScriptFieldBlobCodec.coerce(legacyValue, to: descriptor.type) ?? descriptor.defaultValue
                if decodedBlob[descriptor.name] == nil ||
                    shouldPreferLegacyReferenceValue(type: descriptor.type,
                                                     blobValue: merged[descriptor.name],
                                                     legacyValue: coercedLegacy) {
                    merged[descriptor.name] = coercedLegacy
                }
            }
        }
        script.serializedFields = merged
        script.fieldMetadata = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0.metadata) })
        script.fieldData = ScriptFieldBlobCodec.encodeFieldBlobV1(merged, schemaDescriptors: descriptors)
        script.fieldDataVersion = 1
    }

    private func applySerializedFields(entityId: UUID, script: ScriptComponent) {
        guard let runtimeHandle else { return }

        func applyValue(name: String, value: ScriptFieldValue) -> Bool {
            let ok: UInt32 = entityId.uuidString.withCString { entityCString in
                name.withCString { fieldName in
                    switch value {
                    case let .bool(boolean):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 0, 0, 0, boolean ? 1 : 0, nil, 0, 0, 0)
                    case let .int(number):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 1, number, 0, 0, nil, 0, 0, 0)
                    case let .float(number):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 2, 0, number, 0, nil, 0, 0, 0)
                    case let .vec2(vec):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 3, 0, 0, 0, nil, vec.x, vec.y, 0)
                    case let .string(string):
                        return string.withCString { stringCString in
                            MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 6, 0, 0, 0, stringCString, 0, 0, 0)
                        }
                    case let .vec3(vec):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 4, 0, 0, 0, nil, vec.x, vec.y, vec.z)
                    case let .color3(vec):
                        return MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 5, 0, 0, 0, nil, vec.x, vec.y, vec.z)
                    case let .entity(entity):
                        let entityString = entity?.uuidString ?? ""
                        return entityString.withCString { entityValueCString in
                            MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 7, 0, 0, 0, entityValueCString, 0, 0, 0)
                        }
                    case let .prefab(prefab):
                        let prefabString = prefab?.rawValue.uuidString ?? ""
                        return prefabString.withCString { prefabValueCString in
                            MCELuaRuntimeSetField(runtimeHandle, entityCString, fieldName, 8, 0, 0, 0, prefabValueCString, 0, 0, 0)
                        }
                    }
                }
            }
            if ok == 0 {
                lifecycleStates[entityId] = .faulted
                return false
            }
            return true
        }

        guard let scriptHandle = script.scriptAssetHandle else {
            for (name, value) in script.serializedFields.sorted(by: { $0.key < $1.key }) {
                if !applyValue(name: name, value: value) { return }
            }
            return
        }
        let descriptors = ScriptMetadataCache.shared.descriptors(scriptAssetHandle: scriptHandle,
                                                                 typeName: script.typeName,
                                                                 assetDatabase: engineContext?.assetDatabase)
        guard !descriptors.isEmpty else {
            for (name, value) in script.serializedFields.sorted(by: { $0.key < $1.key }) {
                if !applyValue(name: name, value: value) { return }
            }
            return
        }
        let decodedBlob = ScriptFieldBlobCodec.decodeFieldBlobV1(script.fieldData)
        var values = ScriptFieldBlobCodec.mergedValues(from: script.fieldData, schemaDescriptors: descriptors)
        if !script.serializedFields.isEmpty {
            for descriptor in descriptors {
                guard let legacyValue = script.serializedFields[descriptor.name] else { continue }
                let coercedLegacy = ScriptFieldBlobCodec.coerce(legacyValue, to: descriptor.type) ?? descriptor.defaultValue
                if decodedBlob[descriptor.name] == nil ||
                    shouldPreferLegacyReferenceValue(type: descriptor.type,
                                                     blobValue: values[descriptor.name],
                                                     legacyValue: coercedLegacy) {
                    values[descriptor.name] = coercedLegacy
                }
            }
        }
        for descriptor in descriptors {
            let name = descriptor.name
            let value = values[name] ?? descriptor.defaultValue
            if !applyValue(name: name, value: value) { return }
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

    private func shouldPreferLegacyReferenceValue(type: ScriptFieldType,
                                                  blobValue: ScriptFieldValue?,
                                                  legacyValue: ScriptFieldValue) -> Bool {
        switch type {
        case .entity:
            guard case .entity(nil)? = blobValue else { return false }
            if case .entity(let uuid?) = legacyValue { return uuid != UUID(uuidString: "00000000-0000-0000-0000-000000000000") }
            return false
        case .prefab:
            guard case .prefab(nil)? = blobValue else { return false }
            if case .prefab(let handle?) = legacyValue { return handle.rawValue != UUID(uuidString: "00000000-0000-0000-0000-000000000000") }
            return false
        default:
            return false
        }
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

@_cdecl("MCELuaHostAssetGetName")
func MCELuaHostAssetGetName(_ hostContext: UnsafeMutableRawPointer?,
                            _ assetHandleCString: UnsafePointer<CChar>?,
                            _ buffer: UnsafeMutablePointer<CChar>?,
                            _ bufferSize: Int32) -> UInt32 {
    guard let hostContext,
          let assetHandleCString,
          let buffer,
          bufferSize > 0 else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let handleUUID = UUID(uuidString: String(cString: assetHandleCString)),
          let metadata = runtime.engineContext?.assetDatabase?.metadata(for: AssetHandle(rawValue: handleUUID)) else {
        return 0
    }
    let displayName = URL(fileURLWithPath: metadata.sourcePath).lastPathComponent
    return writeCString(displayName, to: buffer, max: bufferSize) > 0 ? 1 : 0
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
    return resolved.scene.setLocalTransform(transform, for: resolved.entity, source: .script) ? 1 : 0
}

@_cdecl("MCELuaHostEntityMove")
func MCELuaHostEntityMove(_ hostContext: UnsafeMutableRawPointer?,
                          _ entityId: UnsafePointer<CChar>?,
                          _ x: Float,
                          _ y: Float,
                          _ z: Float) {
    guard let hostContext else { return }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId) else { return }
    resolved.scene.requestCharacterMove(entityId: resolved.entity.id, direction: SIMD3<Float>(x, y, z))
}

@_cdecl("MCELuaHostEntityJump")
func MCELuaHostEntityJump(_ hostContext: UnsafeMutableRawPointer?,
                          _ entityId: UnsafePointer<CChar>?) {
    guard let hostContext else { return }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId) else { return }
    resolved.scene.requestCharacterJump(entityId: resolved.entity.id)
}

@_cdecl("MCELuaHostEntityIsGrounded")
func MCELuaHostEntityIsGrounded(_ hostContext: UnsafeMutableRawPointer?,
                                _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let hostContext else { return 0 }
    let runtime = Unmanaged<LuaScriptRuntime>.fromOpaque(hostContext).takeUnretainedValue()
    guard let resolved = runtime.callbackEntity(entityId) else { return 0 }
    return resolved.scene.isCharacterGrounded(entityId: resolved.entity.id) ? 1 : 0
}
