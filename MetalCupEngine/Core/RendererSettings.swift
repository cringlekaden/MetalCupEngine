//
//  RendererSettings.swift
//  MetalCup
//
//  Created by Kaden Cringle on 2/6/26.
//

import Foundation

public enum TonemapType: UInt32 {
    case none = 0
    case reinhard = 1
    case aces = 2
    case hazel = 3
}

public struct RendererSettings: sizeable {
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
    public var tonemap: UInt32 = TonemapType.hazel.rawValue
    public var exposure: Float = 1.0
    public var gamma: Float = 2.2

    public var iblEnabled: UInt32 = 1
    public var iblIntensity: Float = 1.0
    public var iblResolutionOverride: UInt32 = 0


    public var perfFlags: UInt32 = 0
    public var normalFlipYGlobal: UInt32 = 1

    public var padding: SIMD2<Float> = .zero
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

@objcMembers public final class RendererSettingsProxy: NSObject {
    public static let shared = RendererSettingsProxy()

    public var bloomEnabled: Bool {
        get { Renderer.settings.bloomEnabled != 0 }
        set { Renderer.settings.bloomEnabled = newValue ? 1 : 0 }
    }

    public var bloomThreshold: Float {
        get { Renderer.settings.bloomThreshold }
        set { Renderer.settings.bloomThreshold = newValue }
    }

    public var bloomKnee: Float {
        get { Renderer.settings.bloomKnee }
        set { Renderer.settings.bloomKnee = newValue }
    }

    public var bloomIntensity: Float {
        get { Renderer.settings.bloomIntensity }
        set { Renderer.settings.bloomIntensity = newValue }
    }

    public var bloomUpsampleScale: Float {
        get { Renderer.settings.bloomUpsampleScale }
        set { Renderer.settings.bloomUpsampleScale = newValue }
    }

    public var bloomDirtIntensity: Float {
        get { Renderer.settings.bloomDirtIntensity }
        set { Renderer.settings.bloomDirtIntensity = newValue }
    }

    public var blurPasses: Int {
        get { Int(Renderer.settings.blurPasses) }
        set { Renderer.settings.blurPasses = UInt32(max(0, newValue)) }
    }

    public var bloomMaxMips: Int {
        get { Int(Renderer.settings.bloomMaxMips) }
        set { Renderer.settings.bloomMaxMips = UInt32(max(1, newValue)) }
    }

    public var tonemap: Int {
        get { Int(Renderer.settings.tonemap) }
        set { Renderer.settings.tonemap = UInt32(newValue) }
    }

    public var exposure: Float {
        get { Renderer.settings.exposure }
        set { Renderer.settings.exposure = newValue }
    }

    public var gamma: Float {
        get { Renderer.settings.gamma }
        set { Renderer.settings.gamma = newValue }
    }

    public var iblEnabled: Bool {
        get { Renderer.settings.iblEnabled != 0 }
        set { Renderer.settings.iblEnabled = newValue ? 1 : 0 }
    }

    public var iblIntensity: Float {
        get { Renderer.settings.iblIntensity }
        set { Renderer.settings.iblIntensity = newValue }
    }

    public var halfResBloom: Bool {
        get { (Renderer.settings.perfFlags & RendererPerfFlags.halfResBloom.rawValue) != 0 }
        set {
            var settings = Renderer.settings
            settings.setPerfFlag(.halfResBloom, enabled: newValue)
            Renderer.settings = settings
        }
    }

    public var disableSpecularAA: Bool {
        get { (Renderer.settings.perfFlags & RendererPerfFlags.disableSpecularAA.rawValue) != 0 }
        set {
            var settings = Renderer.settings
            settings.setPerfFlag(.disableSpecularAA, enabled: newValue)
            Renderer.settings = settings
        }
    }

    public var disableClearcoat: Bool {
        get { (Renderer.settings.perfFlags & RendererPerfFlags.disableClearcoat.rawValue) != 0 }
        set {
            var settings = Renderer.settings
            settings.setPerfFlag(.disableClearcoat, enabled: newValue)
            Renderer.settings = settings
        }
    }

    public var disableSheen: Bool {
        get { (Renderer.settings.perfFlags & RendererPerfFlags.disableSheen.rawValue) != 0 }
        set {
            var settings = Renderer.settings
            settings.setPerfFlag(.disableSheen, enabled: newValue)
            Renderer.settings = settings
        }
    }

    public var skipSpecIBLHighRoughness: Bool {
        get { (Renderer.settings.perfFlags & RendererPerfFlags.skipSpecIBLHighRoughness.rawValue) != 0 }
        set {
            var settings = Renderer.settings
            settings.setPerfFlag(.skipSpecIBLHighRoughness, enabled: newValue)
            Renderer.settings = settings
        }
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

@objcMembers public final class RendererStatsProxy: NSObject {
    public static let shared = RendererStatsProxy()

    public var frameMs: Float { Renderer.profiler.averageMs(.frame) }
    public var updateMs: Float { Renderer.profiler.averageMs(.update) }
    public var sceneMs: Float { Renderer.profiler.averageMs(.scene) }
    public var renderMs: Float { Renderer.profiler.averageMs(.render) }
    public var bloomMs: Float { Renderer.profiler.averageMs(.bloom) }
    public var bloomExtractMs: Float { Renderer.profiler.averageMs(.bloomExtract) }
    public var bloomDownsampleMs: Float { Renderer.profiler.averageMs(.bloomDownsample) }
    public var bloomBlurMs: Float { Renderer.profiler.averageMs(.bloomBlur) }
    public var compositeMs: Float { Renderer.profiler.averageMs(.composite) }
    public var overlaysMs: Float { Renderer.profiler.averageMs(.overlays) }
    public var presentMs: Float { Renderer.profiler.averageMs(.present) }
    public var gpuMs: Float { Renderer.profiler.averageMs(.gpu) }
}
