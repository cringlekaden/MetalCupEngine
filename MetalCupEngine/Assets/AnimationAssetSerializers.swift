/// AnimationAssetSerializers.swift
/// Defines skeleton and animation clip serialization helpers.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct Matrix4x4DTO: Codable {
    public var values: [Float]

    public init(_ matrix: simd_float4x4) {
        values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    public func toSIMD() -> simd_float4x4? {
        guard values.count >= 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        )
    }
}

public struct SkeletonAssetDocument: Codable {
    public struct JointDocument: Codable {
        public var name: String
        public var parentIndex: Int
        public var bindLocalPosition: Vector3DTO
        public var bindLocalRotation: Vector4DTO
        public var bindLocalScale: Vector3DTO
        public var inverseBindGlobal: Matrix4x4DTO?
    }

    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var sourcePath: String?
    public var joints: [JointDocument]

    public init(schemaVersion: Int = 1,
                id: String? = nil,
                name: String? = nil,
                sourcePath: String? = nil,
                joints: [JointDocument] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.joints = joints
    }
}

public struct AnimationClipAssetDocument: Codable {
    public struct TranslationKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector3DTO
    }

    public struct RotationKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector4DTO
    }

    public struct ScaleKeyframeDocument: Codable {
        public var time: Float
        public var value: Vector3DTO
    }

    public struct JointTrackDocument: Codable {
        public var jointIndex: Int
        public var translations: [TranslationKeyframeDocument]
        public var rotations: [RotationKeyframeDocument]
        public var scales: [ScaleKeyframeDocument]
    }

    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var sourcePath: String?
    public var durationSeconds: Float
    public var tracks: [JointTrackDocument]

    public init(schemaVersion: Int = 1,
                id: String? = nil,
                name: String? = nil,
                sourcePath: String? = nil,
                durationSeconds: Float = 0,
                tracks: [JointTrackDocument] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.durationSeconds = durationSeconds
        self.tracks = tracks
    }
}

public enum SkeletonAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> SkeletonAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(SkeletonAssetDocument.self, from: data)
            let handle = resolvedHandle(id: document.id, fallback: fallbackHandle)
            let joints = document.joints.map { joint in
                SkeletonAsset.Joint(
                    name: joint.name,
                    parentIndex: joint.parentIndex,
                    bindLocalPosition: joint.bindLocalPosition.toSIMD(),
                    bindLocalRotation: joint.bindLocalRotation.toSIMD(),
                    bindLocalScale: joint.bindLocalScale.toSIMD(),
                    inverseBindGlobalMatrix: joint.inverseBindGlobal?.toSIMD()
                )
            }
            return SkeletonAsset(
                handle: handle,
                name: document.name ?? url.deletingPathExtension().lastPathComponent,
                sourcePath: document.sourcePath ?? url.lastPathComponent,
                joints: joints
            )
        } catch {
            EngineLoggerContext.log(
                "Skeleton load failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return nil
        }
    }

    @discardableResult
    public static func save(_ asset: SkeletonAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = SkeletonAssetDocument(
            schemaVersion: 1,
            id: asset.handle.rawValue.uuidString,
            name: asset.name,
            sourcePath: asset.sourcePath,
            joints: asset.joints.map { joint in
                SkeletonAssetDocument.JointDocument(
                    name: joint.name,
                    parentIndex: joint.parentIndex,
                    bindLocalPosition: Vector3DTO(joint.bindLocalPosition),
                    bindLocalRotation: Vector4DTO(joint.bindLocalRotation),
                    bindLocalScale: Vector3DTO(joint.bindLocalScale),
                    inverseBindGlobal: joint.inverseBindGlobalMatrix.map(Matrix4x4DTO.init)
                )
            }
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EngineLoggerContext.log(
                "Skeleton save failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return false
        }
    }
}

public enum AnimationClipAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> AnimationClipAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(AnimationClipAssetDocument.self, from: data)
            let handle = resolvedHandle(id: document.id, fallback: fallbackHandle)
            let tracks = document.tracks.map { track in
                AnimationClipAsset.JointTrack(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map {
                        AnimationClipAsset.TranslationKeyframe(time: $0.time, value: $0.value.toSIMD())
                    },
                    rotations: track.rotations.map {
                        AnimationClipAsset.RotationKeyframe(time: $0.time, value: $0.value.toSIMD())
                    },
                    scales: track.scales.map {
                        AnimationClipAsset.ScaleKeyframe(time: $0.time, value: $0.value.toSIMD())
                    }
                )
            }
            return AnimationClipAsset(
                handle: handle,
                name: document.name ?? url.deletingPathExtension().lastPathComponent,
                sourcePath: document.sourcePath ?? url.lastPathComponent,
                durationSeconds: document.durationSeconds,
                tracks: tracks
            )
        } catch {
            EngineLoggerContext.log(
                "Animation clip load failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return nil
        }
    }

    @discardableResult
    public static func save(_ asset: AnimationClipAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = AnimationClipAssetDocument(
            schemaVersion: 1,
            id: asset.handle.rawValue.uuidString,
            name: asset.name,
            sourcePath: asset.sourcePath,
            durationSeconds: asset.durationSeconds,
            tracks: asset.tracks.map { track in
                AnimationClipAssetDocument.JointTrackDocument(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map {
                        AnimationClipAssetDocument.TranslationKeyframeDocument(
                            time: $0.time,
                            value: Vector3DTO($0.value)
                        )
                    },
                    rotations: track.rotations.map {
                        AnimationClipAssetDocument.RotationKeyframeDocument(
                            time: $0.time,
                            value: Vector4DTO($0.value)
                        )
                    },
                    scales: track.scales.map {
                        AnimationClipAssetDocument.ScaleKeyframeDocument(
                            time: $0.time,
                            value: Vector3DTO($0.value)
                        )
                    }
                )
            }
        )
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EngineLoggerContext.log(
                "Animation clip save failed \(url.lastPathComponent): \(error)",
                level: .warning,
                category: .assets
            )
            return false
        }
    }
}

private func resolvedHandle(id: String?, fallback: AssetHandle?) -> AssetHandle {
    if let id, let uuid = UUID(uuidString: id) {
        return AssetHandle(rawValue: uuid)
    }
    return fallback ?? AssetHandle()
}
