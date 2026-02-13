/// AssetTypes.swift
/// Defines the AssetTypes types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation

public struct AssetHandle: Hashable, Codable {
    public let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(string: String) {
        self.rawValue = UUID(uuidString: string) ?? UUID()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.rawValue = UUID(uuidString: value) ?? UUID()
    }
}

public typealias TextureHandle = AssetHandle
public typealias MeshHandle = AssetHandle
public typealias MaterialHandle = AssetHandle

public enum AssetType: String, Codable {
    case texture
    case model
    case material
    case environment
    case scene
    case prefab
    case unknown
}

public struct AssetMetadata: Codable {
    public var handle: AssetHandle
    public var type: AssetType
    public var sourcePath: String
    public var importSettings: [String: String]
    public var dependencies: [AssetHandle]
    public var lastModified: TimeInterval

    public init(handle: AssetHandle,
                type: AssetType,
                sourcePath: String,
                importSettings: [String: String] = [:],
                dependencies: [AssetHandle] = [],
                lastModified: TimeInterval = 0) {
        self.handle = handle
        self.type = type
        self.sourcePath = sourcePath
        self.importSettings = importSettings
        self.dependencies = dependencies
        self.lastModified = lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(AssetHandle.self, forKey: .handle)
        type = try container.decode(AssetType.self, forKey: .type)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        importSettings = try container.decodeIfPresent([String: String].self, forKey: .importSettings) ?? [:]
        dependencies = try container.decodeIfPresent([AssetHandle].self, forKey: .dependencies) ?? []
        lastModified = try container.decodeIfPresent(TimeInterval.self, forKey: .lastModified) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(type, forKey: .type)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(importSettings, forKey: .importSettings)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(lastModified, forKey: .lastModified)
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case type
        case sourcePath
        case importSettings
        case dependencies
        case lastModified
    }
}
