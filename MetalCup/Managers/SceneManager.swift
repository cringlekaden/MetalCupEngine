//
//  SceneManager.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

enum SceneType {
    case Sandbox
}

class SceneManager {
    
    private static var _currentScene: Scene!
    public static var currentScene: Scene {
        return _currentScene
    }
    
    public static func SetScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            _currentScene = Sandbox(name: "Sandbox Scene", environmentMap2D: .Cruise)
        }
    }
    
    public static func Update(deltaTime: Float) {
        GameTime.UpdateTime(deltaTime)
        _currentScene.updateCameras()
        _currentScene.update()
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.render(renderCommandEncoder: renderCommandEncoder)
    }
}
