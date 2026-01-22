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
    
    public static func initialize(_ sceneType: SceneType) {
        SetScene(sceneType)
    }
    
    public static func SetScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            _currentScene = Sandbox(name: "Sandbox Scene")
        }
    }
    
    public static func TickScene(renderCommandEncoder: MTLRenderCommandEncoder, deltaTime: Float) {
        GameTime.UpdateTime(deltaTime)
        _currentScene.updateCameras()
        _currentScene.update()
        _currentScene.render(renderCommandEncoder: renderCommandEncoder)
    }
}
