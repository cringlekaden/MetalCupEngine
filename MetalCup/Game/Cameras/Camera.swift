//
//  Camera.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import simd

enum CameraType {
    case Debug
}

class Camera: Node {
    
    var cameraType: CameraType!
    var viewMatrix: matrix_float4x4 {
        var viewMatrix = matrix_identity_float4x4
        viewMatrix.rotate(angle: self.getRotationX(), axis: xAxis)
        viewMatrix.rotate(angle: self.getRotationY(), axis: yAxis)
        viewMatrix.rotate(angle: self.getRotationZ(), axis: zAxis)
        viewMatrix.translate(direction: -getPosition())
        return viewMatrix
    }
    var projectionMatrix: matrix_float4x4 {
        return matrix_identity_float4x4
    }
    
    init(name: String, cameraType: CameraType) {
        super.init(name: name)
        self.cameraType = cameraType
    }
}
