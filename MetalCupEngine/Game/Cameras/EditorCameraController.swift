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

    public func update(transform: inout TransformComponent) {
        if !lastInitialized {
            yaw = transform.rotation.y
            pitch = transform.rotation.x
            let forward = forwardVector(pitch: pitch, yaw: yaw)
            focalPoint = transform.position + forward * distance
            lastInitialized = true
        }

        let altDown = Keyboard.IsKeyPressed(.option) || Keyboard.IsKeyPressed(.rightOption)
        let shiftDown = Keyboard.IsKeyPressed(.shift)
        let rightMouse = Mouse.IsMouseButtonPressed(button: .right)
        let leftMouse = Mouse.IsMouseButtonPressed(button: .left)

        let mouseDelta = SIMD2<Float>(Mouse.GetDX(), Mouse.GetDY())
        let scrollDelta = Mouse.GetDWheel()
        let dt = Time.DeltaTime

        if altDown && leftMouse && shiftDown {
            pan(delta: mouseDelta)
        } else if altDown && leftMouse {
            orbit(delta: mouseDelta)
        } else if altDown && rightMouse {
            dolly(delta: mouseDelta.y)
        } else if rightMouse {
            freeLook(delta: mouseDelta)
            fly(dt: dt)
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

    private func fly(dt: Float) {
        let forward = forwardVector(pitch: pitch, yaw: yaw)
        let right = rightVector(pitch: pitch, yaw: yaw)
        var move = SIMD3<Float>.zero
        if Keyboard.IsKeyPressed(.w) { move += forward }
        if Keyboard.IsKeyPressed(.s) { move -= forward }
        if Keyboard.IsKeyPressed(.a) { move -= right }
        if Keyboard.IsKeyPressed(.d) { move += right }
        if Keyboard.IsKeyPressed(.q) { move.y -= 1 }
        if Keyboard.IsKeyPressed(.e) { move.y += 1 }
        if simd_length_squared(move) > 0 {
            let delta = simd_normalize(move) * moveSpeed * dt
            focalPoint += delta
        }
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
