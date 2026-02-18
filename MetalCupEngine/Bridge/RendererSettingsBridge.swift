/// RendererSettingsBridge.swift
/// Defines the RendererSettingsBridge types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

private func activeScene() -> EngineScene? {
    return Renderer.activeRenderer?.delegate?.activeScene()
}

private func getSkyLight() -> (Entity, SkyLightComponent)? {
    return activeScene()?.ecs.activeSkyLight()
}

private func requestIBLRegenerate() {
    guard let scene = activeScene(),
          let (entity, sky) = getSkyLight() else { return }
    var updated = sky
    updated.needsRegenerate = true
    scene.ecs.add(updated, to: entity)
}

@_cdecl("MCERendererGetBloomEnabled")
public func MCERendererGetBloomEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.bloomEnabled
}

@_cdecl("MCERendererSetBloomEnabled")
public func MCERendererSetBloomEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.bloomEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetBloomThreshold")
public func MCERendererGetBloomThreshold(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.bloomThreshold
}

@_cdecl("MCERendererSetBloomThreshold")
public func MCERendererSetBloomThreshold(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.bloomThreshold = value
}

@_cdecl("MCERendererGetBloomKnee")
public func MCERendererGetBloomKnee(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.bloomKnee
}

@_cdecl("MCERendererSetBloomKnee")
public func MCERendererSetBloomKnee(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.bloomKnee = value
}

@_cdecl("MCERendererGetBloomIntensity")
public func MCERendererGetBloomIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.bloomIntensity
}

@_cdecl("MCERendererSetBloomIntensity")
public func MCERendererSetBloomIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.bloomIntensity = value
}

@_cdecl("MCERendererGetBloomUpsampleScale")
public func MCERendererGetBloomUpsampleScale(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.bloomUpsampleScale
}

@_cdecl("MCERendererSetBloomUpsampleScale")
public func MCERendererSetBloomUpsampleScale(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.bloomUpsampleScale = value
}

@_cdecl("MCERendererGetBloomDirtIntensity")
public func MCERendererGetBloomDirtIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.bloomDirtIntensity
}

@_cdecl("MCERendererSetBloomDirtIntensity")
public func MCERendererSetBloomDirtIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.bloomDirtIntensity = value
}

@_cdecl("MCERendererGetBlurPasses")
public func MCERendererGetBlurPasses(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.blurPasses
}

@_cdecl("MCERendererSetBlurPasses")
public func MCERendererSetBlurPasses(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.blurPasses = value
}

@_cdecl("MCERendererGetBloomMaxMips")
public func MCERendererGetBloomMaxMips(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.bloomMaxMips
}

@_cdecl("MCERendererSetBloomMaxMips")
public func MCERendererSetBloomMaxMips(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.bloomMaxMips = max(1, value)
}

@_cdecl("MCERendererGetTonemap")
public func MCERendererGetTonemap(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.tonemap
}

@_cdecl("MCERendererSetTonemap")
public func MCERendererSetTonemap(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.tonemap = value
}

@_cdecl("MCERendererGetExposure")
public func MCERendererGetExposure(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.exposure
}

@_cdecl("MCERendererSetExposure")
public func MCERendererSetExposure(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.exposure = value
}

@_cdecl("MCERendererGetGamma")
public func MCERendererGetGamma(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.gamma
}

@_cdecl("MCERendererSetGamma")
public func MCERendererSetGamma(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.gamma = value
}

@_cdecl("MCERendererGetIBLEnabled")
public func MCERendererGetIBLEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.iblEnabled
}

@_cdecl("MCERendererSetIBLEnabled")
public func MCERendererSetIBLEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.iblEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetIBLIntensity")
public func MCERendererGetIBLIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblIntensity
}

@_cdecl("MCERendererSetIBLIntensity")
public func MCERendererSetIBLIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblIntensity = value
}

@_cdecl("MCERendererGetIBLQualityPreset")
public func MCERendererGetIBLQualityPreset(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.iblQualityPreset
}

