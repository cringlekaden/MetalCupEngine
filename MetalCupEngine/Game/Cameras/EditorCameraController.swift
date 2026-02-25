/// EditorCameraController.swift
/// Defines the EditorCameraController types and helpers for the engine.
/// Created by Kaden Cringle.

import simd

public final class EditorCameraController {
    private var yaw: Float = 0.0
    private var pitch: Float = 0.0
    private var distance: Float = 10.0
    private var focalPoint: SIMD3<Float> = .zero
    private var lastInitialized = false

    private let orbitSpeed: Float = 0.8
    private let panSpeed: Float = 0.0075
    private let zoomSpeed: Float = 12.0
    private let moveSpeed: Float = 12.0
    private let lookSpeed: Float = 0.12

    public init() {}

    public func update(transform: inout TransformComponent, frame: FrameContext) {
        if !lastInitialized {
            let rotation = simd_quatf(real: transform.rotation.w,
                                      imag: SIMD3<Float>(transform.rotation.x,
                                                        transform.rotation.y,
                                                        transform.rotation.z))
            let forward = simd_normalize(rotation.act(SIMD3<Float>(0, 0, -1)))
            yaw = atan2(forward.x, -forward.z)
            let clampedY = max(-1.0 as Float, min(1.0 as Float, -forward.y))
            pitch = asinf(clampedY)
            focalPoint = transform.position + forward * distance
            lastInitialized = true
        }

        let keys = frame.input.keys
        let mouseButtons = frame.input.mouseButtons

        let altDown = keyDown(.option, keys: keys) || keyDown(.rightOption, keys: keys)
        let shiftDown = keyDown(.shift, keys: keys)
        let rightMouse = mouseDown(.right, buttons: mouseButtons)
        let leftMouse = mouseDown(.left, buttons: mouseButtons)

        let mouseDelta = frame.input.mouseDelta
        let scrollDelta = frame.input.scrollDelta
        let dt = frame.time.deltaTime

        if altDown && leftMouse && shiftDown {
            pan(delta: mouseDelta)
        } else if altDown && leftMouse {
            orbit(delta: mouseDelta)
        } else if altDown && rightMouse {
            dolly(delta: mouseDelta.y)
        } else if rightMouse {
            freeLook(delta: mouseDelta)
            fly(dt: dt, keys: keys)
        } else {
            if scrollDelta != 0 {
                zoom(delta: scrollDelta)
            }
        }

        let basis = basisFromYawPitch()
        let forward = basis.forward
        transform.position = focalPoint - forward * distance
        transform.rotation = basis.rotation
    }

    private func orbit(delta: SIMD2<Float>) {
        yaw -= delta.x * lookSpeed * 0.02 * orbitSpeed
        pitch -= delta.y * lookSpeed * 0.02 * orbitSpeed
        pitch = clampPitch(pitch)
    }

    private func pan(delta: SIMD2<Float>) {
        let basis = basisFromYawPitch()
        let right = basis.right
        let up = basis.up
        let scale = panSpeed * max(distance, 0.1)
        focalPoint -= right * delta.x * scale
        focalPoint += up * delta.y * scale
    }

    private func zoom(delta: Float) {
        let amount = delta * zoomSpeed * 0.05
        distance = max(1.0, distance - amount)
    }

    private func dolly(delta: Float) {
        let amount = delta * zoomSpeed * 0.02
        distance = max(1.0, distance + amount)
    }

    private func freeLook(delta: SIMD2<Float>) {
        yaw -= delta.x * lookSpeed * 0.02
        pitch -= delta.y * lookSpeed * 0.02
        pitch = clampPitch(pitch)
    }

    private func fly(dt: Float, keys: [Bool]) {
        let basis = basisFromYawPitch()
        let forward = basis.forward
        let right = basis.right
        var move = SIMD3<Float>.zero
        if keyDown(.w, keys: keys) { move += forward }
        if keyDown(.s, keys: keys) { move -= forward }
        if keyDown(.a, keys: keys) { move -= right }
        if keyDown(.d, keys: keys) { move += right }
        if keyDown(.q, keys: keys) { move.y -= 1 }
        if keyDown(.e, keys: keys) { move.y += 1 }
        if simd_length_squared(move) > 0 {
            let delta = simd_normalize(move) * moveSpeed * dt
            focalPoint += delta
        }
    }

    private func keyDown(_ code: KeyCodes, keys: [Bool]) -> Bool {
        let index = Int(code.rawValue)
        return index >= 0 && index < keys.count ? keys[index] : false
    }

    private func mouseDown(_ code: MouseCodes, buttons: [Bool]) -> Bool {
        let index = Int(code.rawValue)
        return index >= 0 && index < buttons.count ? buttons[index] : false
    }

    private func basisFromYawPitch() -> (forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, rotation: SIMD4<Float>) {
        let worldUp = SIMD3<Float>(0, 1, 0)
        let yawQuat = simd_quatf(angle: yaw, axis: worldUp)
        let yawRight = simd_normalize(yawQuat.act(SIMD3<Float>(1, 0, 0)))
        let pitchQuat = simd_quatf(angle: pitch, axis: yawRight)
        let rotationQuat = simd_normalize(pitchQuat * yawQuat)

        let forward = simd_normalize(rotationQuat.act(SIMD3<Float>(0, 0, -1)))
        let right = simd_normalize(rotationQuat.act(SIMD3<Float>(1, 0, 0)))
        let up = simd_normalize(rotationQuat.act(SIMD3<Float>(0, 1, 0)))
        let rotation = TransformMath.normalizedQuaternion(SIMD4<Float>(rotationQuat.imag.x,
                                                                     rotationQuat.imag.y,
                                                                     rotationQuat.imag.z,
                                                                     rotationQuat.real))
        return (forward: forward, right: right, up: up, rotation: rotation)
    }

    private func clampPitch(_ value: Float) -> Float {
        let maxPitch = Float(89.0).toRadians
        return min(max(value, -maxPitch), maxPitch)
    }
}
