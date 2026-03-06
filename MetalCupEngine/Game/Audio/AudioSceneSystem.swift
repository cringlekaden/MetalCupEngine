/// AudioSceneSystem.swift
/// Collects scene audio state and forwards immutable updates to AudioEngineService.
/// Created by Kaden Cringle.

import Foundation

public final class AudioSceneSystem {
    public init() {}

    public func update(scene: EngineScene, frame: FrameContext) {
        guard let audioService = scene.engineContext?.audioEngineService else { return }

        var primaryListener: AudioFrameListenerState?
        var fallbackListener: AudioFrameListenerState?
        scene.ecs.viewDeterministic(AudioListenerComponent.self, TransformComponent.self) { entity, listener, _ in
            guard listener.isEnabled else { return }
            let world = scene.renderWorldTransform(for: entity)
            let state = AudioFrameListenerState(entityId: entity.id, worldTransform: world, listener: listener)
            if listener.isPrimary, primaryListener == nil {
                primaryListener = state
            } else if fallbackListener == nil {
                fallbackListener = state
            }
        }

        var sources: [AudioFrameSourceState] = []
        scene.ecs.viewDeterministic(AudioSourceComponent.self, TransformComponent.self) { entity, source, _ in
            guard source.isEnabled else { return }
            let world = scene.renderWorldTransform(for: entity)
            sources.append(
                AudioFrameSourceState(entityId: entity.id, worldTransform: world, source: source)
            )
        }

        let update = AudioFrameUpdate(
            frameTime: frame.time,
            listener: primaryListener ?? fallbackListener,
            sources: sources
        )
        audioService.process(update: update)
    }
}