@_cdecl("MCERendererSetIBLQualityPreset")
public func MCERendererSetIBLQualityPreset(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.iblQualityPreset = value
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetHalfResBloom")
public func MCERendererGetHalfResBloom(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.halfResBloom.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetHalfResBloom")
public func MCERendererSetHalfResBloom(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.halfResBloom, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableSpecularAA")
public func MCERendererGetDisableSpecularAA(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableSpecularAA.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSpecularAA")
public func MCERendererSetDisableSpecularAA(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableSpecularAA, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableClearcoat")
public func MCERendererGetDisableClearcoat(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableClearcoat.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableClearcoat")
public func MCERendererSetDisableClearcoat(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableClearcoat, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetDisableSheen")
public func MCERendererGetDisableSheen(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.disableSheen.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSheen")
public func MCERendererSetDisableSheen(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.disableSheen, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetSkipSpecIBLHighRoughness")
public func MCERendererGetSkipSpecIBLHighRoughness(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (Renderer.settings.perfFlags & RendererPerfFlags.skipSpecIBLHighRoughness.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetSkipSpecIBLHighRoughness")
public func MCERendererSetSkipSpecIBLHighRoughness(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    var settings = Renderer.settings
    settings.setPerfFlag(.skipSpecIBLHighRoughness, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetNormalFlipYGlobal")
public func MCERendererGetNormalFlipYGlobal(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.normalFlipYGlobal
}

@_cdecl("MCERendererSetNormalFlipYGlobal")
public func MCERendererSetNormalFlipYGlobal(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.normalFlipYGlobal = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetShadingDebugMode")
public func MCERendererGetShadingDebugMode(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.shadingDebugMode
}

@_cdecl("MCERendererSetShadingDebugMode")
public func MCERendererSetShadingDebugMode(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.shadingDebugMode = value
}

@_cdecl("MCERendererGetIBLSpecularLodExponent")
public func MCERendererGetIBLSpecularLodExponent(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblSpecularLodExponent
}

@_cdecl("MCERendererSetIBLSpecularLodExponent")
public func MCERendererSetIBLSpecularLodExponent(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblSpecularLodExponent = max(0.01, value)
}

@_cdecl("MCERendererGetIBLSpecularLodBias")
public func MCERendererGetIBLSpecularLodBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblSpecularLodBias
}

@_cdecl("MCERendererSetIBLSpecularLodBias")
public func MCERendererSetIBLSpecularLodBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblSpecularLodBias = value
}

@_cdecl("MCERendererGetIBLSpecularGrazingLodBias")
public func MCERendererGetIBLSpecularGrazingLodBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblSpecularGrazingLodBias
}

@_cdecl("MCERendererSetIBLSpecularGrazingLodBias")
public func MCERendererSetIBLSpecularGrazingLodBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblSpecularGrazingLodBias = value
}

@_cdecl("MCERendererGetIBLSpecularMinRoughness")
public func MCERendererGetIBLSpecularMinRoughness(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblSpecularMinRoughness
}

@_cdecl("MCERendererSetIBLSpecularMinRoughness")
public func MCERendererSetIBLSpecularMinRoughness(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblSpecularMinRoughness = max(0.0, value)
}

@_cdecl("MCERendererGetSpecularAAStrength")
public func MCERendererGetSpecularAAStrength(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.specularAAStrength
}

@_cdecl("MCERendererSetSpecularAAStrength")
public func MCERendererSetSpecularAAStrength(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.specularAAStrength = max(0.0, value)
}

@_cdecl("MCERendererGetNormalMapMipBias")
public func MCERendererGetNormalMapMipBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.normalMapMipBias
}

@_cdecl("MCERendererSetNormalMapMipBias")
public func MCERendererSetNormalMapMipBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.normalMapMipBias = value
}

@_cdecl("MCERendererGetNormalMapMipBiasGrazing")
public func MCERendererGetNormalMapMipBiasGrazing(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.normalMapMipBiasGrazing
}

@_cdecl("MCERendererSetNormalMapMipBiasGrazing")
public func MCERendererSetNormalMapMipBiasGrazing(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.normalMapMipBiasGrazing = max(0.0, value)
}

@_cdecl("MCERendererGetOutlineEnabled")
public func MCERendererGetOutlineEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.outlineEnabled
}

@_cdecl("MCERendererSetOutlineEnabled")
public func MCERendererSetOutlineEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.outlineEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetOutlineThickness")
public func MCERendererGetOutlineThickness(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.outlineThickness
}

@_cdecl("MCERendererSetOutlineThickness")
public func MCERendererSetOutlineThickness(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.outlineThickness = max(1, min(4, value))
}

@_cdecl("MCERendererGetOutlineOpacity")
public func MCERendererGetOutlineOpacity(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.outlineOpacity
}

@_cdecl("MCERendererSetOutlineOpacity")
public func MCERendererSetOutlineOpacity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.outlineOpacity = max(0.0, min(1.0, value))
}

@_cdecl("MCERendererGetOutlineColor")
public func MCERendererGetOutlineColor(
    _ contextPtr: UnsafeRawPointer?,
    _ r: UnsafeMutablePointer<Float>?,
    _ g: UnsafeMutablePointer<Float>?,
    _ b: UnsafeMutablePointer<Float>?
) {
    let color = Renderer.settings.outlineColor
    r?.pointee = color.x
    g?.pointee = color.y
    b?.pointee = color.z
}

@_cdecl("MCERendererSetOutlineColor")
public func MCERendererSetOutlineColor(_ contextPtr: UnsafeRawPointer?, _ r: Float, _ g: Float, _ b: Float) {
    Renderer.settings.outlineColor = SIMD3<Float>(
        max(0.0, r),
        max(0.0, g),
        max(0.0, b)
    )
}

@_cdecl("MCERendererGetGridEnabled")
public func MCERendererGetGridEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.gridEnabled
}

@_cdecl("MCERendererSetGridEnabled")
public func MCERendererSetGridEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.gridEnabled = value != 0 ? 1 : 0
}

@_cdecl("MCERendererGetGridOpacity")
public func MCERendererGetGridOpacity(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.gridOpacity
}

@_cdecl("MCERendererSetGridOpacity")
public func MCERendererSetGridOpacity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.gridOpacity = max(0.0, min(1.0, value))
}

@_cdecl("MCERendererGetGridFadeDistance")
public func MCERendererGetGridFadeDistance(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.gridFadeDistance
}

@_cdecl("MCERendererSetGridFadeDistance")
public func MCERendererSetGridFadeDistance(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.gridFadeDistance = max(0.0, value)
}

@_cdecl("MCERendererGetGridMajorLineEvery")
public func MCERendererGetGridMajorLineEvery(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.gridMajorLineEvery
}

@_cdecl("MCERendererSetGridMajorLineEvery")
public func MCERendererSetGridMajorLineEvery(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.gridMajorLineEvery = max(1.0, value)
}

@_cdecl("MCERendererGetIBLFireflyClampEnabled")
public func MCERendererGetIBLFireflyClampEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    Renderer.settings.iblFireflyClampEnabled
}

@_cdecl("MCERendererSetIBLFireflyClampEnabled")
public func MCERendererSetIBLFireflyClampEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    Renderer.settings.iblFireflyClampEnabled = value != 0 ? 1 : 0
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetIBLFireflyClamp")
public func MCERendererGetIBLFireflyClamp(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblFireflyClamp
}

@_cdecl("MCERendererSetIBLFireflyClamp")
public func MCERendererSetIBLFireflyClamp(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblFireflyClamp = max(0.0, value)
    requestIBLRegenerate()
}

@_cdecl("MCERendererGetIBLSampleMultiplier")
public func MCERendererGetIBLSampleMultiplier(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.settings.iblSampleMultiplier
}

@_cdecl("MCERendererSetIBLSampleMultiplier")
public func MCERendererSetIBLSampleMultiplier(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    Renderer.settings.iblSampleMultiplier = max(0.1, value)
    requestIBLRegenerate()
}


@_cdecl("MCERendererGetFrameMs")
public func MCERendererGetFrameMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.frame)
}

