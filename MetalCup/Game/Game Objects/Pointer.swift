//
//  Player.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

class Pointer: GameObject {
    
    private var _camera: Camera!
    
    init(camera: Camera) {
        super.init(name: "Pointer", meshType: .TriangleCustom)
        self._camera = camera
    }
    
    override func doUpdate() {
        self.rotateZ(-atan2f(Mouse.GetMouseViewportPosition().x - getPositionX() + _camera.getPositionX(), Mouse.GetMouseViewportPosition().y - getPositionY() + _camera.getPositionY()))
    }
}
