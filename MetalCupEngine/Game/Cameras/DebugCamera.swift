//
//  DebugCamera.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import simd

class DebugCamera: Camera {
    
    private var _projectionMatrix = matrix_identity_float4x4
    override var projectionMatrix: matrix_float4x4 {
        return _projectionMatrix
    }
    
    private var _moveSpeed: Float = 15.0
    private var _turnSpeed: Float = 1.0

    private var pressedKeys = Set<UInt16>()
    private var rightMouseDown = false
    private var mouseDelta = SIMD2<Float>(0, 0)
    
    init() {
        super.init(name: "Debug", cameraType: .Debug)
    }
    
    override func setProjectionMatrix() {
        _projectionMatrix = matrix_float4x4.perspective(fovDegrees: 45.0, aspectRatio: Renderer.AspectRatio, near: 0.1, far: 1000)
    }

    override func doUpdate() {
        let dt = GameTime.DeltaTime
        let moveSpeed = _moveSpeed
        let turnSpeed = _turnSpeed
        // Combine event-driven and polling-based input
        rightMouseDown = Mouse.IsMouseButtonPressed(button: .right)
        let isRightDown = rightMouseDown
        let polledDelta = SIMD2<Float>(Mouse.GetDX(), Mouse.GetDY())
        let frameMouseDelta = mouseDelta + polledDelta
        let isKeyDown: (KeyCodes) -> Bool = { key in
            return self.pressedKeys.contains(key.rawValue) || Keyboard.IsKeyPressed(key)
        }

        // Mouse look (only while holding right mouse button)
        if isRightDown {
            let dy = frameMouseDelta.y * dt * turnSpeed // pitch
            let dx = frameMouseDelta.x * dt * turnSpeed // yaw
            self.rotate(dy, dx, 0)
            // Clamp pitch to avoid flipping over
            let maxPitch: Float = Float(89.0).toRadians
            var pitch = getRotationX()
            if pitch > maxPitch { pitch = maxPitch }
            if pitch < -maxPitch { pitch = -maxPitch }
            setRotationX(pitch)
        }
        // Derive camera basis from view matrix so movement follows look direction
        let view = self.viewMatrix
        let right = simd_normalize(SIMD3<Float>(view.columns.0.x, view.columns.1.x, view.columns.2.x))
        let forward = simd_normalize(-SIMD3<Float>(view.columns.0.z, view.columns.1.z, view.columns.2.z))
        // WASD input (UFO style)
        var moveDir = SIMD3<Float>(0,0,0)
        if isKeyDown(.w) { moveDir += forward }
        if isKeyDown(.s) { moveDir -= forward }
        if isKeyDown(.a) { moveDir -= right }
        if isKeyDown(.d) { moveDir += right }
        if simd_length_squared(moveDir) > 0.0 {
            let delta = simd_normalize(moveDir) * moveSpeed * dt
            let pos = getPosition()
            setPosition(pos.x + delta.x, pos.y + delta.y, pos.z + delta.z)
        }
        // consume frame mouse delta
        mouseDelta = .zero
    }

    override func onEvent(_ event: Event) {
        switch event {
        case let e as KeyPressedEvent:
            pressedKeys.insert(e.keyCode)
        case let e as KeyReleasedEvent:
            pressedKeys.remove(e.keyCode)
        case let e as MouseButtonPressedEvent:
            if e.button == 1 { rightMouseDown = true }
        case let e as MouseButtonReleasedEvent:
            if e.button == 1 { rightMouseDown = false }
        case let e as MouseMovedEvent:
            mouseDelta += e.delta
        default:
            break
        }
    }
}
