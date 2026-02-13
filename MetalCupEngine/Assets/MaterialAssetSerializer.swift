/// MaterialAssetSerializer.swift
/// Defines the MaterialAssetSerializer types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public struct MaterialAssetDocument: Codable {
    public var schemaVersion: Int
    public var id: String?
    public var name: String?
    public var version: Int?

    public var baseColorFactor: Vector3DTO?
    public var metallicFactor: Float?
    public var roughnessFactor: Float?
    public var aoFactor: Float?
    public var emissiveColor: Vector3DTO?
    public var emissiveIntensity: Float?

    public var alphaMode: MaterialAlphaMode?
    public var alphaCutoff: Float?
    public var doubleSided: Bool?
    public var unlit: Bool?

    public var textures: MaterialTextureSlots?

    public init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
    }
}

public enum MaterialAssetSerializer {
    public static func load(from url: URL, fallbackHandle: AssetHandle?) -> MaterialAsset? {
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(MaterialAssetDocument.self, from: data)
            return material(from: document, url: url, fallbackHandle: fallbackHandle)
        } catch {
            print("WARN::MATERIAL::LOAD::__\(url.lastPathComponent)__::\(error)")
            let fallbackHandle = fallbackHandle ?? AssetHandle()
            let name = url.deletingPathExtension().lastPathComponent
            return MaterialAsset.default(handle: fallbackHandle, name: name)
        }
    }

    public static func save(_ asset: MaterialAsset, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = document(from: asset)
        do {
            let data = try encoder.encode(document)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            print("WARN::MATERIAL::SAVE::__\(url.lastPathComponent)__::\(error)")
            return false
        }
    }

    private static func material(from document: MaterialAssetDocument, url: URL, fallbackHandle: AssetHandle?) -> MaterialAsset {
        let resolvedHandle: AssetHandle
        if let id = document.id, let uuid = UUID(uuidString: id) {
            resolvedHandle = AssetHandle(rawValue: uuid)
        } else {
            resolvedHandle = fallbackHandle ?? AssetHandle()
        }

        var textures = document.textures ?? MaterialTextureSlots()
        textures.enforceMetalRoughnessRule()

        let name = document.name ?? url.deletingPathExtension().lastPathComponent
        let baseColor = document.baseColorFactor?.toSIMD() ?? SIMD3<Float>(1.0, 1.0, 1.0)
        let emissiveColor = document.emissiveColor?.toSIMD() ?? SIMD3<Float>(0.0, 0.0, 0.0)

        return MaterialAsset(
            handle: fallbackHandle ?? resolvedHandle,
            name: name,
            version: document.version ?? 1,
            baseColorFactor: baseColor,
            metallicFactor: document.metallicFactor ?? 1.0,
            roughnessFactor: document.roughnessFactor ?? 1.0,
            aoFactor: document.aoFactor ?? 1.0,
            emissiveColor: emissiveColor,
            emissiveIntensity: document.emissiveIntensity ?? 1.0,
            alphaMode: document.alphaMode ?? .opaque,
            alphaCutoff: document.alphaCutoff ?? 0.5,
            doubleSided: document.doubleSided ?? false,
            unlit: document.unlit ?? false,
            textures: textures
        )
    }

    private static func document(from asset: MaterialAsset) -> MaterialAssetDocument {
        var document = MaterialAssetDocument(schemaVersion: 1)
        document.id = asset.handle.rawValue.uuidString
        document.name = asset.name
        document.version = asset.version
        document.baseColorFactor = Vector3DTO(asset.baseColorFactor)
        document.metallicFactor = asset.metallicFactor
        document.roughnessFactor = asset.roughnessFactor
        document.aoFactor = asset.aoFactor
        document.emissiveColor = Vector3DTO(asset.emissiveColor)
        document.emissiveIntensity = asset.emissiveIntensity
        document.alphaMode = asset.alphaMode
        document.alphaCutoff = asset.alphaCutoff
        document.doubleSided = asset.doubleSided
        document.unlit = asset.unlit
        document.textures = asset.textures
        return document
    }
}
