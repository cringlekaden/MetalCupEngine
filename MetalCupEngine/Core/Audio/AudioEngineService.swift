/// AudioEngineService.swift
/// Defines the engine-level audio service boundary and threading contract.
/// Created by Kaden Cringle.

import Foundation

public struct AudioFrameSourceState {
    public let entityId: UUID
    public let worldTransform: TransformComponent
    public let source: AudioSourceComponent

    public init(entityId: UUID,
                worldTransform: TransformComponent,
                source: AudioSourceComponent) {
        self.entityId = entityId
        self.worldTransform = worldTransform
        self.source = source
    }
}

public struct AudioFrameListenerState {
    public let entityId: UUID
    public let worldTransform: TransformComponent
    public let listener: AudioListenerComponent

    public init(entityId: UUID,
                worldTransform: TransformComponent,
                listener: AudioListenerComponent) {
        self.entityId = entityId
        self.worldTransform = worldTransform
        self.listener = listener
    }
}

public struct AudioFrameUpdate {
    public let frameTime: FrameTime
    public let listener: AudioFrameListenerState?
    public let sources: [AudioFrameSourceState]

    public init(frameTime: FrameTime,
                listener: AudioFrameListenerState?,
                sources: [AudioFrameSourceState]) {
        self.frameTime = frameTime
        self.listener = listener
        self.sources = sources
    }
}

public protocol AudioEngineService: AnyObject {
    /// Control/update API. Called on the engine update thread (main thread today).
    /// Implementations may forward immutable command data to an internal audio thread.
    func process(update: AudioFrameUpdate)
}

public final class NullAudioEngineService: AudioEngineService {
    public init() {}
    public func process(update: AudioFrameUpdate) {}
}
