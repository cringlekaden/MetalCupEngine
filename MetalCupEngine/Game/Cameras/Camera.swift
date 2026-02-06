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

public class Camera: Node {
    
    var cameraType: CameraType!
    
    private var _viewMatrix = matrix_identity_float4x4
    var viewMatrix: matrix_float4x4 {
        return _viewMatrix
    }
    
    var projectionMatrix: matrix_float4x4 {
        return matrix_identity_float4x4
    }
    
    init(name: String, cameraType: CameraType){
        super.init(name: name)
        self.cameraType = cameraType
    }
    
    func setProjectionMatrix() {}
    
    override func updateModelMatrix() {
        _viewMatrix = matrix_identity_float4x4
        _viewMatrix.rotate(angle: self.getRotationX(), axis: xAxis)
        _viewMatrix.rotate(angle: self.getRotationY(), axis: yAxis)
        _viewMatrix.rotate(angle: self.getRotationZ(), axis: zAxis)
        _viewMatrix.translate(direction: -getPosition())
    }
}
