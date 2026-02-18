/// Scene.swift
/// Data-only ECS container for entities and components.
/// Created by Kaden Cringle.

import Foundation

public final class Scene {
    public let ecs: SceneECS
    public let id: UUID
    public var name: String
    public var environmentMapHandle: AssetHandle?

    public init(id: UUID = UUID(),
                name: String,
                environmentMapHandle: AssetHandle? = nil,
                shouldBuildScene: Bool = true) {
        self.id = id
        self.name = name
        self.environmentMapHandle = environmentMapHandle
        self.ecs = SceneECS()
        if shouldBuildScene {
            buildScene()
        }
    }

    func buildScene() {}
}