@_cdecl("MCERendererGetUpdateMs")
public func MCERendererGetUpdateMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.update)
}

@_cdecl("MCERendererGetSceneMs")
public func MCERendererGetSceneMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.scene)
}

@_cdecl("MCERendererGetRenderMs")
public func MCERendererGetRenderMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.render)
}

@_cdecl("MCERendererGetBloomMs")
public func MCERendererGetBloomMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.bloom)
}

@_cdecl("MCERendererGetBloomExtractMs")
public func MCERendererGetBloomExtractMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.bloomExtract)
}

@_cdecl("MCERendererGetBloomDownsampleMs")
public func MCERendererGetBloomDownsampleMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.bloomDownsample)
}

@_cdecl("MCERendererGetBloomBlurMs")
public func MCERendererGetBloomBlurMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.bloomBlur)
}

@_cdecl("MCERendererGetCompositeMs")
public func MCERendererGetCompositeMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.composite)
}

@_cdecl("MCERendererGetOverlaysMs")
public func MCERendererGetOverlaysMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.overlays)
}

@_cdecl("MCERendererGetPresentMs")
public func MCERendererGetPresentMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.present)
}

@_cdecl("MCERendererGetGpuMs")
public func MCERendererGetGpuMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    Renderer.profiler.averageMs(.gpu)
}

// MCESky* APIs removed: SkyLight is edited via EditorECSBridge only.
