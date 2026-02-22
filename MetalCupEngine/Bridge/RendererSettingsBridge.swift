/// RendererSettingsBridge.swift
/// Defines the RendererSettingsBridge types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

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

private func getSettings(_ contextPtr: UnsafeRawPointer?) -> RendererSettings {
    guard let engineContext = resolveEngineContext(contextPtr) else { return RendererSettings() }
    return engineContext.rendererSettings
}

private func updateSettings(_ contextPtr: UnsafeRawPointer?, _ body: (inout RendererSettings) -> Void) {
    guard let engineContext = resolveEngineContext(contextPtr) else { return }
    var settings = engineContext.rendererSettings
    body(&settings)
    engineContext.rendererSettings = settings
}

private func profiler(_ contextPtr: UnsafeRawPointer?) -> RendererProfiler? {
    return resolveEngineContext(contextPtr)?.renderer?.profiler
}

@_cdecl("MCERendererGetBloomEnabled")
public func MCERendererGetBloomEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).bloomEnabled
}

@_cdecl("MCERendererSetBloomEnabled")
public func MCERendererSetBloomEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.bloomEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetBloomThreshold")
public func MCERendererGetBloomThreshold(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).bloomThreshold
}

@_cdecl("MCERendererSetBloomThreshold")
public func MCERendererSetBloomThreshold(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.bloomThreshold = value
    }
}

@_cdecl("MCERendererGetBloomKnee")
public func MCERendererGetBloomKnee(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).bloomKnee
}

@_cdecl("MCERendererSetBloomKnee")
public func MCERendererSetBloomKnee(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.bloomKnee = value
    }
}

@_cdecl("MCERendererGetBloomIntensity")
public func MCERendererGetBloomIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).bloomIntensity
}

@_cdecl("MCERendererSetBloomIntensity")
public func MCERendererSetBloomIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.bloomIntensity = value
    }
}

@_cdecl("MCERendererGetBloomUpsampleScale")
public func MCERendererGetBloomUpsampleScale(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).bloomUpsampleScale
}

@_cdecl("MCERendererSetBloomUpsampleScale")
public func MCERendererSetBloomUpsampleScale(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.bloomUpsampleScale = value
    }
}

@_cdecl("MCERendererGetBloomDirtIntensity")
public func MCERendererGetBloomDirtIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).bloomDirtIntensity
}

@_cdecl("MCERendererSetBloomDirtIntensity")
public func MCERendererSetBloomDirtIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.bloomDirtIntensity = value
    }
}

@_cdecl("MCERendererGetBlurPasses")
public func MCERendererGetBlurPasses(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).blurPasses
}

@_cdecl("MCERendererSetBlurPasses")
public func MCERendererSetBlurPasses(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.blurPasses = value
    }
}

@_cdecl("MCERendererGetBloomMaxMips")
public func MCERendererGetBloomMaxMips(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).bloomMaxMips
}

@_cdecl("MCERendererSetBloomMaxMips")
public func MCERendererSetBloomMaxMips(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.bloomMaxMips = max(1, value)
    }
}

@_cdecl("MCERendererGetTonemap")
public func MCERendererGetTonemap(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).tonemap
}

@_cdecl("MCERendererSetTonemap")
public func MCERendererSetTonemap(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.tonemap = value
    }
}

@_cdecl("MCERendererGetExposure")
public func MCERendererGetExposure(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).exposure
}

@_cdecl("MCERendererSetExposure")
public func MCERendererSetExposure(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.exposure = value
    }
}

@_cdecl("MCERendererGetGamma")
public func MCERendererGetGamma(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).gamma
}

@_cdecl("MCERendererSetGamma")
public func MCERendererSetGamma(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.gamma = value
    }
}

@_cdecl("MCERendererGetIBLEnabled")
public func MCERendererGetIBLEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).iblEnabled
}

@_cdecl("MCERendererSetIBLEnabled")
public func MCERendererSetIBLEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.iblEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetIBLIntensity")
public func MCERendererGetIBLIntensity(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblIntensity
}

@_cdecl("MCERendererSetIBLIntensity")
public func MCERendererSetIBLIntensity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblIntensity = value
    }
}

