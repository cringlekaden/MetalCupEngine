/// MetalTypes.swift
/// Defines the MetalTypes types and helpers for the engine.
/// Created by Kaden Cringle.

import simd

public protocol sizeable {}

extension sizeable {
    
    static var size: Int {
        return MemoryLayout<Self>.size
    }
    
    static var stride: Int {
        return MemoryLayout<Self>.stride
    }
    
    static func size(_ count: Int)->Int {
        return MemoryLayout<Self>.size * count
    }
    
    static func stride(_ count: Int)->Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension UInt32: sizeable {}
extension Int32: sizeable {}
extension Float: sizeable {}
extension SIMD2<Float>: sizeable {}
extension SIMD3<Float>: sizeable {}
extension SIMD4<Float>: sizeable {}

public enum VertexBufferIndex {
    public static let vertices = 0
    public static let sceneConstants = 1
    public static let modelConstants = 2
    public static let cubemapViewProjection = 1
}

public enum FragmentBufferIndex {
    public static let material = 1
    public static let rendererSettings = 2
    public static let lightCount = 3
    public static let lightData = 4
    public static let iblParams = 0
    public static let skyParams = 0
    public static let skyIntensity = 0
}

public enum FragmentTextureIndex {
    public static let albedo = 0
    public static let normal = 1
    public static let metallic = 2
    public static let roughness = 3
    public static let metalRoughness = 4
    public static let ao = 5
    public static let emissive = 6
    public static let irradiance = 7
    public static let prefiltered = 8
    public static let brdfLut = 9
    public static let clearcoat = 10
    public static let clearcoatRoughness = 11
    public static let sheenColor = 12
    public static let sheenIntensity = 13
    public static let skybox = 14
}

public enum FragmentSamplerIndex {
    public static let linear = 0
    public static let linearClamp = 1
}

public enum PostProcessTextureIndex {
    public static let source = 0
    public static let bloom = 1
}

public enum IBLTextureIndex {
    public static let environment = 0
}

public struct Vertex: sizeable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var texCoord: SIMD2<Float>
    public var normal: SIMD3<Float>
    public var tangent: SIMD3<Float>
    public var bitangent: SIMD3<Float>
}

public struct SimpleVertex: sizeable {
    public var position: SIMD3<Float>
}

public struct ModelConstants: sizeable {
    public var modelMatrix = matrix_identity_float4x4
}

public struct SceneConstants: sizeable {
    public var totalGameTime = Float(0)
    public var viewMatrix = matrix_identity_float4x4
    public var skyViewMatrix = matrix_identity_float4x4
    public var projectionMatrix = matrix_identity_float4x4
    public var cameraPositionAndIBL = SIMD4<Float>(0, 0, 0, 1)
}

public struct MetalCupMaterial: sizeable {
    public var baseColor = SIMD3<Float>(1.0, 1.0, 1.0)
    public var metallicScalar: Float = 1.0
    public var roughnessScalar: Float = 1.0
    public var aoScalar: Float = 1.0
    public var emissiveColor = SIMD3<Float>(0.0, 0.0, 0.0)
    public var emissiveScalar: Float = 1.0
    public var alphaCutoff: Float = 0.5
    public var flags: UInt32 = 0
    public var clearcoatFactor: Float = 0.0
    public var clearcoatRoughness: Float = 0.1
    public var sheenRoughness: Float = 0.3
    public var padding: Float = 0.0
    public var sheenColor = SIMD3<Float>(0.0, 0.0, 0.0)
    public var padding2: Float = 0.0
}

public struct MetalCupMaterialFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let hasBaseColorMap =      MetalCupMaterialFlags(rawValue: 1 << 0)
    public static let hasNormalMap =         MetalCupMaterialFlags(rawValue: 1 << 1)
    public static let hasMetallicMap =       MetalCupMaterialFlags(rawValue: 1 << 2)
    public static let hasRoughnessMap =      MetalCupMaterialFlags(rawValue: 1 << 3)
    public static let hasMetalRoughnessMap = MetalCupMaterialFlags(rawValue: 1 << 4)
    public static let hasAOMap =             MetalCupMaterialFlags(rawValue: 1 << 5)
    public static let hasEmissiveMap =       MetalCupMaterialFlags(rawValue: 1 << 6)
    public static let isUnlit =              MetalCupMaterialFlags(rawValue: 1 << 7)
    public static let isDoubleSided =        MetalCupMaterialFlags(rawValue: 1 << 8)
    public static let alphaMasked =          MetalCupMaterialFlags(rawValue: 1 << 9)
    public static let alphaBlended =         MetalCupMaterialFlags(rawValue: 1 << 10)
    public static let hasClearcoat =         MetalCupMaterialFlags(rawValue: 1 << 11)
    public static let hasSheen =             MetalCupMaterialFlags(rawValue: 1 << 12)
    public static let normalFlipY =          MetalCupMaterialFlags(rawValue: 1 << 13)
    public static let hasClearcoatMap =      MetalCupMaterialFlags(rawValue: 1 << 14)
    public static let hasClearcoatRoughnessMap = MetalCupMaterialFlags(rawValue: 1 << 15)
    public static let hasSheenColorMap =     MetalCupMaterialFlags(rawValue: 1 << 16)
    public static let hasSheenIntensityMap = MetalCupMaterialFlags(rawValue: 1 << 17)
    public static let hasClearcoatGlossMap = MetalCupMaterialFlags(rawValue: 1 << 18)
}

public struct LightData: sizeable {
    public var position: SIMD3<Float> = .zero
    public var type: UInt32 = 0
    public var direction: SIMD3<Float> = SIMD3<Float>(0, -1, 0)
    public var range: Float = 0.0
    public var color: SIMD3<Float> = .one
    public var brightness: Float = 1.0
    public var ambientIntensity: Float = 1.0
    public var diffuseIntensity: Float = 1.0
    public var specularIntensity: Float = 1.0
    public var innerConeCos: Float = 0.95
    public var outerConeCos: Float = 0.9
    public var padding: SIMD2<Float> = .zero

    public init() {}
}

public struct IBLIrradianceParams: sizeable {
    public var sampleCount: UInt32 = 2048
    public var fireflyClamp: Float = 100.0
    public var fireflyClampEnabled: UInt32 = 1
    public var padding: Float = 0.0
}

public struct IBLPrefilterParams: sizeable {
    public var roughness: Float = 0.0
    public var sampleCount: UInt32 = 1024
    public var fireflyClamp: Float = 100.0
    public var fireflyClampEnabled: UInt32 = 1
    public var envMipCount: Float = 1.0
    public var padding: Float = 0.0
}

public struct SkyParams: sizeable {
    public var sunDirection = SIMD3<Float>(0, 1, 0)
    public var sunAngularRadius: Float = 0.00935
    public var sunColor = SIMD3<Float>(1, 1, 1)
    public var sunIntensity: Float = 5.0
    public var turbidity: Float = 2.0
    public var intensity: Float = 1.0
    public var skyTint: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    public var padding: Float = 0.0
}

public typealias SkyUniforms = SkyParams
