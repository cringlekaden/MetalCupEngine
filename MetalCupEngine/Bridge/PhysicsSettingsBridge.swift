/// PhysicsSettingsBridge.swift
/// Defines the physics settings bridge for editor UI access.
/// Created by Codex.

import Foundation
import simd

private func resolveEngineContext(_ contextPtr: UnsafeRawPointer?) -> EngineContext? {
    guard let contextPtr else { return nil }
    let raw = UInt(bitPattern: contextPtr)
    if raw < 0x1000 {
        #if DEBUG
        assertionFailure("Invalid EngineContext pointer (too small) passed to bridge.")
        #endif
        return nil
    }
    return Unmanaged<EngineContext>.fromOpaque(contextPtr).takeUnretainedValue()
}

@_cdecl("MCEPhysicsGetEnabled")
public func MCEPhysicsGetEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.isEnabled == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetEnabled")
public func MCEPhysicsSetEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.isEnabled = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetGravity")
public func MCEPhysicsGetGravity(_ contextPtr: UnsafeRawPointer?, _ x: UnsafeMutablePointer<Float>?, _ y: UnsafeMutablePointer<Float>?, _ z: UnsafeMutablePointer<Float>?) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    let gravity = context.physicsSettings.gravity
    x?.pointee = gravity.x
    y?.pointee = gravity.y
    z?.pointee = gravity.z
}

@_cdecl("MCEPhysicsSetGravity")
public func MCEPhysicsSetGravity(_ contextPtr: UnsafeRawPointer?, _ x: Float, _ y: Float, _ z: Float) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.gravity = SIMD3<Float>(x, y, z)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetSolverIterations")
public func MCEPhysicsGetSolverIterations(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.solverIterations ?? 1
}

@_cdecl("MCEPhysicsSetSolverIterations")
public func MCEPhysicsSetSolverIterations(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.solverIterations = max(1, value)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetQualityPreset")
public func MCEPhysicsGetQualityPreset(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.qualityPreset.rawValue ?? PhysicsSettings.QualityPreset.medium.rawValue
}

@_cdecl("MCEPhysicsSetQualityPreset")
public func MCEPhysicsSetQualityPreset(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    let preset = PhysicsSettings.QualityPreset(rawValue: value) ?? .medium
    settings.qualityPreset = preset
    settings.solverIterations = preset.solverIterations
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetFixedDeltaTime")
public func MCEPhysicsGetFixedDeltaTime(_ contextPtr: UnsafeRawPointer?) -> Float {
    resolveEngineContext(contextPtr)?.physicsSettings.fixedDeltaTime ?? (1.0 / 60.0)
}

@_cdecl("MCEPhysicsSetFixedDeltaTime")
public func MCEPhysicsSetFixedDeltaTime(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.fixedDeltaTime = max(0.0001, value)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetMaxSubsteps")
public func MCEPhysicsGetMaxSubsteps(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    Int32(resolveEngineContext(contextPtr)?.physicsSettings.maxSubsteps ?? 4)
}

@_cdecl("MCEPhysicsSetMaxSubsteps")
public func MCEPhysicsSetMaxSubsteps(_ contextPtr: UnsafeRawPointer?, _ value: Int32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.maxSubsteps = max(1, min(Int(value), 4))
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDefaultFriction")
public func MCEPhysicsGetDefaultFriction(_ contextPtr: UnsafeRawPointer?) -> Float {
    resolveEngineContext(contextPtr)?.physicsSettings.defaultFriction ?? 0.6
}

@_cdecl("MCEPhysicsSetDefaultFriction")
public func MCEPhysicsSetDefaultFriction(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.defaultFriction = min(max(value, 0.0), 1.0)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDefaultRestitution")
public func MCEPhysicsGetDefaultRestitution(_ contextPtr: UnsafeRawPointer?) -> Float {
    resolveEngineContext(contextPtr)?.physicsSettings.defaultRestitution ?? 0.0
}

@_cdecl("MCEPhysicsSetDefaultRestitution")
public func MCEPhysicsSetDefaultRestitution(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.defaultRestitution = min(max(value, 0.0), 1.0)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDefaultAngularDamping")
public func MCEPhysicsGetDefaultAngularDamping(_ contextPtr: UnsafeRawPointer?) -> Float {
    resolveEngineContext(contextPtr)?.physicsSettings.defaultAngularDamping ?? 0.2
}

@_cdecl("MCEPhysicsSetDefaultAngularDamping")
public func MCEPhysicsSetDefaultAngularDamping(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.defaultAngularDamping = max(0.0, value)
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetCCDEnabled")
public func MCEPhysicsGetCCDEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.ccdEnabled == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetCCDEnabled")
public func MCEPhysicsSetCCDEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.ccdEnabled = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetResolveInitialOverlap")
public func MCEPhysicsGetResolveInitialOverlap(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.resolveInitialOverlap == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetResolveInitialOverlap")
public func MCEPhysicsSetResolveInitialOverlap(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.resolveInitialOverlap = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDeterministic")
public func MCEPhysicsGetDeterministic(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.deterministic == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetDeterministic")
public func MCEPhysicsSetDeterministic(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.deterministic = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDebugDrawEnabled")
public func MCEPhysicsGetDebugDrawEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.debugDrawEnabled == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetDebugDrawEnabled")
public func MCEPhysicsSetDebugDrawEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.debugDrawEnabled = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetDebugDrawInPlay")
public func MCEPhysicsGetDebugDrawInPlay(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.debugDrawInPlay == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetDebugDrawInPlay")
public func MCEPhysicsSetDebugDrawInPlay(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.debugDrawInPlay = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetShowColliders")
public func MCEPhysicsGetShowColliders(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.showColliders == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetShowColliders")
public func MCEPhysicsSetShowColliders(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.showColliders = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetShowCOMAxes")
public func MCEPhysicsGetShowCOMAxes(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.showCOMAxes == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetShowCOMAxes")
public func MCEPhysicsSetShowCOMAxes(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.showCOMAxes = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetShowContacts")
public func MCEPhysicsGetShowContacts(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.showContacts == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetShowContacts")
public func MCEPhysicsSetShowContacts(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.showContacts = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetShowSleeping")
public func MCEPhysicsGetShowSleeping(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.showSleeping == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetShowSleeping")
public func MCEPhysicsSetShowSleeping(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.showSleeping = value != 0
    context.physicsSettings = settings
}

@_cdecl("MCEPhysicsGetShowOverlaps")
public func MCEPhysicsGetShowOverlaps(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    resolveEngineContext(contextPtr)?.physicsSettings.showOverlaps == true ? 1 : 0
}

@_cdecl("MCEPhysicsSetShowOverlaps")
public func MCEPhysicsSetShowOverlaps(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    guard let context = resolveEngineContext(contextPtr) else { return }
    var settings = context.physicsSettings
    settings.showOverlaps = value != 0
    context.physicsSettings = settings
}
