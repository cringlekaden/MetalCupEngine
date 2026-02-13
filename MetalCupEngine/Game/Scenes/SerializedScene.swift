/// SerializedScene.swift
/// Defines the SerializedScene types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

public final class SerializedScene: EngineScene {
    public init(document: SceneDocument) {
        super.init(id: document.id, name: document.name, environmentMapHandle: nil, shouldBuildScene: false)
        apply(document: document)
    }
}
