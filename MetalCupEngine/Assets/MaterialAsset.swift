//
//  MaterialAsset.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import Foundation
import simd

public enum MaterialAlphaMode: String, Codable {
    case opaque
    case masked
    case blended
}

public struct MaterialTextureSlots: Codable {
    public var baseColor: AssetHandle?
    public var normal: AssetHandle?
    public var metalRoughness: AssetHandle?
    public var metallic: AssetHandle?
    public var roughness: AssetHandle?
    public var ao: AssetHandle?
    public var emissive: AssetHandle?

    public init(
        baseColor: AssetHandle? = nil,
        normal: AssetHandle? = nil,
        metalRoughness: AssetHandle? = nil,
        metallic: AssetHandle? = nil,
        roughness: AssetHandle? = nil,
        ao: AssetHandle? = nil,
        emissive: AssetHandle? = nil
    ) {
        self.baseColor = baseColor
        self.normal = normal
        self.metalRoughness = metalRoughness
        self.metallic = metallic
        self.roughness = roughness
        self.ao = ao
        self.emissive = emissive
    }

    public mutating func enforceMetalRoughnessRule() {
        if metalRoughness != nil {
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
    public var metallicFactor: Float
    public var roughnessFactor: Float
    public var aoFactor: Float
    public var emissiveColor: SIMD3<Float>
    public var emissiveIntensity: Float

    public var alphaMode: MaterialAlphaMode
    public var alphaCutoff: Float
    public var doubleSided: Bool
    public var unlit: Bool

    public var textures: MaterialTextureSlots

    public init(
        handle: AssetHandle,
        name: String,
        version: Int = 1,
        baseColorFactor: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0),
        metallicFactor: Float = 1.0,
        roughnessFactor: Float = 1.0,
        aoFactor: Float = 1.0,
        emissiveColor: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0),
        emissiveIntensity: Float = 1.0,
        alphaMode: MaterialAlphaMode = .opaque,
        alphaCutoff: Float = 0.5,
        doubleSided: Bool = false,
        unlit: Bool = false,
        textures: MaterialTextureSlots = MaterialTextureSlots()
    ) {
        self.handle = handle
        self.name = name
        self.version = version
        self.baseColorFactor = baseColorFactor
        self.metallicFactor = metallicFactor
        self.roughnessFactor = roughnessFactor
        self.aoFactor = aoFactor
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        self.alphaMode = alphaMode
        self.alphaCutoff = alphaCutoff
        self.doubleSided = doubleSided
        self.unlit = unlit
        self.textures = textures
    }

    public static func `default`(handle: AssetHandle, name: String) -> MaterialAsset {
        MaterialAsset(handle: handle, name: name)
    }

    public func buildMetalMaterial(database: AssetDatabase?) -> MetalCupMaterial {
        var material = MetalCupMaterial()
        material.baseColor = baseColorFactor
        material.metallicScalar = metallicFactor
        material.roughnessScalar = roughnessFactor
        material.aoScalar = aoFactor
        material.emissiveColor = emissiveColor
        material.emissiveScalar = emissiveIntensity
        material.alphaCutoff = alphaCutoff

        var flags = MetalCupMaterialFlags()
        if textures.baseColor != nil { flags.insert(.hasBaseColorMap) }
        if textures.normal != nil { flags.insert(.hasNormalMap) }
        if textures.metalRoughness != nil {
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
           let metadata = database?.metadata(for: normalHandle),
           AssetManager.shouldFlipNormalY(path: metadata.sourcePath) {
            flags.insert(.normalFlipY)
        }

        material.flags = flags.rawValue
        return material
    }
}
