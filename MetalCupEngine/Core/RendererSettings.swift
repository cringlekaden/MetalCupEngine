/// RendererSettings.swift
/// Defines the RendererSettings types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import Metal

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
        case sceneUpdate
        case fixedUpdate
        case scene
        case render
        case renderBatches
        case bloom
        case bloomExtract
        case bloomDownsample
        case bloomBlur
        case composite
        case overlays
        case present
        case gpu
    }

    public enum GpuPass: String, CaseIterable {
        case shadows
        case depthPrepass
        case scene
        case grid
        case picking
        case outline
        case bloomExtract
        case bloomBlur
        case finalComposite
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
    private var gpuPassAverages: [GpuPass: RollingAverage] = [:]
    private var gpuPassProfilingEnabled: Bool = false
    private let gpuCounterLock = NSLock()
    private var gpuCounterSampleBuffer: MTLCounterSampleBuffer?
    private var gpuCounterResolveBuffer: MTLBuffer?
    private var gpuCounterSamplesPerFrame: Int = 0
    private var gpuCounterBytesPerSample: Int = 0
    private var gpuCounterBytesPerFrame: Int = 0
    private var gpuCounterInFlightFrames: Int = 0
    private var gpuCounterBeginMask: [UInt32] = []
    private var gpuCounterEndMask: [UInt32] = []
    private var gpuCounterFrameIds: [UInt64] = []
    private var gpuCounterSupported: Bool = false
    private var gpuCounterSupportReason: String = ""
    private var gpuCounterSetName: String = ""
    private var gpuCounterSamplingPointName: String = ""
    private var gpuCounterLoggedDiagnostics: Bool = false

    public init(sampleCount: Int = 120) {
        for scope in Scope.allCases {
            averages[scope] = RollingAverage(capacity: sampleCount)
        }
        for pass in GpuPass.allCases {
            gpuPassAverages[pass] = RollingAverage(capacity: sampleCount)
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

    public func recordGpuPass(_ pass: GpuPass, seconds: Double) {
        queue.async {
            self.gpuPassAverages[pass]?.add(seconds * 1000.0)
        }
    }

    public func averageGpuPassMs(_ pass: GpuPass) -> Float {
        var result: Double = 0
        queue.sync {
            result = self.gpuPassAverages[pass]?.average ?? 0
        }
        return Float(result)
    }

    public func setGpuPassTimingsEnabled(_ enabled: Bool) {
        queue.async {
            self.gpuPassProfilingEnabled = enabled
        }
    }

    public func gpuPassTimingsEnabled() -> Bool {
        var result = false
        queue.sync {
            result = gpuPassProfilingEnabled
        }
        return result
    }

    public func gpuCounterSamplingSupported(device: MTLDevice) -> Bool {
        guard #available(macOS 11.0, *) else { return false }
        updateGpuCounterSupport(device: device)
        return gpuCounterSupported
    }

    public func prepareGpuCounterSampling(device: MTLDevice, inFlightFrames: Int) -> Bool {
        guard gpuCounterSamplingSupported(device: device) else { return false }
        guard #available(macOS 11.0, *) else { return false }
        let passCount = GpuPass.allCases.count
        let samplesPerFrame = passCount * 2
        let totalSamples = samplesPerFrame * max(1, inFlightFrames)
        if gpuCounterSampleBuffer != nil,
           gpuCounterSamplesPerFrame == samplesPerFrame,
           gpuCounterInFlightFrames == inFlightFrames {
            return true
        }

        guard let counterSet = resolveTimestampCounterSet(device: device) else { return false }
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = counterSet
        descriptor.sampleCount = totalSamples
        descriptor.storageMode = .shared
        descriptor.label = "GpuPassCounters"
        let sampleBuffer: MTLCounterSampleBuffer
        do {
            sampleBuffer = try device.makeCounterSampleBuffer(descriptor: descriptor)
        } catch {
            return false
        }

        let bytesPerSample = counterBytesPerSample(counterSet: counterSet)
        let bytesPerFrame = bytesPerSample * samplesPerFrame
        let totalBytes = bytesPerFrame * max(1, inFlightFrames)
        guard let resolveBuffer = device.makeBuffer(length: totalBytes, options: .storageModeShared) else { return false }
        resolveBuffer.label = "GpuPassCounters.Resolve"

        gpuCounterLock.lock()
        gpuCounterSampleBuffer = sampleBuffer
        gpuCounterResolveBuffer = resolveBuffer
        gpuCounterSamplesPerFrame = samplesPerFrame
        gpuCounterBytesPerSample = bytesPerSample
        gpuCounterBytesPerFrame = bytesPerFrame
        gpuCounterInFlightFrames = inFlightFrames
        gpuCounterBeginMask = Array(repeating: 0, count: inFlightFrames)
        gpuCounterEndMask = Array(repeating: 0, count: inFlightFrames)
        gpuCounterFrameIds = Array(repeating: 0, count: inFlightFrames)
        gpuCounterLock.unlock()
        logGpuCounterDiagnosticsIfNeeded()
        return true
    }

    public func beginGpuCounterFrame(frameIndex: Int, frameId: UInt64) {
        gpuCounterLock.lock()
        guard gpuCounterSampleBuffer != nil,
              gpuCounterInFlightFrames > 0,
              frameIndex < gpuCounterInFlightFrames else {
            gpuCounterLock.unlock()
            return
        }
        gpuCounterBeginMask[frameIndex] = 0
        gpuCounterEndMask[frameIndex] = 0
        gpuCounterFrameIds[frameIndex] = frameId
        gpuCounterLock.unlock()
    }

    public func sampleGpuPassBegin(_ pass: GpuPass, encoder: MTLRenderCommandEncoder, frameIndex: Int) {
        guard #available(macOS 11.0, *) else { return }
        guard let sampleBuffer = gpuCounterSampleBuffer,
              gpuCounterInFlightFrames > 0,
              frameIndex < gpuCounterInFlightFrames else { return }
        let passIndex = gpuPassIndex(pass)
        let sampleIndex = frameIndex * gpuCounterSamplesPerFrame + (passIndex * 2)
        encoder.sampleCounters(sampleBuffer: sampleBuffer, sampleIndex: sampleIndex, barrier: true)
        gpuCounterLock.lock()
        gpuCounterBeginMask[frameIndex] |= UInt32(1 << passIndex)
        gpuCounterLock.unlock()
    }

    public func sampleGpuPassEnd(_ pass: GpuPass, encoder: MTLRenderCommandEncoder, frameIndex: Int) {
        guard #available(macOS 11.0, *) else { return }
        guard let sampleBuffer = gpuCounterSampleBuffer,
              gpuCounterInFlightFrames > 0,
              frameIndex < gpuCounterInFlightFrames else { return }
        let passIndex = gpuPassIndex(pass)
        let sampleIndex = frameIndex * gpuCounterSamplesPerFrame + (passIndex * 2) + 1
        encoder.sampleCounters(sampleBuffer: sampleBuffer, sampleIndex: sampleIndex, barrier: true)
        gpuCounterLock.lock()
        gpuCounterEndMask[frameIndex] |= UInt32(1 << passIndex)
        gpuCounterLock.unlock()
    }

    public func encodeGpuCounterResolve(commandBuffer: MTLCommandBuffer, frameIndex: Int) {
        guard #available(macOS 11.0, *) else { return }
        guard let sampleBuffer = gpuCounterSampleBuffer,
              let resolveBuffer = gpuCounterResolveBuffer,
              gpuCounterSamplesPerFrame > 0,
              gpuCounterInFlightFrames > 0,
              frameIndex < gpuCounterInFlightFrames else { return }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        let startSample = frameIndex * gpuCounterSamplesPerFrame
        let destinationOffset = frameIndex * gpuCounterBytesPerFrame
        let range = startSample..<(startSample + gpuCounterSamplesPerFrame)
        blit.resolveCounters(sampleBuffer, range: range, destinationBuffer: resolveBuffer, destinationOffset: destinationOffset)
        blit.endEncoding()
    }

    public func processResolvedGpuCounters(frameIndex: Int, frameId: UInt64, commandBuffer: MTLCommandBuffer) {
        guard let resolveBuffer = gpuCounterResolveBuffer,
              gpuCounterSamplesPerFrame > 0,
              gpuCounterBytesPerSample > 0,
              gpuCounterInFlightFrames > 0,
              frameIndex < gpuCounterInFlightFrames else { return }

        var beginMask: UInt32 = 0
        var endMask: UInt32 = 0
        gpuCounterLock.lock()
        if gpuCounterFrameIds[frameIndex] == frameId {
            beginMask = gpuCounterBeginMask[frameIndex]
            endMask = gpuCounterEndMask[frameIndex]
        }
        gpuCounterLock.unlock()

        let activeMask = beginMask & endMask
        if activeMask == 0 { return }

        let basePointer = resolveBuffer.contents().advanced(by: frameIndex * gpuCounterBytesPerFrame)
        var earliest: UInt64 = .max
        var latest: UInt64 = 0
        let passCount = GpuPass.allCases.count

        for passIndex in 0..<passCount {
            let mask = UInt32(1 << passIndex)
            if activeMask & mask == 0 { continue }
            let begin = readCounterSample(basePointer: basePointer, sampleIndex: passIndex * 2)
            let end = readCounterSample(basePointer: basePointer, sampleIndex: passIndex * 2 + 1)
            if end >= begin {
                earliest = min(earliest, begin)
                latest = max(latest, end)
            }
        }

        let gpuDuration = max(0.0, commandBuffer.gpuEndTime - commandBuffer.gpuStartTime)
        if gpuDuration > 0 {
            record(.gpu, seconds: gpuDuration)
        }
        guard earliest != .max, latest > earliest, gpuDuration > 0 else { return }

        let scale = gpuDuration / Double(latest - earliest)
        for passIndex in 0..<passCount {
            let mask = UInt32(1 << passIndex)
            if activeMask & mask == 0 { continue }
            let begin = readCounterSample(basePointer: basePointer, sampleIndex: passIndex * 2)
            let end = readCounterSample(basePointer: basePointer, sampleIndex: passIndex * 2 + 1)
            if end >= begin {
                let seconds = Double(end - begin) * scale
                recordGpuPass(GpuPass.allCases[passIndex], seconds: seconds)
            }
        }
    }

    @available(macOS 11.0, *)
    private func resolveTimestampCounterSet(device: MTLDevice) -> MTLCounterSet? {
        guard let counterSets = device.counterSets else { return nil }
        return counterSets.first(where: { $0.name.localizedCaseInsensitiveContains("timestamp") })
    }

    @available(macOS 11.0, *)
    private func counterBytesPerSample(counterSet: MTLCounterSet) -> Int {
        let counterCount = max(1, counterSet.counters.count)
        return counterCount * MemoryLayout<UInt64>.stride
    }

    private func readCounterSample(basePointer: UnsafeMutableRawPointer, sampleIndex: Int) -> UInt64 {
        let offset = sampleIndex * gpuCounterBytesPerSample
        return basePointer.advanced(by: offset).bindMemory(to: UInt64.self, capacity: 1).pointee
    }

    private func gpuPassIndex(_ pass: GpuPass) -> Int {
        return GpuPass.allCases.firstIndex(of: pass) ?? 0
    }

    public func gpuCounterSupportInfo() -> (supported: Bool, reason: String, counterSet: String, samplingPoint: String) {
        gpuCounterLock.lock()
        let info = (gpuCounterSupported, gpuCounterSupportReason, gpuCounterSetName, gpuCounterSamplingPointName)
        gpuCounterLock.unlock()
        return info
    }

    public func gpuCounterDebugInfo() -> String {
        let info = gpuCounterSupportInfo()
        if info.supported {
            return "GPU counters: supported (\(info.counterSet), \(info.samplingPoint))."
        }
        if info.reason.isEmpty {
            return "GPU counters: unsupported."
        }
        return "GPU counters: unsupported (\(info.reason))."
    }

    private func updateGpuCounterSupport(device: MTLDevice) {
        guard #available(macOS 11.0, *) else {
            setGpuCounterSupport(false, reason: "Requires macOS 11.0+.", counterSet: "", samplingPoint: "")
            return
        }
        guard let counterSets = device.counterSets else {
            setGpuCounterSupport(false, reason: "Device exposes no counter sets.", counterSet: "", samplingPoint: "")
            return
        }
        guard let timestampSet = counterSets.first(where: { $0.name.localizedCaseInsensitiveContains("timestamp") }) else {
            setGpuCounterSupport(false, reason: "No timestamp counter set available.", counterSet: "", samplingPoint: "")
            return
        }
        guard device.supportsCounterSampling(.atDrawBoundary) else {
            setGpuCounterSupport(false, reason: "Device does not support counter sampling at draw boundary.", counterSet: timestampSet.name, samplingPoint: "")
            return
        }
        setGpuCounterSupport(true, reason: "", counterSet: timestampSet.name, samplingPoint: "draw boundary")
    }

    private func setGpuCounterSupport(_ supported: Bool, reason: String, counterSet: String, samplingPoint: String) {
        gpuCounterLock.lock()
        gpuCounterSupported = supported
        gpuCounterSupportReason = reason
        gpuCounterSetName = counterSet
        gpuCounterSamplingPointName = samplingPoint
        gpuCounterLock.unlock()
    }

    private func logGpuCounterDiagnosticsIfNeeded() {
        #if DEBUG
        gpuCounterLock.lock()
        if gpuCounterLoggedDiagnostics {
            gpuCounterLock.unlock()
            return
        }
        gpuCounterLoggedDiagnostics = true
        let supported = gpuCounterSupported
        let reason = gpuCounterSupportReason
        let counterSet = gpuCounterSetName
        let samplingPoint = gpuCounterSamplingPointName
        gpuCounterLock.unlock()
        if supported {
            print("GPU pass timings: supported (\(counterSet), \(samplingPoint)).")
        } else {
            print("GPU pass timings: unsupported (\(reason)).")
        }
        #endif
    }
}
