/// PrefabSerialization.swift
/// Defines prefab serialization helpers.
/// Created by Kaden Cringle.

import Foundation

public enum PrefabSchema {
    public static let currentVersion: Int = 1
}

public struct PrefabEntityDocument: Codable {
    public var localId: UUID
    // parentLocalId is reserved for future hierarchy support (root/children).
    public var parentLocalId: UUID?
    public var components: ComponentsDocument

    public init(localId: UUID, parentLocalId: UUID? = nil, components: ComponentsDocument) {
        self.localId = localId
        self.parentLocalId = parentLocalId
        self.components = components
    }
}

public struct PrefabDocument: Codable {
    public var schemaVersion: Int
    public var name: String
    public var entities: [PrefabEntityDocument]

    public init(schemaVersion: Int = PrefabSchema.currentVersion, name: String, entities: [PrefabEntityDocument]) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.entities = entities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? PrefabSchema.currentVersion
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Prefab"
        if let entities = try? container.decode([PrefabEntityDocument].self, forKey: .entities) {
            self.entities = entities
            return
        }
        let legacyEntities = (try? container.decode([EntityDocument].self, forKey: .entities)) ?? []
        self.entities = legacyEntities.map {
            PrefabEntityDocument(localId: $0.id, parentLocalId: nil, components: $0.components)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case entities
    }
}

public enum PrefabSerializer {
    public static func load(from url: URL) throws -> PrefabDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PrefabDocument.self, from: data)
    }

    public static func save(prefab: PrefabDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(prefab)
        try data.write(to: url, options: [.atomic])
    }
}
