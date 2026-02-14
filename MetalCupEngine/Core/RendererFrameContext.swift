/// RendererFrameContext.swift
/// Defines per-frame renderer resources for batching and picking.
/// Created by Kaden Cringle.

import MetalKit

public struct RendererBatchStats {
    public var uniqueMeshes: Int = 0
    public var batches: Int = 0
    public var instancedDrawCalls: Int = 0
    public var nonInstancedDrawCalls: Int = 0
}

public final class RendererFrameContext {
    public static let shared = RendererFrameContext()

    private let maxFramesInFlight = 3
    private var frameIndex = 0

    private var instanceBuffers: [MTLBuffer?] = []
    private var instanceBufferCapacities: [Int] = []
    private var pickReadbackBuffers: [MTLBuffer?] = []

    private(set) var batchStats = RendererBatchStats()

    private init() {}

    public func beginFrame() {
        frameIndex = (frameIndex + 1) % maxFramesInFlight
        ensureFrameStorage()
        batchStats = RendererBatchStats()
    }

    public func currentFrameIndex() -> Int {
        return frameIndex
    }

    public func updateBatchStats(_ stats: RendererBatchStats) {
        batchStats = stats
    }

    public func uploadInstanceData(_ data: [InstanceData]) -> MTLBuffer? {
        guard !data.isEmpty else { return nil }
        let requiredBytes = InstanceData.stride(data.count)
        ensureInstanceBufferCapacity(requiredBytes)
        guard let buffer = instanceBuffers[frameIndex] else { return nil }
        data.withUnsafeBytes { bytes in
            memcpy(buffer.contents(), bytes.baseAddress, bytes.count)
        }
        return buffer
    }

    public func instanceBuffer() -> MTLBuffer? {
        return instanceBuffers[frameIndex] ?? nil
    }

    public func pickReadbackBuffer() -> MTLBuffer? {
        ensurePickReadbackBuffer()
        return pickReadbackBuffers[frameIndex] ?? nil
    }

    private func ensureFrameStorage() {
        if instanceBuffers.count < maxFramesInFlight {
            instanceBuffers = Array(repeating: nil, count: maxFramesInFlight)
            instanceBufferCapacities = Array(repeating: 0, count: maxFramesInFlight)
        }
        if pickReadbackBuffers.count < maxFramesInFlight {
            pickReadbackBuffers = Array(repeating: nil, count: maxFramesInFlight)
        }
    }

    private func ensureInstanceBufferCapacity(_ requiredBytes: Int) {
        ensureFrameStorage()
        let currentCapacity = instanceBufferCapacities[frameIndex]
        if let _ = instanceBuffers[frameIndex], currentCapacity >= requiredBytes {
            return
        }
        let newCapacity = max(requiredBytes, max(currentCapacity, 1) * 2)
        instanceBuffers[frameIndex] = Engine.Device.makeBuffer(length: newCapacity, options: [.storageModeShared])
        instanceBuffers[frameIndex]?.label = "InstanceBuffer.Frame\(frameIndex)"
        instanceBufferCapacities[frameIndex] = newCapacity
    }

    private func ensurePickReadbackBuffer() {
        ensureFrameStorage()
        if pickReadbackBuffers[frameIndex] != nil { return }
        pickReadbackBuffers[frameIndex] = Engine.Device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: [.storageModeShared])
        pickReadbackBuffers[frameIndex]?.label = "PickReadback.Frame\(frameIndex)"
    }
}
