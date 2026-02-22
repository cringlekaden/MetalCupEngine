/// RendererSettings.swift
/// Defines the RendererSettings types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

public enum TonemapType: UInt32 {
    case none = 0
    case reinhard = 1
    case aces = 2
    case metalCupCustom = 3
}

public enum IBLQualityPreset: UInt32 {
    case low = 0
    case medium = 1
    case high = 2
    case ultra = 3
    case custom = 4
}

public enum ShadowFilterMode: UInt32 {
    case hard = 0
    case pcf = 1
    case pcssExperimental = 2
}

public struct ShadowsSettings {
    public var enabled: UInt32 = 0
    public var directionalEnabled: UInt32 = 1
    public var shadowMapResolution: UInt32 = 2048
    public var cascadeCount: UInt32 = 3
    public var cascadeSplitLambda: Float = 0.65
    public var depthBias: Float = 0.0005
    public var normalBias: Float = 0.01
    public var pcfRadius: Float = 1.5
    public var filterMode: UInt32 = ShadowFilterMode.pcf.rawValue
    public var maxShadowDistance: Float = 100.0
    public var fadeOutDistance: Float = 10.0
    public var pcssLightWorldSize: Float = 1.0
    public var pcssMinFilterRadiusTexels: Float = 1.0
    public var pcssMaxFilterRadiusTexels: Float = 8.0
    public var pcssBlockerSearchRadiusTexels: Float = 4.0
    public var pcssBlockerSamples: UInt32 = 12
    public var pcssPCFSamples: UInt32 = 16
    public var pcssNoiseEnabled: UInt32 = 1
    public var pcssPadding: UInt32 = 0

    public init() {}
}

public typealias BloomUniforms = RendererSettings
public typealias RendererUniforms = RendererSettings

public struct RendererSettings: sizeable {
    public static let expectedMetalStride: Int = 304

    public init() {}

    public var bloomThreshold: Float = 1.2
    public var bloomKnee: Float = 0.2
    public var bloomIntensity: Float = 0.15
    public var bloomUpsampleScale: Float = 1.0
    public var bloomDirtIntensity: Float = 0.0
    public var bloomEnabled: UInt32 = 1

    public var bloomTexelSize: SIMD2<Float> = .zero
    public var bloomMipLevel: Float = 0
    public var bloomMaxMips: UInt32 = 5

    public var blurPasses: UInt32 = 6
    public var tonemap: UInt32 = TonemapType.metalCupCustom.rawValue
    public var exposure: Float = 1.0
    public var gamma: Float = 2.2

    public var iblEnabled: UInt32 = 1
    public var iblIntensity: Float = 1.0
    public var iblResolutionOverride: UInt32 = 0


    public var perfFlags: UInt32 = 0

    public var iblFireflyClamp: Float = 100.0
    public var iblFireflyClampEnabled: UInt32 = 1
    public var iblSampleMultiplier: Float = 1.0
    public var skyboxMipBias: Float = 0.0
    public var iblSpecularLodExponent: Float = 1.5
    public var iblSpecularLodBias: Float = 0.0
    public var iblSpecularGrazingLodBias: Float = 0.35
    public var iblSpecularMinRoughness: Float = 0.06
    public var specularAAStrength: Float = 1.0
    public var normalMapMipBias: Float = 0.0
    public var normalMapMipBiasGrazing: Float = 0.6
    public var shadingDebugMode: UInt32 = 0
    public var iblQualityPreset: UInt32 = IBLQualityPreset.high.rawValue

    public var outlineEnabled: UInt32 = 1
    public var outlineThickness: UInt32 = 1
    public var outlineOpacity: Float = 1.0
    public var outlinePadding: Float = 0.0
    public var outlineColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.9, 0.2)
    public var outlineColorPadding: Float = 0.0
    public var gridEnabled: UInt32 = 1
    public var gridOpacity: Float = 0.85
    public var gridFadeDistance: Float = 120.0
    public var gridMajorLineEvery: Float = 10.0
    public var uvDebug: SIMD2<UInt32> = .zero
    public var shadows: ShadowsSettings = ShadowsSettings()
    public var padding0: SIMD4<Float> = .zero
    public var padding1: SIMD4<Float> = .zero
}

public struct RendererPerfFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let halfResBloom = RendererPerfFlags(rawValue: 1 << 0)
    public static let useAsyncIBLGen = RendererPerfFlags(rawValue: 1 << 1)
    public static let disableSpecularAA = RendererPerfFlags(rawValue: 1 << 2)
    public static let disableClearcoat = RendererPerfFlags(rawValue: 1 << 3)
    public static let disableSheen = RendererPerfFlags(rawValue: 1 << 4)
    public static let skipSpecIBLHighRoughness = RendererPerfFlags(rawValue: 1 << 5)
}

public extension RendererSettings {
    var isBloomEnabled: Bool { bloomEnabled != 0 }
    var isIBLEnabled: Bool { iblEnabled != 0 }
    var isShadowsEnabled: Bool { shadows.enabled != 0 }
    var isDirectionalShadowsEnabled: Bool { shadows.directionalEnabled != 0 }

    mutating func setPerfFlag(_ flag: RendererPerfFlags, enabled: Bool) {
        if enabled {
            perfFlags |= flag.rawValue
        } else {
            perfFlags &= ~flag.rawValue
        }
    }

    func hasPerfFlag(_ flag: RendererPerfFlags) -> Bool {
        (perfFlags & flag.rawValue) != 0
    }
}


public final class RendererProfiler {
    public enum Scope: String, CaseIterable {
        case frame
        case update
        case scene
        case render
        case bloom
        case bloomExtract
        case bloomDownsample
        case bloomBlur
        case composite
        case overlays
        case present
        case gpu
    }

    private final class RollingAverage {
        private var values: [Double]
        private var index: Int = 0
        private var count: Int = 0

        init(capacity: Int) {
            values = Array(repeating: 0, count: capacity)
        }

        func add(_ value: Double) {
            values[index] = value
            index = (index + 1) % values.count
            count = min(count + 1, values.count)
        }

        var average: Double {
            guard count > 0 else { return 0 }
            let sum = values.prefix(count).reduce(0, +)
            return sum / Double(count)
        }
    }

    private let queue = DispatchQueue(label: "RendererProfiler.queue")
    private var averages: [Scope: RollingAverage] = [:]

    public init(sampleCount: Int = 120) {
        for scope in Scope.allCases {
            averages[scope] = RollingAverage(capacity: sampleCount)
        }
    }

    public func record(_ scope: Scope, seconds: Double) {
        queue.async {
            self.averages[scope]?.add(seconds * 1000.0)
        }
    }

    public func averageMs(_ scope: Scope) -> Float {
        var result: Double = 0
        queue.sync {
            result = self.averages[scope]?.average ?? 0
        }
        return Float(result)
    }
}