@_cdecl("MCERendererGetIBLQualityPreset")
public func MCERendererGetIBLQualityPreset(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).iblQualityPreset
}

@_cdecl("MCERendererSetIBLQualityPreset")
public func MCERendererSetIBLQualityPreset(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.iblQualityPreset = value
    }
}

@_cdecl("MCERendererGetHalfResBloom")
public func MCERendererGetHalfResBloom(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (getSettings(contextPtr).perfFlags & RendererPerfFlags.halfResBloom.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetHalfResBloom")
public func MCERendererSetHalfResBloom(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.setPerfFlag(.halfResBloom, enabled: value != 0)
    }
}

@_cdecl("MCERendererGetDisableSpecularAA")
public func MCERendererGetDisableSpecularAA(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (getSettings(contextPtr).perfFlags & RendererPerfFlags.disableSpecularAA.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSpecularAA")
public func MCERendererSetDisableSpecularAA(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.setPerfFlag(.disableSpecularAA, enabled: value != 0)
    }
}

@_cdecl("MCERendererGetDisableClearcoat")
public func MCERendererGetDisableClearcoat(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (getSettings(contextPtr).perfFlags & RendererPerfFlags.disableClearcoat.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableClearcoat")
public func MCERendererSetDisableClearcoat(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.setPerfFlag(.disableClearcoat, enabled: value != 0)
    }
}

@_cdecl("MCERendererGetDisableSheen")
public func MCERendererGetDisableSheen(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (getSettings(contextPtr).perfFlags & RendererPerfFlags.disableSheen.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetDisableSheen")
public func MCERendererSetDisableSheen(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.setPerfFlag(.disableSheen, enabled: value != 0)
    }
}

@_cdecl("MCERendererGetSkipSpecIBLHighRoughness")
public func MCERendererGetSkipSpecIBLHighRoughness(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    (getSettings(contextPtr).perfFlags & RendererPerfFlags.skipSpecIBLHighRoughness.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetSkipSpecIBLHighRoughness")
public func MCERendererSetSkipSpecIBLHighRoughness(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.setPerfFlag(.skipSpecIBLHighRoughness, enabled: value != 0)
    }
}

@_cdecl("MCERendererGetShadingDebugMode")
public func MCERendererGetShadingDebugMode(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadingDebugMode
}

@_cdecl("MCERendererSetShadingDebugMode")
public func MCERendererSetShadingDebugMode(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadingDebugMode = value
    }
}

@_cdecl("MCERendererGetIBLSpecularLodExponent")
public func MCERendererGetIBLSpecularLodExponent(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblSpecularLodExponent
}

@_cdecl("MCERendererSetIBLSpecularLodExponent")
public func MCERendererSetIBLSpecularLodExponent(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblSpecularLodExponent = max(0.01, value)
    }
}

@_cdecl("MCERendererGetIBLSpecularLodBias")
public func MCERendererGetIBLSpecularLodBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblSpecularLodBias
}

@_cdecl("MCERendererSetIBLSpecularLodBias")
public func MCERendererSetIBLSpecularLodBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblSpecularLodBias = value
    }
}

@_cdecl("MCERendererGetIBLSpecularGrazingLodBias")
public func MCERendererGetIBLSpecularGrazingLodBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblSpecularGrazingLodBias
}

@_cdecl("MCERendererSetIBLSpecularGrazingLodBias")
public func MCERendererSetIBLSpecularGrazingLodBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblSpecularGrazingLodBias = value
    }
}

@_cdecl("MCERendererGetIBLSpecularMinRoughness")
public func MCERendererGetIBLSpecularMinRoughness(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblSpecularMinRoughness
}

@_cdecl("MCERendererSetIBLSpecularMinRoughness")
public func MCERendererSetIBLSpecularMinRoughness(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblSpecularMinRoughness = max(0.0, value)
    }
}

@_cdecl("MCERendererGetSpecularAAStrength")
public func MCERendererGetSpecularAAStrength(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).specularAAStrength
}

