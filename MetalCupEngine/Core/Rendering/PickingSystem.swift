/// PickingSystem.swift
/// Owns picking ID mapping and GPU readback for entity selection.
/// Created by Kaden Cringle.

import MetalKit

public struct PickingRequest {
    public var pixel: SIMD2<Int>
    public var mask: LayerMask

    public init(pixel: SIMD2<Int>, mask: LayerMask) {
        self.pixel = pixel
        self.mask = mask
    }
}

public final class PickingSystem {
    private var pendingRequest: PickingRequest?
    private var pickIdToEntity: [UInt32: Entity] = [:]
    private var entityIdToPickId: [UUID: UInt32] = [:]
    private var nextPickId: UInt32 = 1

    public init() {}

    public func resetMapping() {
        pickIdToEntity.removeAll(keepingCapacity: true)
        entityIdToPickId.removeAll(keepingCapacity: true)
        nextPickId = 1
    }

    public func assignPickId(for entity: Entity) -> UInt32 {
        if let existing = entityIdToPickId[entity.id] {
            return existing
        }
        let id = nextPickId
        nextPickId &+= 1
        pickIdToEntity[id] = entity
        entityIdToPickId[entity.id] = id
        return id
    }

    public func entity(for pickId: UInt32) -> Entity? {
        pickIdToEntity[pickId]
    }

    public func pickId(for entityId: UUID) -> UInt32 {
        entityIdToPickId[entityId] ?? 0
    }

    public func requestPick(pixel: SIMD2<Int>, mask: LayerMask) {
        pendingRequest = PickingRequest(pixel: pixel, mask: mask)
    }

    public func consumeRequest() -> PickingRequest? {
        let request = pendingRequest
        pendingRequest = nil
        return request
    }

    public func enqueueReadback(
        request: PickingRequest,
        pickTexture: MTLTexture,
        readbackBuffer: MTLBuffer,
        commandBuffer: MTLCommandBuffer,
        completion: @escaping (UInt32, LayerMask) -> Void
    ) {
        let width = max(1, pickTexture.width)
        let height = max(1, pickTexture.height)
        let clampedX = max(0, min(request.pixel.x, width - 1))
        let clampedY = max(0, min(request.pixel.y, height - 1))
        let origin = MTLOrigin(x: clampedX, y: clampedY, z: 0)
        let size = MTLSize(width: 1, height: 1, depth: 1)

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Pick Readback Blit"
            blit.copy(from: pickTexture,
                      sourceSlice: 0,
                      sourceLevel: 0,
                      sourceOrigin: origin,
                      sourceSize: size,
                      to: readbackBuffer,
                      destinationOffset: 0,
                      destinationBytesPerRow: MemoryLayout<UInt32>.stride,
                      destinationBytesPerImage: MemoryLayout<UInt32>.stride)
            blit.endEncoding()
        }

        commandBuffer.addCompletedHandler { _ in
            let pointer = readbackBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
            completion(pointer.pointee, request.mask)
        }
    }
}
