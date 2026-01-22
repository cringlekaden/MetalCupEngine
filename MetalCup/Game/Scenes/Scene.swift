//
//  Scene.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

class Scene: Node {
    
    private var _cameraManager = CameraManager()
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    
    override init(name: String) {
        super.init(name: name)
        buildScene()
    }
    
    override func update() {
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        _sceneConstants.cameraPosition = _cameraManager.currentCamera.getPosition()
        super.update()
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Rendering Scene \(getName())...")
        renderCommandEncoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride, index: 1)
        _lightManager.setLightData(renderCommandEncoder)
        super.render(renderCommandEncoder: renderCommandEncoder)
        renderCommandEncoder.popDebugGroup()
    }
    
    func updateCameras() {
        _cameraManager.update()
    }
    
    func addCamera(_ camera: Camera, _ setCurrent: Bool = true) {
        _cameraManager.registerCamera(camera: camera)
        if(setCurrent) {
            _cameraManager.setCamera(camera.cameraType)
        }
    }
    
    func addLight(_ light: LightObject) {
        addChild(light)
        _lightManager.addLight(light)
    }
    
    func buildScene() {}
}