@_cdecl("MCERendererSetSpecularAAStrength")
public func MCERendererSetSpecularAAStrength(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.specularAAStrength = max(0.0, value)
    }
}

@_cdecl("MCERendererGetNormalMapMipBias")
public func MCERendererGetNormalMapMipBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).normalMapMipBias
}

@_cdecl("MCERendererSetNormalMapMipBias")
public func MCERendererSetNormalMapMipBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.normalMapMipBias = value
    }
}

@_cdecl("MCERendererGetNormalMapMipBiasGrazing")
public func MCERendererGetNormalMapMipBiasGrazing(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).normalMapMipBiasGrazing
}

@_cdecl("MCERendererSetNormalMapMipBiasGrazing")
public func MCERendererSetNormalMapMipBiasGrazing(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.normalMapMipBiasGrazing = max(0.0, value)
    }
}

@_cdecl("MCERendererGetOutlineEnabled")
public func MCERendererGetOutlineEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).outlineEnabled
}

@_cdecl("MCERendererSetOutlineEnabled")
public func MCERendererSetOutlineEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.outlineEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetOutlineThickness")
public func MCERendererGetOutlineThickness(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).outlineThickness
}

@_cdecl("MCERendererSetOutlineThickness")
public func MCERendererSetOutlineThickness(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.outlineThickness = max(1, min(4, value))
    }
}

@_cdecl("MCERendererGetOutlineOpacity")
public func MCERendererGetOutlineOpacity(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).outlineOpacity
}

@_cdecl("MCERendererSetOutlineOpacity")
public func MCERendererSetOutlineOpacity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.outlineOpacity = max(0.0, min(1.0, value))
    }
}

@_cdecl("MCERendererGetOutlineColor")
public func MCERendererGetOutlineColor(
    _ contextPtr: UnsafeRawPointer?,
    _ r: UnsafeMutablePointer<Float>?,
    _ g: UnsafeMutablePointer<Float>?,
    _ b: UnsafeMutablePointer<Float>?
) {
    let color = getSettings(contextPtr).outlineColor
    r?.pointee = color.x
    g?.pointee = color.y
    b?.pointee = color.z
}

@_cdecl("MCERendererSetOutlineColor")
public func MCERendererSetOutlineColor(_ contextPtr: UnsafeRawPointer?, _ r: Float, _ g: Float, _ b: Float) {
    updateSettings(contextPtr) { settings in
        settings.outlineColor = SIMD3<Float>(
            max(0.0, r),
            max(0.0, g),
            max(0.0, b)
        )
    }
}

@_cdecl("MCERendererGetGridEnabled")
public func MCERendererGetGridEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).gridEnabled
}

@_cdecl("MCERendererSetGridEnabled")
public func MCERendererSetGridEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.gridEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetGridOpacity")
public func MCERendererGetGridOpacity(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).gridOpacity
}

@_cdecl("MCERendererSetGridOpacity")
public func MCERendererSetGridOpacity(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.gridOpacity = max(0.0, min(1.0, value))
    }
}

@_cdecl("MCERendererGetGridFadeDistance")
public func MCERendererGetGridFadeDistance(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).gridFadeDistance
}

@_cdecl("MCERendererSetGridFadeDistance")
public func MCERendererSetGridFadeDistance(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.gridFadeDistance = max(0.0, value)
    }
}

@_cdecl("MCERendererGetGridMajorLineEvery")
public func MCERendererGetGridMajorLineEvery(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).gridMajorLineEvery
}

@_cdecl("MCERendererSetGridMajorLineEvery")
public func MCERendererSetGridMajorLineEvery(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.gridMajorLineEvery = max(1.0, value)
    }
}

@_cdecl("MCERendererGetIBLFireflyClampEnabled")
public func MCERendererGetIBLFireflyClampEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).iblFireflyClampEnabled
}

@_cdecl("MCERendererSetIBLFireflyClampEnabled")
public func MCERendererSetIBLFireflyClampEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.iblFireflyClampEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetIBLFireflyClamp")
public func MCERendererGetIBLFireflyClamp(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblFireflyClamp
}

