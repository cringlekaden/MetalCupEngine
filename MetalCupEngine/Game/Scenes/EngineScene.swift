//
//  Scene.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

public class EngineScene: Node {
    
    private var _cameraManager = CameraManager()
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    
    public var environmentMapHandle: AssetHandle?
    
    init(name: String, environmentMapHandle: AssetHandle?) {
        super.init(name: name)
        self.environmentMapHandle = environmentMapHandle
        let skybox = Skybox()
        addChild(skybox)
        buildScene()
    }
    
    override func update() {
        _cameraManager.update()
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0;
        _sceneConstants.skyViewMatrix[3][1] = 0;
        _sceneConstants.skyViewMatrix[3][2] = 0;
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        let cameraPosition = _cameraManager.currentCamera.getPosition()
        let hasEnvironment = environmentMapHandle.flatMap { AssetManager.texture(handle: $0) } != nil
        let settings = Renderer.settings
        let iblIntensity = (hasEnvironment && settings.iblEnabled != 0) ? settings.iblIntensity : 0.0
        _sceneConstants.cameraPositionAndIBL = SIMD4<Float>(
            cameraPosition.x,
            cameraPosition.y,
            cameraPosition.z,
            iblIntensity
        )
        super.update()
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Rendering Scene \(getName())...")
        renderCommandEncoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride, index: 1)
        var settings = Renderer.settings
        renderCommandEncoder.setFragmentBytes(&settings, length: RendererSettings.stride, index: 2)
        _lightManager.setLightData(renderCommandEncoder)
        super.render(renderCommandEncoder: renderCommandEncoder)
        renderCommandEncoder.popDebugGroup()
    }
    
    func updateCameras() {
        _cameraManager.update()
    }
    
    func updateAspectRatio() {
        _cameraManager.currentCamera.setProjectionMatrix()
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
    
    override public func onEvent(_ event: Event) {
        _cameraManager.onEvent(event)
        super.onEvent(event)
    }
}
