//
//  Camera.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import simd

public enum CameraType {
    case Debug
}

public class Camera {

    var cameraType: CameraType!

    private var position = SIMD3<Float>.zero
    private var rotation = SIMD3<Float>.zero
    private var _viewMatrix = matrix_identity_float4x4

    var viewMatrix: matrix_float4x4 {
        return _viewMatrix
    }

    var projectionMatrix: matrix_float4x4 {
        return matrix_identity_float4x4
    }

    init(name: String, cameraType: CameraType) {
        self.cameraType = cameraType
    }

    func setProjectionMatrix() {}

    func update() {
        doUpdate()
        updateViewMatrix()
    }

    func doUpdate() {}

    func onEvent(_ event: Event) {}

    private func updateViewMatrix() {
        _viewMatrix = matrix_identity_float4x4
        _viewMatrix.rotate(angle: rotation.x, axis: xAxis)
        _viewMatrix.rotate(angle: rotation.y, axis: yAxis)
        _viewMatrix.rotate(angle: rotation.z, axis: zAxis)
        _viewMatrix.translate(direction: -position)
    }
}

extension Camera {
    func setPosition(_ position: SIMD3<Float>) {
        self.position = position
        updateViewMatrix()
    }

    func setPosition(_ x: Float, _ y: Float, _ z: Float) {
        setPosition(SIMD3<Float>(x, y, z))
    }

    func getPosition() -> SIMD3<Float> {
        return position
    }

    func setRotation(_ rotation: SIMD3<Float>) {
        self.rotation = rotation
        updateViewMatrix()
    }

    func setRotation(_ x: Float, _ y: Float, _ z: Float) {
        setRotation(SIMD3<Float>(x, y, z))
    }

    func rotate(_ x: Float, _ y: Float, _ z: Float) {
        setRotation(rotation.x + x, rotation.y + y, rotation.z + z)
    }

    func getRotation() -> SIMD3<Float> {
        return rotation
    }

    func getRotationX() -> Float { rotation.x }
    func getRotationY() -> Float { rotation.y }
    func getRotationZ() -> Float { rotation.z }

    func setRotationX(_ value: Float) {
        rotation.x = value
        updateViewMatrix()
    }

    func setRotationY(_ value: Float) {
        rotation.y = value
        updateViewMatrix()
    }

    func setRotationZ(_ value: Float) {
        rotation.z = value
        updateViewMatrix()
    }
}
