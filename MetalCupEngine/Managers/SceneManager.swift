/// SceneManager.swift
/// Defines the SceneManager types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import MetalKit
import simd

public enum SceneType {
    case Sandbox
}

public final class SceneManager {
    
    private static var editorScene: EngineScene?
    private static var runtimeScene: EngineScene?
    public static var currentScene: EngineScene {
        if isPlaying, let runtimeScene {
            return runtimeScene
        }
        if let editorScene {
            return editorScene
        }
        let placeholder = makeEmptyScene()
        editorScene = placeholder
        return placeholder
    }
    public static var hasScene: Bool {
        return editorScene != nil
    }
    public static private(set) var isPlaying: Bool = false
    public static private(set) var isPaused: Bool = false
    private static var editorSnapshot: SceneDocument?

    public static func setScene(_ scene: EngineScene) {
        editorScene = scene
    }
    
    public static func setScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            editorScene = Sandbox(name: "Sandbox Scene", environmentMapHandle: nil)
        }
    }
    
    public static func update() {
        if isPlaying {
            runtimeScene?.onUpdate(isPlaying: true, isPaused: isPaused)
        } else {
            editorScene?.onUpdate(isPlaying: false, isPaused: false)
        }
    }
    
    public static func render(renderCommandEncoder: MTLRenderCommandEncoder) {
        if isPlaying {
            runtimeScene?.onRender(encoder: renderCommandEncoder)
        } else {
            editorScene?.onRender(encoder: renderCommandEncoder)
        }
    }

    public static func updateViewportSize(_ size: SIMD2<Float>) {
        Renderer.ViewportSize = size
        currentScene.updateAspectRatio()
    }

    public static func play() {
        if isPlaying { return }
        guard let editorScene else { return }
        editorSnapshot = editorScene.toDocument(rendererSettingsOverride: RendererSettingsDTO(settings: Renderer.settings))
        if let snapshot = editorSnapshot {
            runtimeScene = SerializedScene(document: snapshot)
        } else {
            runtimeScene = makeEmptyScene()
        }
        isPlaying = true
        isPaused = false
    }

    public static func stop() {
        if !isPlaying { return }
        if let snapshot = editorSnapshot, let editorScene {
            editorScene.apply(document: snapshot)
            if let settings = snapshot.rendererSettingsOverride {
                Renderer.settings = settings.makeRendererSettings()
            }
        }
        editorSnapshot = nil
        runtimeScene = nil
        isPlaying = false
        isPaused = false
    }

    public static func pause() {
        if !isPlaying { return }
        isPaused = true
    }

    public static func resume() {
        if !isPlaying { return }
        isPaused = false
    }

    public static func saveScene(to url: URL) throws {
        guard let editorScene else { return }
        try SceneSerializer.save(scene: editorScene, to: url)
    }

    public static func loadScene(from url: URL) throws {
        let document = try SceneSerializer.load(from: url)
        if let settings = document.rendererSettingsOverride {
            Renderer.settings = settings.makeRendererSettings()
        }
        let scene = SerializedScene(document: document)
        editorScene = scene
        if isPlaying {
            runtimeScene = SerializedScene(document: document)
        }
    }

    public static func getEditorScene() -> EngineScene? {
        return editorScene
    }

    private static func makeEmptyScene() -> EngineScene {
        let document = SceneDocument(id: UUID(), name: "Untitled", entities: [])
        return SerializedScene(document: document)
    }
}
