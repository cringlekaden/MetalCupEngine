/// MaterialAsset.swift
/// Defines the MaterialAsset types and helpers for the engine.
/// Created by Kaden Cringle.

import Foundation
import simd

public enum MaterialAlphaMode: String, Codable {
    case opaque
    case masked
    case blended
}

public enum PBRMaskMode: String, Codable {
    case separate
    case metallicRoughness
    case orm
}

public struct PBRMaskChannels: Codable {
    public var ao: UInt32
    public var roughness: UInt32
    public var metallic: UInt32

    public init(ao: UInt32 = 0, roughness: UInt32 = 1, metallic: UInt32 = 2) {
        self.ao = ao
        self.roughness = roughness
        self.metallic = metallic
    }
}

public struct MaterialTextureSlots: Codable {
    public var baseColor: AssetHandle?
    public var normal: AssetHandle?
    public var metalRoughness: AssetHandle?
    public var orm: AssetHandle?
    public var metallic: AssetHandle?
    public var roughness: AssetHandle?
    public var ao: AssetHandle?
    public var emissive: AssetHandle?

    public init(
        baseColor: AssetHandle? = nil,
        normal: AssetHandle? = nil,
        metalRoughness: AssetHandle? = nil,
        orm: AssetHandle? = nil,
        metallic: AssetHandle? = nil,
        roughness: AssetHandle? = nil,
        ao: AssetHandle? = nil,
        emissive: AssetHandle? = nil
    ) {
        self.baseColor = baseColor
        self.normal = normal
        self.metalRoughness = metalRoughness
        self.orm = orm
        self.metallic = metallic
        self.roughness = roughness
        self.ao = ao
        self.emissive = emissive
    }

    public mutating func enforceMetalRoughnessRule() {
        if orm != nil {
            metalRoughness = nil
            metallic = nil
            roughness = nil
        } else if metalRoughness != nil {
            metallic = nil
            roughness = nil
        } else if metallic != nil || roughness != nil {
            metalRoughness = nil
        }
    }
}

public struct MaterialAsset {
    public var handle: AssetHandle
    public var name: String
    public var version: Int

    public var baseColorFactor: SIMD3<Float>
    public var baseColorAlpha: Float
    public var metallicFactor: Float
    public var roughnessFactor: Float
    public var aoFactor: Float
    public var emissiveColor: SIMD3<Float>
    public var emissiveIntensity: Float
    public var uvTiling: SIMD2<Float>
    public var uvOffset: SIMD2<Float>

    public var alphaMode: MaterialAlphaMode
    public var alphaCutoff: Float
    public var doubleSided: Bool
    public var unlit: Bool

    public var textures: MaterialTextureSlots
    public var pbrMaskMode: PBRMaskMode
    public var pbrMaskChannels: PBRMaskChannels

    public init(
        handle: AssetHandle,
        name: String,
        version: Int = 1,
        baseColorFactor: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0),
        baseColorAlpha: Float = 1.0,
        metallicFactor: Float = 1.0,
        roughnessFactor: Float = 1.0,
        aoFactor: Float = 1.0,
        emissiveColor: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0),
        emissiveIntensity: Float = 1.0,
        uvTiling: SIMD2<Float> = SIMD2<Float>(1.0, 1.0),
        uvOffset: SIMD2<Float> = SIMD2<Float>(0.0, 0.0),
        alphaMode: MaterialAlphaMode = .opaque,
        alphaCutoff: Float = 0.5,
        doubleSided: Bool = false,
        unlit: Bool = false,
        textures: MaterialTextureSlots = MaterialTextureSlots(),
        pbrMaskMode: PBRMaskMode = .separate,
        pbrMaskChannels: PBRMaskChannels = PBRMaskChannels()
    ) {
        self.handle = handle
        self.name = name
        self.version = version
        self.baseColorFactor = baseColorFactor
        self.baseColorAlpha = baseColorAlpha
        self.metallicFactor = metallicFactor
        self.roughnessFactor = roughnessFactor
        self.aoFactor = aoFactor
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        self.uvTiling = uvTiling
        self.uvOffset = uvOffset
        self.alphaMode = alphaMode
        self.alphaCutoff = alphaCutoff
        self.doubleSided = doubleSided
        self.unlit = unlit
        self.textures = textures
        self.pbrMaskMode = pbrMaskMode
        self.pbrMaskChannels = pbrMaskChannels
    }

    public static func `default`(handle: AssetHandle, name: String) -> MaterialAsset {
        MaterialAsset(handle: handle, name: name)
    }

    public func buildMetalMaterial(database: AssetDatabase?) -> MetalCupMaterial {
        var material = MetalCupMaterial()
        material.baseColor = baseColorFactor
        material.baseColorAlpha = baseColorAlpha
        material.metallicScalar = metallicFactor
        material.roughnessScalar = roughnessFactor
        material.aoScalar = aoFactor
        material.emissiveColor = emissiveColor
        material.emissiveScalar = emissiveIntensity
        material.alphaCutoff = alphaCutoff
        material.uvTiling = uvTiling
        material.uvOffset = uvOffset

        var flags = MetalCupMaterialFlags()
        if textures.baseColor != nil { flags.insert(.hasBaseColorMap) }
        if textures.normal != nil { flags.insert(.hasNormalMap) }
        if textures.orm != nil {
            flags.insert(.hasORMMap)
        } else if textures.metalRoughness != nil {
            flags.insert(.hasMetalRoughnessMap)
        } else {
            if textures.metallic != nil { flags.insert(.hasMetallicMap) }
            if textures.roughness != nil { flags.insert(.hasRoughnessMap) }
        }
        if textures.ao != nil { flags.insert(.hasAOMap) }
        if textures.emissive != nil { flags.insert(.hasEmissiveMap) }
        if unlit { flags.insert(.isUnlit) }
        if doubleSided { flags.insert(.isDoubleSided) }
        switch alphaMode {
        case .opaque:
            break
        case .masked:
            flags.insert(.alphaMasked)
        case .blended:
            flags.insert(.alphaBlended)
        }

        if let normalHandle = textures.normal,
           let metadata = database?.metadata(for: normalHandle) {
            let flipFromImport = metadata.importSettings["flipNormalY"] == "true"
            if flipFromImport || AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
                flags.insert(.normalFlipY)
            }
        }

        switch pbrMaskMode {
        case .separate:
            material.pbrMaskMode = 0
        case .metallicRoughness:
            material.pbrMaskMode = 1
        case .orm:
            material.pbrMaskMode = 2
        }
        material.aoChannel = pbrMaskChannels.ao
        material.roughnessChannel = pbrMaskChannels.roughness
        material.metallicChannel = pbrMaskChannels.metallic
        material.flags = flags.rawValue
        return material
    }
}
