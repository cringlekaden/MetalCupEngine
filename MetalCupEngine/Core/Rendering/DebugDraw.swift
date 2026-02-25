/// DebugDraw.swift
/// Provides a submission queue for debug rendering.
/// Created by Kaden Cringle.

import simd

public final class DebugDraw {
    private var submittedGridParams: GridParams?
    private var submittedLines: [DebugLine] = []
    public var lineThickness: Float = 0.08

    public init() {}

    public func beginFrame() {
        submittedGridParams = nil
        submittedLines.removeAll(keepingCapacity: true)
    }

    public func endFrame() {
        // Intentionally empty: submission queue persists until next beginFrame.
    }

    public func submitGridXZ(_ params: GridParams) {
        submittedGridParams = params
    }

    public func submitLine(_ start: SIMD3<Float>, _ end: SIMD3<Float>, color: SIMD4<Float>) {
        submittedLines.append(DebugLine(start: start, end: end, color: color))
    }

    public func submitWireBox(transform: matrix_float4x4, halfExtents: SIMD3<Float>, color: SIMD4<Float>) {
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(-halfExtents.x, -halfExtents.y, -halfExtents.z),
            SIMD3<Float>(halfExtents.x, -halfExtents.y, -halfExtents.z),
            SIMD3<Float>(halfExtents.x, halfExtents.y, -halfExtents.z),
            SIMD3<Float>(-halfExtents.x, halfExtents.y, -halfExtents.z),
            SIMD3<Float>(-halfExtents.x, -halfExtents.y, halfExtents.z),
            SIMD3<Float>(halfExtents.x, -halfExtents.y, halfExtents.z),
            SIMD3<Float>(halfExtents.x, halfExtents.y, halfExtents.z),
            SIMD3<Float>(-halfExtents.x, halfExtents.y, halfExtents.z)
        ]
        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        for (a, b) in edges {
            let start = transformPoint(transform, points[a])
            let end = transformPoint(transform, points[b])
            submitLine(start, end, color: color)
        }
    }

    public func submitWireSphere(transform: matrix_float4x4, radius: Float, color: SIMD4<Float>, segments: Int = 16) {
        if segments <= 3 { return }
        submitCircle(transform: transform, radius: radius, axis: 0, color: color, segments: segments)
        submitCircle(transform: transform, radius: radius, axis: 1, color: color, segments: segments)
        submitCircle(transform: transform, radius: radius, axis: 2, color: color, segments: segments)
    }

    public func submitWireCapsule(transform: matrix_float4x4, radius: Float, halfHeight: Float, color: SIMD4<Float>, segments: Int = 16) {
        if segments <= 3 { return }
        submitCircle(transform: transform, radius: radius, axis: 1, color: color, segments: segments)
        let top = transform * matrix_float4x4(translation: SIMD3<Float>(0.0, halfHeight, 0.0))
        let bottom = transform * matrix_float4x4(translation: SIMD3<Float>(0.0, -halfHeight, 0.0))
        submitCircle(transform: top, radius: radius, axis: 1, color: color, segments: segments)
        submitCircle(transform: bottom, radius: radius, axis: 1, color: color, segments: segments)

        let sidePoints = [
            (SIMD3<Float>(radius, halfHeight, 0.0), SIMD3<Float>(radius, -halfHeight, 0.0)),
            (SIMD3<Float>(-radius, halfHeight, 0.0), SIMD3<Float>(-radius, -halfHeight, 0.0)),
            (SIMD3<Float>(0.0, halfHeight, radius), SIMD3<Float>(0.0, -halfHeight, radius)),
            (SIMD3<Float>(0.0, halfHeight, -radius), SIMD3<Float>(0.0, -halfHeight, -radius))
        ]
        for (a, b) in sidePoints {
            submitLine(transformPoint(transform, a), transformPoint(transform, b), color: color)
        }
    }

    func gridParams() -> GridParams? {
        submittedGridParams
    }

    func lines() -> [DebugLine] {
        submittedLines
    }

    private func submitCircle(transform: matrix_float4x4, radius: Float, axis: Int, color: SIMD4<Float>, segments: Int) {
        let twoPi = Float.pi * 2.0
        for i in 0..<segments {
            let a0 = (Float(i) / Float(segments)) * twoPi
            let a1 = (Float(i + 1) / Float(segments)) * twoPi
            let p0 = circlePoint(radius: radius, angle: a0, axis: axis)
            let p1 = circlePoint(radius: radius, angle: a1, axis: axis)
            submitLine(transformPoint(transform, p0), transformPoint(transform, p1), color: color)
        }
    }

    private func circlePoint(radius: Float, angle: Float, axis: Int) -> SIMD3<Float> {
        let c = cos(angle)
        let s = sin(angle)
        switch axis {
        case 0:
            return SIMD3<Float>(0.0, c * radius, s * radius)
        case 1:
            return SIMD3<Float>(c * radius, 0.0, s * radius)
        default:
            return SIMD3<Float>(c * radius, s * radius, 0.0)
        }
    }

    private func transformPoint(_ matrix: matrix_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let p = SIMD4<Float>(point.x, point.y, point.z, 1.0)
        let result = matrix * p
        return SIMD3<Float>(result.x, result.y, result.z)
    }
}

public struct DebugLine {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var color: SIMD4<Float>
}

extension matrix_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
    }
}