@_cdecl("MCERendererSetIBLFireflyClamp")
public func MCERendererSetIBLFireflyClamp(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblFireflyClamp = max(0.0, value)
    }
}

@_cdecl("MCERendererGetIBLSampleMultiplier")
public func MCERendererGetIBLSampleMultiplier(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).iblSampleMultiplier
}

@_cdecl("MCERendererSetIBLSampleMultiplier")
public func MCERendererSetIBLSampleMultiplier(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.iblSampleMultiplier = max(0.1, value)
    }
}

@_cdecl("MCERendererGetSkyboxMipBias")
public func MCERendererGetSkyboxMipBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).skyboxMipBias
}

@_cdecl("MCERendererSetSkyboxMipBias")
public func MCERendererSetSkyboxMipBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.skyboxMipBias = value
    }
}

@_cdecl("MCERendererGetShadowsEnabled")
public func MCERendererGetShadowsEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.enabled
}

@_cdecl("MCERendererSetShadowsEnabled")
public func MCERendererSetShadowsEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.enabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetDirectionalShadowsEnabled")
public func MCERendererGetDirectionalShadowsEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.directionalEnabled
}

@_cdecl("MCERendererSetDirectionalShadowsEnabled")
public func MCERendererSetDirectionalShadowsEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.directionalEnabled = value != 0 ? 1 : 0
    }
}

@_cdecl("MCERendererGetShadowMapResolution")
public func MCERendererGetShadowMapResolution(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.shadowMapResolution
}

@_cdecl("MCERendererSetShadowMapResolution")
public func MCERendererSetShadowMapResolution(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        let options: [UInt32] = [1024, 2048, 4096]
        let chosen = options.min(by: { abs(Int($0) - Int(value)) < abs(Int($1) - Int(value)) }) ?? 2048
        settings.shadows.shadowMapResolution = chosen
    }
}

@_cdecl("MCERendererGetShadowCascadeCount")
public func MCERendererGetShadowCascadeCount(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.cascadeCount
}

@_cdecl("MCERendererSetShadowCascadeCount")
public func MCERendererSetShadowCascadeCount(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.cascadeCount = max(1, min(4, value))
    }
}

@_cdecl("MCERendererGetShadowSplitLambda")
public func MCERendererGetShadowSplitLambda(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.cascadeSplitLambda
}

@_cdecl("MCERendererSetShadowSplitLambda")
public func MCERendererSetShadowSplitLambda(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.cascadeSplitLambda = max(0.0, min(1.0, value))
    }
}

@_cdecl("MCERendererGetShadowDepthBias")
public func MCERendererGetShadowDepthBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.depthBias
}

@_cdecl("MCERendererSetShadowDepthBias")
public func MCERendererSetShadowDepthBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.depthBias = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowNormalBias")
public func MCERendererGetShadowNormalBias(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.normalBias
}

