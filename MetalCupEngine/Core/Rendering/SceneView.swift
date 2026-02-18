/// SceneView.swift
/// Describes the camera/view parameters used for rendering a scene.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct SceneView {
    public var viewMatrix: matrix_float4x4
    public var projectionMatrix: matrix_float4x4
    public var cameraPosition: SIMD3<Float>
    public var viewportSize: SIMD2<Float>
    public var viewportOrigin: SIMD2<Float>
    public var mousePositionInViewport: SIMD2<Float>?
    public var requestPick: Bool
    public var exposure: Float
    public var layerMask: LayerMask
    public var selectedEntityIds: [UUID]
    public var debugFlags: UInt32
    public var isEditorView: Bool

    public init(viewMatrix: matrix_float4x4 = matrix_identity_float4x4,
                projectionMatrix: matrix_float4x4 = matrix_identity_float4x4,
                cameraPosition: SIMD3<Float> = .zero,
                viewportSize: SIMD2<Float> = .zero,
                viewportOrigin: SIMD2<Float> = .zero,
                mousePositionInViewport: SIMD2<Float>? = nil,
                requestPick: Bool = false,
                exposure: Float = 1.0,
                layerMask: LayerMask = .all,
                selectedEntityIds: [UUID] = [],
                debugFlags: UInt32 = 0,
                isEditorView: Bool = false) {
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.cameraPosition = cameraPosition
        self.viewportSize = viewportSize
        self.viewportOrigin = viewportOrigin
        self.mousePositionInViewport = mousePositionInViewport
        self.requestPick = requestPick
        self.exposure = exposure
        self.layerMask = layerMask
        self.selectedEntityIds = selectedEntityIds
        self.debugFlags = debugFlags
        self.isEditorView = isEditorView
    }
}
