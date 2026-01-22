//
//  DebugCamera.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import simd

class DebugCamera: Camera {
    
    override var projectionMatrix: matrix_float4x4 {
        return matrix_float4x4.perspective(fovDegrees: 45.0, aspectRatio: Renderer.AspectRatio, near: 0.1, far: 1000)
    }
    
    init() {
        super.init(name: "Debug Camera", cameraType: .Debug)
    }

    override func doUpdate() {
        if(Keyboard.IsKeyPressed(.leftArrow)){
            self.moveX(-GameTime.DeltaTime)
        }
        if(Keyboard.IsKeyPressed(.rightArrow)){
            self.moveX(GameTime.DeltaTime)
        }
        if(Keyboard.IsKeyPressed(.upArrow)){
            self.moveY(GameTime.DeltaTime)
        }
        if(Keyboard.IsKeyPressed(.downArrow)){
            self.moveY(-GameTime.DeltaTime)
        }
        if(Mouse.IsMouseButtonPressed(button: .right)) {
            self.rotate(Mouse.GetDY() * GameTime.DeltaTime, Mouse.GetDX() * GameTime.DeltaTime, 0)
        }
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
