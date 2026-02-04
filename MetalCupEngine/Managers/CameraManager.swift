//
//  CameraManager.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

class CameraManager {
    
    private var _cameras: [CameraType : Camera] = [:]
    
    public var currentCamera: Camera!
    
    public func registerCamera(camera: Camera) {
        _cameras[camera.cameraType] = camera
    }
    
    public func setCamera(_ cameraType: CameraType) {
        currentCamera = _cameras[cameraType]
    }
    
    internal func update() {
        for camera in _cameras.values {
            camera.update()
        }
    }
}
