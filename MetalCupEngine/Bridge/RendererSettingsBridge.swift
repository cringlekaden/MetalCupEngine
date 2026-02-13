/// RendererSettingsBridge.swift
/// Defines the RendererSettingsBridge types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

private func editorScene() -> EngineScene {
    return SceneManager.getEditorScene() ?? SceneManager.currentScene
}

private func ensureSkyLight() -> (Entity, SkyLightComponent) {
    let ecs = editorScene().ecs
    if let active = ecs.activeSkyLight() {
        return active
    }
    let entity = ecs.createEntity(name: "Sky Light")
    var sky = SkyLightComponent()
    sky.needsRegenerate = true
    ecs.add(sky, to: entity)
    ecs.add(SkyLightTag(), to: entity)
    return (entity, sky)
}

private func getSkyLight() -> (Entity, SkyLightComponent)? {
    return editorScene().ecs.activeSkyLight()
}

private func requestIBLRegenerate() {
    guard let (entity, sky) = getSkyLight() else { return }
    var updated = sky
    updated.needsRegenerate = true
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCERendererGetBloomEnabled")
public func MCERendererGetBloomEnabled() -> UInt32 {
    Renderer.settings.bloomEnabled
}

@_cdecl("MCERendererSetBloomEnabled")
public func MCERendererSetBloomEnabled(_ value: UInt32) {
    Renderer.settings.bloomEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetBloomThreshold")
public func MCERendererGetBloomThreshold() -> Float {
    Renderer.settings.bloomThreshold
}

@_cdecl("MCERendererSetBloomThreshold")
public func MCERendererSetBloomThreshold(_ value: Float) {
    Renderer.settings.bloomThreshold = value
}

@_cdecl("MCERendererGetBloomKnee")
public func MCERendererGetBloomKnee() -> Float {
    Renderer.settings.bloomKnee
}

@_cdecl("MCERendererSetBloomKnee")
public func MCERendererSetBloomKnee(_ value: Float) {
    Renderer.settings.bloomKnee = value
}

@_cdecl("MCERendererGetBloomIntensity")
public func MCERendererGetBloomIntensity() -> Float {
    Renderer.settings.bloomIntensity
}

@_cdecl("MCERendererSetBloomIntensity")
public func MCERendererSetBloomIntensity(_ value: Float) {
    Renderer.settings.bloomIntensity = value
}

@_cdecl("MCERendererGetBloomUpsampleScale")
public func MCERendererGetBloomUpsampleScale() -> Float {
    Renderer.settings.bloomUpsampleScale
}

@_cdecl("MCERendererSetBloomUpsampleScale")
public func MCERendererSetBloomUpsampleScale(_ value: Float) {
    Renderer.settings.bloomUpsampleScale = value
}

@_cdecl("MCERendererGetBloomDirtIntensity")
public func MCERendererGetBloomDirtIntensity() -> Float {
    Renderer.settings.bloomDirtIntensity
}

@_cdecl("MCERendererSetBloomDirtIntensity")
public func MCERendererSetBloomDirtIntensity(_ value: Float) {
    Renderer.settings.bloomDirtIntensity = value
}

@_cdecl("MCERendererGetBlurPasses")
public func MCERendererGetBlurPasses() -> UInt32 {
    Renderer.settings.blurPasses
}

@_cdecl("MCERendererSetBlurPasses")
public func MCERendererSetBlurPasses(_ value: UInt32) {
    Renderer.settings.blurPasses = value
}

@_cdecl("MCERendererGetBloomMaxMips")
public func MCERendererGetBloomMaxMips() -> UInt32 {
    Renderer.settings.bloomMaxMips
}

@_cdecl("MCERendererSetBloomMaxMips")
public func MCERendererSetBloomMaxMips(_ value: UInt32) {
    Renderer.settings.bloomMaxMips = max(1, value)
}

@_cdecl("MCERendererGetTonemap")
public func MCERendererGetTonemap() -> UInt32 {
    Renderer.settings.tonemap
}

@_cdecl("MCERendererSetTonemap")
public func MCERendererSetTonemap(_ value: UInt32) {
    Renderer.settings.tonemap = value
}

@_cdecl("MCERendererGetExposure")
public func MCERendererGetExposure() -> Float {
    Renderer.settings.exposure
}

@_cdecl("MCERendererSetExposure")
public func MCERendererSetExposure(_ value: Float) {
    Renderer.settings.exposure = value
}

@_cdecl("MCERendererGetGamma")
public func MCERendererGetGamma() -> Float {
    Renderer.settings.gamma
}

@_cdecl("MCERendererSetGamma")
public func MCERendererSetGamma(_ value: Float) {
    Renderer.settings.gamma = value
}

@_cdecl("MCERendererGetIBLEnabled")
public func MCERendererGetIBLEnabled() -> UInt32 {
    Renderer.settings.iblEnabled
}

@_cdecl("MCERendererSetIBLEnabled")
public func MCERendererSetIBLEnabled(_ value: UInt32) {
    Renderer.settings.iblEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetIBLIntensity")
public func MCERendererGetIBLIntensity() -> Float {
    Renderer.settings.iblIntensity
}

@_cdecl("MCERendererSetIBLIntensity")
public func MCERendererSetIBLIntensity(_ value: Float) {
    Renderer.settings.iblIntensity = value
}

@_cdecl("MCERendererGetIBLQualityPreset")
public func MCERendererGetIBLQualityPreset() -> UInt32 {
    Renderer.settings.iblQualityPreset
}

@_cdecl("MCERendererSetIBLQualityPreset")
public func MCERendererSetIBLQualityPreset(_ value: UInt32) {
    Renderer.settings.iblQualityPreset = value
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetHalfResBloom")
public func MCERendererGetHalfResBloom() -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.halfResBloom.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetHalfResBloom")
public func MCERendererSetHalfResBloom(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.halfResBloom, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableSpecularAA")
public func MCERendererGetDisableSpecularAA() -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableSpecularAA.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSpecularAA")
public func MCERendererSetDisableSpecularAA(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableSpecularAA, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableClearcoat")
public func MCERendererGetDisableClearcoat() -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableClearcoat.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableClearcoat")
public func MCERendererSetDisableClearcoat(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableClearcoat, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableSheen")
public func MCERendererGetDisableSheen() -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableSheen.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSheen")
public func MCERendererSetDisableSheen(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableSheen, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetSkipSpecIBLHighRoughness")
public func MCERendererGetSkipSpecIBLHighRoughness() -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.skipSpecIBLHighRoughness.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetSkipSpecIBLHighRoughness")
public func MCERendererSetSkipSpecIBLHighRoughness(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.skipSpecIBLHighRoughness, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetNormalFlipYGlobal")
public func MCERendererGetNormalFlipYGlobal() -> UInt32 {
    Renderer.settings.normalFlipYGlobal
}

@_cdecl("MCERendererSetNormalFlipYGlobal")
public func MCERendererSetNormalFlipYGlobal(_ value: UInt32) {
    Renderer.settings.normalFlipYGlobal = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetShadingDebugMode")
public func MCERendererGetShadingDebugMode() -> UInt32 {
    Renderer.settings.shadingDebugMode
}

@_cdecl("MCERendererSetShadingDebugMode")
public func MCERendererSetShadingDebugMode(_ value: UInt32) {
    Renderer.settings.shadingDebugMode = value
}

@_cdecl("MCERendererGetIBLSpecularLodExponent")
public func MCERendererGetIBLSpecularLodExponent() -> Float {
    Renderer.settings.iblSpecularLodExponent
}

@_cdecl("MCERendererSetIBLSpecularLodExponent")
public func MCERendererSetIBLSpecularLodExponent(_ value: Float) {
    Renderer.settings.iblSpecularLodExponent = max(0.01, value)
}

@_cdecl("MCERendererGetIBLSpecularLodBias")
public func MCERendererGetIBLSpecularLodBias() -> Float {
    Renderer.settings.iblSpecularLodBias
}

@_cdecl("MCERendererSetIBLSpecularLodBias")
public func MCERendererSetIBLSpecularLodBias(_ value: Float) {
    Renderer.settings.iblSpecularLodBias = value
}

@_cdecl("MCERendererGetIBLSpecularGrazingLodBias")
public func MCERendererGetIBLSpecularGrazingLodBias() -> Float {
    Renderer.settings.iblSpecularGrazingLodBias
}

@_cdecl("MCERendererSetIBLSpecularGrazingLodBias")
public func MCERendererSetIBLSpecularGrazingLodBias(_ value: Float) {
    Renderer.settings.iblSpecularGrazingLodBias = value
}

@_cdecl("MCERendererGetIBLSpecularMinRoughness")
public func MCERendererGetIBLSpecularMinRoughness() -> Float {
    Renderer.settings.iblSpecularMinRoughness
}

@_cdecl("MCERendererSetIBLSpecularMinRoughness")
public func MCERendererSetIBLSpecularMinRoughness(_ value: Float) {
    Renderer.settings.iblSpecularMinRoughness = max(0.0, value)
}

@_cdecl("MCERendererGetSpecularAAStrength")
public func MCERendererGetSpecularAAStrength() -> Float {
    Renderer.settings.specularAAStrength
}

@_cdecl("MCERendererSetSpecularAAStrength")
public func MCERendererSetSpecularAAStrength(_ value: Float) {
    Renderer.settings.specularAAStrength = max(0.0, value)
}

@_cdecl("MCERendererGetNormalMapMipBias")
public func MCERendererGetNormalMapMipBias() -> Float {
    Renderer.settings.normalMapMipBias
}

@_cdecl("MCERendererSetNormalMapMipBias")
public func MCERendererSetNormalMapMipBias(_ value: Float) {
    Renderer.settings.normalMapMipBias = value
}

@_cdecl("MCERendererGetNormalMapMipBiasGrazing")
public func MCERendererGetNormalMapMipBiasGrazing() -> Float {
    Renderer.settings.normalMapMipBiasGrazing
}

@_cdecl("MCERendererSetNormalMapMipBiasGrazing")
public func MCERendererSetNormalMapMipBiasGrazing(_ value: Float) {
    Renderer.settings.normalMapMipBiasGrazing = max(0.0, value)
}

@_cdecl("MCERendererGetIBLFireflyClampEnabled")
public func MCERendererGetIBLFireflyClampEnabled() -> UInt32 {
    Renderer.settings.iblFireflyClampEnabled
}

@_cdecl("MCERendererSetIBLFireflyClampEnabled")
public func MCERendererSetIBLFireflyClampEnabled(_ value: UInt32) {
    Renderer.settings.iblFireflyClampEnabled = value != 0 ? 1 : 0
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetIBLFireflyClamp")
public func MCERendererGetIBLFireflyClamp() -> Float {
    Renderer.settings.iblFireflyClamp
}

@_cdecl("MCERendererSetIBLFireflyClamp")
public func MCERendererSetIBLFireflyClamp(_ value: Float) {
    Renderer.settings.iblFireflyClamp = max(0.0, value)
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetIBLSampleMultiplier")
public func MCERendererGetIBLSampleMultiplier() -> Float {
    Renderer.settings.iblSampleMultiplier
}

@_cdecl("MCERendererSetIBLSampleMultiplier")
public func MCERendererSetIBLSampleMultiplier(_ value: Float) {
    Renderer.settings.iblSampleMultiplier = max(0.1, value)
    requestIBLRegenerate()
}


@_cdecl("MCERendererGetFrameMs")
public func MCERendererGetFrameMs() -> Float {
    Renderer.profiler.averageMs(.frame)
}

@_cdecl("MCERendererGetUpdateMs")
public func MCERendererGetUpdateMs() -> Float {
    Renderer.profiler.averageMs(.update)
}

@_cdecl("MCERendererGetSceneMs")
public func MCERendererGetSceneMs() -> Float {
    Renderer.profiler.averageMs(.scene)
}

@_cdecl("MCERendererGetRenderMs")
public func MCERendererGetRenderMs() -> Float {
    Renderer.profiler.averageMs(.render)
}

@_cdecl("MCERendererGetBloomMs")
public func MCERendererGetBloomMs() -> Float {
    Renderer.profiler.averageMs(.bloom)
}

@_cdecl("MCERendererGetBloomExtractMs")
public func MCERendererGetBloomExtractMs() -> Float {
    Renderer.profiler.averageMs(.bloomExtract)
}

@_cdecl("MCERendererGetBloomDownsampleMs")
public func MCERendererGetBloomDownsampleMs() -> Float {
    Renderer.profiler.averageMs(.bloomDownsample)
}

@_cdecl("MCERendererGetBloomBlurMs")
public func MCERendererGetBloomBlurMs() -> Float {
    Renderer.profiler.averageMs(.bloomBlur)
}

@_cdecl("MCERendererGetCompositeMs")
public func MCERendererGetCompositeMs() -> Float {
    Renderer.profiler.averageMs(.composite)
}

@_cdecl("MCERendererGetOverlaysMs")
public func MCERendererGetOverlaysMs() -> Float {
    Renderer.profiler.averageMs(.overlays)
}

@_cdecl("MCERendererGetPresentMs")
public func MCERendererGetPresentMs() -> Float {
    Renderer.profiler.averageMs(.present)
}

@_cdecl("MCERendererGetGpuMs")
public func MCERendererGetGpuMs() -> Float {
    Renderer.profiler.averageMs(.gpu)
}

@_cdecl("MCESkyHasSkyLight")
public func MCESkyHasSkyLight() -> UInt32 {
    return getSkyLight() == nil ? 0 : 1
}

@_cdecl("MCESkyGetEnabled")
public func MCESkyGetEnabled() -> UInt32 {
    return ensureSkyLight().1.enabled == true ? 1 : 0
}

@_cdecl("MCESkySetEnabled")
public func MCESkySetEnabled(_ value: UInt32) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.enabled = value != 0
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetMode")
public func MCESkyGetMode() -> UInt32 {
    return ensureSkyLight().1.mode.rawValue
}

@_cdecl("MCESkySetMode")
public func MCESkySetMode(_ value: UInt32) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.mode = SkyMode(rawValue: value) ?? .hdri
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetIntensity")
public func MCESkyGetIntensity() -> Float {
    return ensureSkyLight().1.intensity
}

@_cdecl("MCESkySetIntensity")
public func MCESkySetIntensity(_ value: Float) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.intensity = max(value, 0.0)
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetTint")
public func MCESkyGetTint(_ r: UnsafeMutablePointer<Float>?,
                          _ g: UnsafeMutablePointer<Float>?,
                          _ b: UnsafeMutablePointer<Float>?) {
    let tint = ensureSkyLight().1.skyTint
    r?.pointee = tint.x
    g?.pointee = tint.y
    b?.pointee = tint.z
}

@_cdecl("MCESkySetTint")
public func MCESkySetTint(_ r: Float, _ g: Float, _ b: Float) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.skyTint = SIMD3<Float>(max(r, 0.0), max(g, 0.0), max(b, 0.0))
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetTurbidity")
public func MCESkyGetTurbidity() -> Float {
    return ensureSkyLight().1.turbidity
}

@_cdecl("MCESkySetTurbidity")
public func MCESkySetTurbidity(_ value: Float) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.turbidity = max(1.0, value)
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetAzimuthDegrees")
public func MCESkyGetAzimuthDegrees() -> Float {
    return ensureSkyLight().1.azimuthDegrees
}

@_cdecl("MCESkySetAzimuthDegrees")
public func MCESkySetAzimuthDegrees(_ value: Float) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.azimuthDegrees = value
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetElevationDegrees")
public func MCESkyGetElevationDegrees() -> Float {
    return ensureSkyLight().1.elevationDegrees
}

@_cdecl("MCESkySetElevationDegrees")
public func MCESkySetElevationDegrees(_ value: Float) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.elevationDegrees = value
    updated.needsRegenerate = sky.realtimeUpdate
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyGetRealtimeUpdate")
public func MCESkyGetRealtimeUpdate() -> UInt32 {
    return ensureSkyLight().1.realtimeUpdate == true ? 1 : 0
}

@_cdecl("MCESkySetRealtimeUpdate")
public func MCESkySetRealtimeUpdate(_ value: UInt32) {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.realtimeUpdate = value != 0
    if updated.realtimeUpdate {
        updated.needsRegenerate = true
    }
    editorScene().ecs.add(updated, to: entity)
}

@_cdecl("MCESkyRegenerate")
public func MCESkyRegenerate() {
    let (entity, sky) = ensureSkyLight()
    var updated = sky
    updated.needsRegenerate = true
    editorScene().ecs.add(updated, to: entity)
}
