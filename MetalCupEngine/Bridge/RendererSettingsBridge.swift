//
//  RendererSettingsBridge.swift
//  MetalCupEngine
//
//  Created by Codex on 2/6/26.
//

import Foundation

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

@_cdecl("MCERendererGetBlurPasses")
public func MCERendererGetBlurPasses() -> UInt32 {
    Renderer.settings.blurPasses
}

@_cdecl("MCERendererSetBlurPasses")
public func MCERendererSetBlurPasses(_ value: UInt32) {
    Renderer.settings.blurPasses = value
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

@_cdecl("MCERendererGetShowAlbedo")
public func MCERendererGetShowAlbedo() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showAlbedo.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowAlbedo")
public func MCERendererSetShowAlbedo(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showAlbedo, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetShowNormals")
public func MCERendererGetShowNormals() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showNormals.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowNormals")
public func MCERendererSetShowNormals(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showNormals, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetShowRoughness")
public func MCERendererGetShowRoughness() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showRoughness.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowRoughness")
public func MCERendererSetShowRoughness(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showRoughness, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetShowMetallic")
public func MCERendererGetShowMetallic() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showMetallic.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowMetallic")
public func MCERendererSetShowMetallic(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showMetallic, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetShowEmissive")
public func MCERendererGetShowEmissive() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showEmissive.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowEmissive")
public func MCERendererSetShowEmissive(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showEmissive, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetShowBloom")
public func MCERendererGetShowBloom() -> UInt32 {
    (Renderer.settings.debugFlags & RendererDebugFlags.showBloom.rawValue) != 0 ? 1 : 0
}

@_cdecl("MCERendererSetShowBloom")
public func MCERendererSetShowBloom(_ value: UInt32) {
    var settings = Renderer.settings
    settings.setDebugFlag(.showBloom, enabled: value != 0)
    Renderer.settings = settings
}

@_cdecl("MCERendererGetFrameMs")
public func MCERendererGetFrameMs() -> Float {
    Renderer.profiler.averageMs(.frame)
}

@_cdecl("MCERendererGetUpdateMs")
public func MCERendererGetUpdateMs() -> Float {
    Renderer.profiler.averageMs(.update)
}

@_cdecl("MCERendererGetRenderMs")
public func MCERendererGetRenderMs() -> Float {
    Renderer.profiler.averageMs(.render)
}

@_cdecl("MCERendererGetBloomMs")
public func MCERendererGetBloomMs() -> Float {
    Renderer.profiler.averageMs(.bloom)
}

@_cdecl("MCERendererGetPresentMs")
public func MCERendererGetPresentMs() -> Float {
    Renderer.profiler.averageMs(.present)
}

@_cdecl("MCERendererGetGpuMs")
public func MCERendererGetGpuMs() -> Float {
    Renderer.profiler.averageMs(.gpu)
}
