/// AssetTypes.swift
/// Defines the AssetTypes types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

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
public typealias SkeletonHandle = AssetHandle
public typealias AnimationClipHandle = AssetHandle
public typealias AudioHandle = AssetHandle

public enum AssetType: String, Codable {
    case texture
    case model
    case material
    case environment
    case scene
    case prefab
    case script
    case skeleton
    case animationClip
    case audio
    case unknown
}

public struct SkeletonAsset {
    public struct Joint {
        public var name: String
        public var parentIndex: Int
        public var bindLocalPosition: SIMD3<Float>
        public var bindLocalRotation: SIMD4<Float>
        public var bindLocalScale: SIMD3<Float>
        public var inverseBindGlobalMatrix: simd_float4x4?

        public init(name: String,
                    parentIndex: Int,
                    bindLocalPosition: SIMD3<Float> = .zero,
                    bindLocalRotation: SIMD4<Float> = TransformMath.identityQuaternion,
                    bindLocalScale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0),
                    inverseBindGlobalMatrix: simd_float4x4? = nil) {
            self.name = name
            self.parentIndex = parentIndex
            self.bindLocalPosition = bindLocalPosition
            self.bindLocalRotation = TransformMath.normalizedQuaternion(bindLocalRotation)
            self.bindLocalScale = bindLocalScale
            self.inverseBindGlobalMatrix = inverseBindGlobalMatrix
        }
    }

    public var handle: SkeletonHandle
    public var name: String
    public var sourcePath: String
    public var boneCount: Int
    public var joints: [Joint]

    public init(handle: SkeletonHandle,
                name: String,
                sourcePath: String,
                boneCount: Int = 0,
                joints: [Joint] = []) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.joints = joints
        self.boneCount = joints.isEmpty ? boneCount : joints.count
    }
}

public struct AnimationClipAsset {
    public struct TranslationKeyframe {
        public var time: Float
        public var value: SIMD3<Float>

        public init(time: Float, value: SIMD3<Float>) {
            self.time = time
            self.value = value
        }
    }

    public struct RotationKeyframe {
        public var time: Float
        public var value: SIMD4<Float>

        public init(time: Float, value: SIMD4<Float>) {
            self.time = time
            self.value = TransformMath.normalizedQuaternion(value)
        }
    }

    public struct ScaleKeyframe {
        public var time: Float
        public var value: SIMD3<Float>

        public init(time: Float, value: SIMD3<Float>) {
            self.time = time
            self.value = value
        }
    }

    public struct JointTrack {
        public var jointIndex: Int
        public var translations: [TranslationKeyframe]
        public var rotations: [RotationKeyframe]
        public var scales: [ScaleKeyframe]

        public init(jointIndex: Int,
                    translations: [TranslationKeyframe] = [],
                    rotations: [RotationKeyframe] = [],
                    scales: [ScaleKeyframe] = []) {
            self.jointIndex = jointIndex
            self.translations = translations.sorted { $0.time < $1.time }
            self.rotations = rotations.sorted { $0.time < $1.time }
            self.scales = scales.sorted { $0.time < $1.time }
        }
    }

    public var handle: AnimationClipHandle
    public var name: String
    public var sourcePath: String
    public var durationSeconds: Float
    public var tracks: [JointTrack]

    public init(handle: AnimationClipHandle,
                name: String,
                sourcePath: String,
                durationSeconds: Float = 0.0,
                tracks: [JointTrack] = []) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
        self.tracks = tracks
    }
}

public struct AudioAsset {
    public var handle: AudioHandle
    public var name: String
    public var sourcePath: String
    public var durationSeconds: Float

    public init(handle: AudioHandle,
                name: String,
                sourcePath: String,
                durationSeconds: Float = 0.0) {
        self.handle = handle
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
    }
}

public struct AssetMetadata: Codable {
    public var handle: AssetHandle
    public var type: AssetType
    public var sourcePath: String
    public var importSettings: [String: String]
    public var scriptLanguage: String?
    public var entryTypeName: String?
    public var dependencies: [AssetHandle]
    public var lastModified: TimeInterval

    public init(handle: AssetHandle,
                type: AssetType,
                sourcePath: String,
                importSettings: [String: String] = [:],
                scriptLanguage: String? = nil,
                entryTypeName: String? = nil,
                dependencies: [AssetHandle] = [],
                lastModified: TimeInterval = 0) {
        self.handle = handle
        self.type = type
        self.sourcePath = sourcePath
        self.importSettings = importSettings
        self.scriptLanguage = scriptLanguage
        self.entryTypeName = entryTypeName
        self.dependencies = dependencies
        self.lastModified = lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(AssetHandle.self, forKey: .handle)
        type = try container.decode(AssetType.self, forKey: .type)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        importSettings = try container.decodeIfPresent([String: String].self, forKey: .importSettings) ?? [:]
        scriptLanguage = try container.decodeIfPresent(String.self, forKey: .scriptLanguage)
        entryTypeName = try container.decodeIfPresent(String.self, forKey: .entryTypeName)
        dependencies = try container.decodeIfPresent([AssetHandle].self, forKey: .dependencies) ?? []
        lastModified = try container.decodeIfPresent(TimeInterval.self, forKey: .lastModified) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(type, forKey: .type)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(importSettings, forKey: .importSettings)
        try container.encodeIfPresent(scriptLanguage, forKey: .scriptLanguage)
        try container.encodeIfPresent(entryTypeName, forKey: .entryTypeName)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(lastModified, forKey: .lastModified)
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case type
        case sourcePath
        case importSettings
        case scriptLanguage
        case entryTypeName
        case dependencies
        case lastModified
    }
}
