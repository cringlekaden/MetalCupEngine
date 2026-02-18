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
            yaw = transform.rotation.y
            pitch = transform.rotation.x
            let forward = forwardVector(pitch: pitch, yaw: yaw)
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

        let forward = forwardVector(pitch: pitch, yaw: yaw)
        transform.position = focalPoint - forward * distance
        transform.rotation = SIMD3<Float>(pitch, yaw, 0.0)
    }

    private func orbit(delta: SIMD2<Float>) {
        yaw += delta.x * lookSpeed * 0.02 * orbitSpeed
        pitch += delta.y * lookSpeed * 0.02 * orbitSpeed
        pitch = clampPitch(pitch)
    }

    private func pan(delta: SIMD2<Float>) {
        let right = rightVector(pitch: pitch, yaw: yaw)
        let up = SIMD3<Float>(0, 1, 0)
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
        yaw += delta.x * lookSpeed * 0.02
        pitch += delta.y * lookSpeed * 0.02
        pitch = clampPitch(pitch)
    }

    private func fly(dt: Float, keys: [Bool]) {
        let forward = forwardVector(pitch: pitch, yaw: yaw)
        let right = rightVector(pitch: pitch, yaw: yaw)
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

    private func forwardVector(pitch: Float, yaw: Float) -> SIMD3<Float> {
        let cp = cos(pitch)
        let sp = sin(pitch)
        let cy = cos(yaw)
        let sy = sin(yaw)
        return simd_normalize(SIMD3<Float>(sy * cp, -sp, -cy * cp))
    }

    private func rightVector(pitch: Float, yaw: Float) -> SIMD3<Float> {
        let forward = forwardVector(pitch: pitch, yaw: yaw)
        return simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
    }

    private func clampPitch(_ value: Float) -> Float {
        let maxPitch = Float(89.0).toRadians
        return min(max(value, -maxPitch), maxPitch)
    }
}
