//
//  AssetTypes.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

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

    public init(handle: AssetHandle,
                type: AssetType,
                sourcePath: String,
                importSettings: [String: String] = [:],
                dependencies: [AssetHandle] = []) {
        self.handle = handle
        self.type = type
        self.sourcePath = sourcePath
        self.importSettings = importSettings
        self.dependencies = dependencies
    }
}