@_cdecl("MCERendererSetShadowNormalBias")
public func MCERendererSetShadowNormalBias(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.normalBias = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCFRadius")
public func MCERendererGetShadowPCFRadius(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.pcfRadius
}

@_cdecl("MCERendererSetShadowPCFRadius")
public func MCERendererSetShadowPCFRadius(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcfRadius = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowFilterMode")
public func MCERendererGetShadowFilterMode(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.filterMode
}

@_cdecl("MCERendererSetShadowFilterMode")
public func MCERendererSetShadowFilterMode(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.filterMode = min(value, 2)
    }
}

@_cdecl("MCERendererGetShadowMaxDistance")
public func MCERendererGetShadowMaxDistance(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.maxShadowDistance
}

@_cdecl("MCERendererSetShadowMaxDistance")
public func MCERendererSetShadowMaxDistance(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.maxShadowDistance = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowFadeOutDistance")
public func MCERendererGetShadowFadeOutDistance(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.fadeOutDistance
}

@_cdecl("MCERendererSetShadowFadeOutDistance")
public func MCERendererSetShadowFadeOutDistance(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.fadeOutDistance = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSLightWorldSize")
public func MCERendererGetShadowPCSSLightWorldSize(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.pcssLightWorldSize
}

@_cdecl("MCERendererSetShadowPCSSLightWorldSize")
public func MCERendererSetShadowPCSSLightWorldSize(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssLightWorldSize = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSMinRadius")
public func MCERendererGetShadowPCSSMinRadius(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.pcssMinFilterRadiusTexels
}

@_cdecl("MCERendererSetShadowPCSSMinRadius")
public func MCERendererSetShadowPCSSMinRadius(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssMinFilterRadiusTexels = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSMaxRadius")
public func MCERendererGetShadowPCSSMaxRadius(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.pcssMaxFilterRadiusTexels
}

@_cdecl("MCERendererSetShadowPCSSMaxRadius")
public func MCERendererSetShadowPCSSMaxRadius(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssMaxFilterRadiusTexels = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSBlockerRadius")
public func MCERendererGetShadowPCSSBlockerRadius(_ contextPtr: UnsafeRawPointer?) -> Float {
    getSettings(contextPtr).shadows.pcssBlockerSearchRadiusTexels
}

@_cdecl("MCERendererSetShadowPCSSBlockerRadius")
public func MCERendererSetShadowPCSSBlockerRadius(_ contextPtr: UnsafeRawPointer?, _ value: Float) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssBlockerSearchRadiusTexels = max(0.0, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSBlockerSamples")
public func MCERendererGetShadowPCSSBlockerSamples(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.pcssBlockerSamples
}

@_cdecl("MCERendererSetShadowPCSSBlockerSamples")
public func MCERendererSetShadowPCSSBlockerSamples(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssBlockerSamples = max(1, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSFilterSamples")
public func MCERendererGetShadowPCSSFilterSamples(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.pcssPCFSamples
}

@_cdecl("MCERendererSetShadowPCSSFilterSamples")
public func MCERendererSetShadowPCSSFilterSamples(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssPCFSamples = max(1, value)
    }
}

@_cdecl("MCERendererGetShadowPCSSNoiseEnabled")
public func MCERendererGetShadowPCSSNoiseEnabled(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    getSettings(contextPtr).shadows.pcssNoiseEnabled
}

@_cdecl("MCERendererSetShadowPCSSNoiseEnabled")
public func MCERendererSetShadowPCSSNoiseEnabled(_ contextPtr: UnsafeRawPointer?, _ value: UInt32) {
    updateSettings(contextPtr) { settings in
        settings.shadows.pcssNoiseEnabled = value != 0 ? 1 : 0
    }
}


@_cdecl("MCERendererGetFrameMs")
public func MCERendererGetFrameMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.frame) ?? 0
}

@_cdecl("MCERendererGetUpdateMs")
public func MCERendererGetUpdateMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.update) ?? 0
}

@_cdecl("MCERendererGetSceneMs")
public func MCERendererGetSceneMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.scene) ?? 0
}

@_cdecl("MCERendererGetRenderMs")
public func MCERendererGetRenderMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.render) ?? 0
}

@_cdecl("MCERendererGetBloomMs")
public func MCERendererGetBloomMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.bloom) ?? 0
}

@_cdecl("MCERendererGetBloomExtractMs")
public func MCERendererGetBloomExtractMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.bloomExtract) ?? 0
}

@_cdecl("MCERendererGetBloomDownsampleMs")
public func MCERendererGetBloomDownsampleMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.bloomDownsample) ?? 0
}

@_cdecl("MCERendererGetBloomBlurMs")
public func MCERendererGetBloomBlurMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.bloomBlur) ?? 0
}

@_cdecl("MCERendererGetCompositeMs")
public func MCERendererGetCompositeMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.composite) ?? 0
}

@_cdecl("MCERendererGetOverlaysMs")
public func MCERendererGetOverlaysMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.overlays) ?? 0
}

@_cdecl("MCERendererGetPresentMs")
public func MCERendererGetPresentMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.present) ?? 0
}

@_cdecl("MCERendererGetGpuMs")
public func MCERendererGetGpuMs(_ contextPtr: UnsafeRawPointer?) -> Float {
    profiler(contextPtr)?.averageMs(.gpu) ?? 0
}

// MCESky* APIs removed: SkyLight is edited via EditorECSBridge only.
