/// SceneRuntime.swift
/// Manages play/pause state and simulation updates for a scene.
/// Created by Kaden Cringle.

import Foundation

public final class SceneRuntime {
    public private(set) var isPlaying: Bool = false
    public private(set) var isPaused: Bool = false

    public init() {}

    public func play() {
        isPlaying = true
        isPaused = false
    }

    public func stop() {
        isPlaying = false
        isPaused = false
    }

    public func pause() {
        guard isPlaying else { return }
        isPaused = true
    }

    public func resume() {
        guard isPlaying else { return }
        isPaused = false
    }

    public func update(scene: EngineScene) {
        scene.runtimeUpdate(isPlaying: isPlaying, isPaused: isPaused)
    }

    public func fixedUpdate(scene: EngineScene) {
        scene.runtimeFixedUpdate()
    }

}
