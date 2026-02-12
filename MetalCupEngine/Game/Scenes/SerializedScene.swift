import Foundation

public final class SerializedScene: EngineScene {
    public init(document: SceneDocument) {
        super.init(id: document.id, name: document.name, environmentMapHandle: nil, shouldBuildScene: false)
        apply(document: document)
    }
}
