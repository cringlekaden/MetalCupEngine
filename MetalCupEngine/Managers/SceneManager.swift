//
//  SceneManager.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit
import simd

public enum SceneType {
    case Sandbox
}

public class SceneManager {
    
    private static var _currentScene: EngineScene!
    public static var currentScene: EngineScene {
        return _currentScene
    }
    
    public static func SetScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            let envHandle = AssetManager.handle(forSourcePath: "Resources/neonCity.exr")
            _currentScene = Sandbox(name: "Sandbox Scene", environmentMapHandle: envHandle)
        }
    }
    
    public static func Update() {
        _currentScene.update()
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.render(renderCommandEncoder: renderCommandEncoder)
    }

    public static func UpdateViewportSize(_ size: SIMD2<Float>) {
        Renderer.ViewportSize = size
        _currentScene.updateAspectRatio()
    }
}
