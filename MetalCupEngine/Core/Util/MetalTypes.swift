/// MetalTypes.swift
/// Shared Metal data types and Swift-side shader bindings.
/// Created by Kaden Cringle

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
    public static let vertices = ShaderBindings.VertexBuffer.vertices
    public static let sceneConstants = ShaderBindings.VertexBuffer.sceneConstants
    public static let modelConstants = ShaderBindings.VertexBuffer.modelConstants
    public static let instances = ShaderBindings.VertexBuffer.instances
    public static let cubemapViewProjection = ShaderBindings.VertexBuffer.cubemapViewProjection
}

public enum FragmentBufferIndex {
    public static let material = ShaderBindings.FragmentBuffer.material
    public static let rendererSettings = ShaderBindings.FragmentBuffer.rendererSettings
    public static let lightCount = ShaderBindings.FragmentBuffer.lightCount
    public static let lightData = ShaderBindings.FragmentBuffer.lightData
    public static let iblParams = ShaderBindings.FragmentBuffer.iblParams
    public static let skyParams = ShaderBindings.FragmentBuffer.skyParams
    public static let skyIntensity = ShaderBindings.FragmentBuffer.skyIntensity
    public static let outlineParams = ShaderBindings.FragmentBuffer.outlineParams
    public static let gridParams = ShaderBindings.FragmentBuffer.gridParams
    public static let shadowConstants = ShaderBindings.FragmentBuffer.shadowConstants
    public static let lightGrid = ShaderBindings.FragmentBuffer.lightGrid
    public static let lightIndexList = ShaderBindings.FragmentBuffer.lightIndexList
    public static let lightIndexCount = ShaderBindings.FragmentBuffer.lightIndexCount
    public static let lightClusterParams = ShaderBindings.FragmentBuffer.lightClusterParams
}

public enum FragmentTextureIndex {
    public static let albedo = ShaderBindings.FragmentTexture.albedo
    public static let normal = ShaderBindings.FragmentTexture.normal
    public static let metallic = ShaderBindings.FragmentTexture.metallic
    public static let roughness = ShaderBindings.FragmentTexture.roughness
    public static let metalRoughness = ShaderBindings.FragmentTexture.metalRoughness
    public static let ao = ShaderBindings.FragmentTexture.ao
    public static let emissive = ShaderBindings.FragmentTexture.emissive
    public static let irradiance = ShaderBindings.FragmentTexture.irradiance
    public static let prefiltered = ShaderBindings.FragmentTexture.prefiltered
    public static let brdfLut = ShaderBindings.FragmentTexture.brdfLut
    public static let clearcoat = ShaderBindings.FragmentTexture.clearcoat
    public static let clearcoatRoughness = ShaderBindings.FragmentTexture.clearcoatRoughness
    public static let sheenColor = ShaderBindings.FragmentTexture.sheenColor
    public static let sheenIntensity = ShaderBindings.FragmentTexture.sheenIntensity
    public static let skybox = ShaderBindings.FragmentTexture.skybox
    public static let shadowMap = ShaderBindings.FragmentTexture.shadowMap
    public static let shadowMapSample = ShaderBindings.FragmentTexture.shadowMapSample
    public static let orm = ShaderBindings.FragmentTexture.orm
}

public enum FragmentSamplerIndex {
    public static let linear = ShaderBindings.FragmentSampler.linear
    public static let linearClamp = ShaderBindings.FragmentSampler.linearClamp
    public static let shadowCompare = ShaderBindings.FragmentSampler.shadowCompare
    public static let shadowDepth = ShaderBindings.FragmentSampler.shadowDepth
}

public enum PostProcessTextureIndex {
    public static let source = ShaderBindings.PostProcessTexture.source
    public static let bloom = ShaderBindings.PostProcessTexture.bloom
    public static let outlineMask = ShaderBindings.PostProcessTexture.outlineMask
    public static let depth = ShaderBindings.PostProcessTexture.depth
    public static let grid = ShaderBindings.PostProcessTexture.grid
}

public enum IBLTextureIndex {
    public static let environment = ShaderBindings.IBLTexture.environment
}

// TBN invariants:
// - normal is object space, transformed by normalMatrix in the vertex shader.
// - tangent.xyz is object space, tangent.w is handedness (+1/-1).
// - bitangent is derived in shader: cross(N, T) * handedness.
// - normal maps assume +Y up unless NormalFlipY is set in material flags.
public struct Vertex: sizeable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var texCoord: SIMD2<Float>
    public var normal: SIMD3<Float>
    public var tangent: SIMD4<Float>
}

public struct SimpleVertex: sizeable {
    public var position: SIMD3<Float>
}

public struct DebugLineVertex: sizeable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var uv: SIMD2<Float>
}

public struct ModelConstants: sizeable {
    public var modelMatrix = matrix_identity_float4x4
}

public struct InstanceData: sizeable {
    public static let expectedMetalStride: Int = 96
    public var modelMatrix = matrix_identity_float4x4
    public var entityID: UInt32 = 0
    public var padding = SIMD4<UInt32>(repeating: 0)
}

public struct SceneConstants: sizeable {
    public var totalGameTime = Float(0)
    public var viewMatrix = matrix_identity_float4x4
    public var skyViewMatrix = matrix_identity_float4x4
    public var projectionMatrix = matrix_identity_float4x4
    public var inverseProjectionMatrix = matrix_identity_float4x4
    public var cameraPositionAndIBL = SIMD4<Float>(0, 0, 0, 1)

    public static let expectedMetalStride = 16
        + (MemoryLayout<matrix_float4x4>.stride * 4)
        + MemoryLayout<SIMD4<Float>>.stride
}

public struct MetalCupMaterial: sizeable {
    public static let expectedMetalStride: Int = 144

    public var baseColor = SIMD3<Float>(0.8, 0.8, 0.8)
    public var baseColorAlpha: Float = 1.0
    public var metallicScalar: Float = 0.0
    public var roughnessScalar: Float = 0.8
    public var aoScalar: Float = 1.0
    public var emissiveColor = SIMD3<Float>(0.0, 0.0, 0.0)
    public var emissiveScalar: Float = 1.0
    public var alphaCutoff: Float = 0.5
    public var flags: UInt32 = 0
    public var clearcoatFactor: Float = 0.0
    public var clearcoatRoughness: Float = 0.1
    public var sheenRoughness: Float = 0.3
    public var pbrMaskMode: UInt32 = 0
    public var aoChannel: UInt32 = 0
    public var roughnessChannel: UInt32 = 1
    public var metallicChannel: UInt32 = 2
    public var sheenColor = SIMD3<Float>(0.0, 0.0, 0.0)
    public var padding2: Float = 0.0
    public var uvTiling = SIMD2<Float>(1.0, 1.0)
    public var uvOffset = SIMD2<Float>(0.0, 0.0)
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
    public static let usesFallbackMaterial = MetalCupMaterialFlags(rawValue: 1 << 19)
    public static let hasORMMap =            MetalCupMaterialFlags(rawValue: 1 << 20)
}

public struct LightData: sizeable {
    public var position: SIMD3<Float> = .zero
    public var type: UInt32 = 0
    /// Direction the light rays travel (from the light toward the scene).
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

public struct ForwardPlusClusterParams: sizeable {
    public static let abiVersion: UInt32 = 1
    public static let expectedMetalStride: Int = 32
    public static let expectedMetalAlignment: Int = 16

    /// header: x=abiVersion, y=zSliceCount, z=tileCountX, w=tileCountY
    public var header = SIMD4<UInt32>(ForwardPlusClusterParams.abiVersion, 1, 0, 0)
    /// tileAndViewport: x=tileSizeX, y=tileSizeY, z=viewportX, w=viewportY
    public var tileAndViewport = SIMD4<UInt32>(16, 16, 0, 0)
}

public struct ForwardPlusIndexHeader: sizeable {
    public static let abiVersion: UInt32 = 1
    public static let expectedMetalStride: Int = 16
    public static let expectedMetalAlignment: Int = 4

    /// Scalar fields keep atomic targets addressable in MSL.
    public var abiVersion: UInt32 = ForwardPlusIndexHeader.abiVersion
    public var totalIndexCount: UInt32 = 0
    public var overflowClusterCount: UInt32 = 0
    public var maxIndexCapacity: UInt32 = 0
}

public struct ForwardPlusCullLight: sizeable {
    public static let expectedMetalStride: Int = 64
    public static let expectedMetalAlignment: Int = 16

    // positionAndRange: xyz = world position, w = range
    public var positionAndRange = SIMD4<Float>(0, 0, 0, 0)
    // directionAndType: xyz = world direction, w = LightType raw value
    public var directionAndType = SIMD4<Float>(0, -1, 0, 0)
    // colorAndIntensity: rgb = color, w = brightness scalar
    public var colorAndIntensity = SIMD4<Float>(1, 1, 1, 1)
    // spotParams: x = innerConeCos, y = outerConeCos, z/w reserved
    public var spotParams = SIMD4<Float>(1, 1, 0, 0)
}

public struct ForwardPlusCullUniforms: sizeable {
    public static let expectedMetalStride: Int = 160
    public static let expectedMetalAlignment: Int = 16

    public var viewMatrix = matrix_identity_float4x4
    public var projectionMatrix = matrix_identity_float4x4
    // x = viewportWidth, y = viewportHeight, z = lightCount, w = maxLightsPerCluster
    public var params0 = SIMD4<UInt32>(0, 0, 0, 0)
    // x = tileCountX, y = tileCountY, z = indexCapacity, w = reserved
    public var params1 = SIMD4<UInt32>(0, 0, 0, 0)
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
    public var skyTime: Float = 0.0
    public var skyTint: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    public var zenithTint: SIMD3<Float> = SIMD3<Float>(0.24, 0.45, 0.95)
    public var horizonTint: SIMD3<Float> = SIMD3<Float>(0.95, 0.75, 0.55)
    public var gradientStrength: Float = 1.0
    public var hazeDensity: Float = 0.35
    public var hazeFalloff: Float = 2.2
    public var hazeHeight: Float = 0.0
    public var ozoneStrength: Float = 0.35
    public var ozoneTint: SIMD3<Float> = SIMD3<Float>(0.55, 0.7, 1.0)
    public var sunHaloSize: Float = 2.5
    public var sunHaloIntensity: Float = 0.5
    public var sunHaloSoftness: Float = 1.2
    public var cloudsEnabled: UInt32 = 0
    public var cloudsCoverage: Float = 0.35
    public var cloudsSoftness: Float = 0.6
    public var cloudsScale: Float = 1.0
    public var cloudsSpeed: Float = 0.02
    public var cloudsWindDirection: SIMD2<Float> = SIMD2<Float>(1.0, 0.0)
    public var cloudsHeight: Float = 0.25
    public var cloudsThickness: Float = 0.35
    public var cloudsBrightness: Float = 1.0
    public var cloudsSunInfluence: Float = 1.0
    public var padding: SIMD2<Float> = .zero
}

public typealias SkyUniforms = SkyParams

public struct OutlineParams: sizeable {
    public var selectedId: UInt32 = 0
    public var thickness: UInt32 = 1
    public var padding = SIMD2<UInt32>(repeating: 0)
    public var texelSize = SIMD2<Float>(0, 0)
}

public struct GridParams: sizeable {
    public var inverseViewProjection = matrix_identity_float4x4
    public var cameraPosition = SIMD3<Float>(0, 0, 0)
    public var padding: Float = 0.0
}

public struct ShadowConstants: sizeable {
    public var lightViewProj0 = matrix_identity_float4x4
    public var lightViewProj1 = matrix_identity_float4x4
    public var lightViewProj2 = matrix_identity_float4x4
    public var lightViewProj3 = matrix_identity_float4x4
    public var cascadeSplits = SIMD4<Float>(repeating: 0)
    public var shadowCasterDirectionAndEnabled = SIMD4<Float>(0, -1, 0, 0)
    public var shadowMapInvSizeAndCount = SIMD4<Float>(0, 0, 0, 0)
    public var cascadeWorldUnitsPerTexel = SIMD4<Float>(repeating: 0)
    public var cascadeNearZ = SIMD4<Float>(repeating: 0)
    public var cascadeFarZ = SIMD4<Float>(repeating: 0)
    public var shadowBiasParams = SIMD4<Float>(0, 0, 1.0, 0)
    public var shadowFadeParams = SIMD4<Float>(0, 0, 0, 0)
    public var pcssParams0 = SIMD4<Float>(1.0, 1.0, 8.0, 4.0)
    public var pcssParams1 = SIMD4<Float>(12.0, 16.0, 1.0, 0.0)
    public var pcfTapCounts = SIMD4<Float>(16.0, 9.0, 9.0, 4.0)

    public var shadowCasterDirection: SIMD3<Float> {
        get { SIMD3<Float>(shadowCasterDirectionAndEnabled.x, shadowCasterDirectionAndEnabled.y, shadowCasterDirectionAndEnabled.z) }
        set { shadowCasterDirectionAndEnabled = SIMD4<Float>(newValue, shadowCasterDirectionAndEnabled.w) }
    }

    public var shadowEnabled: Float {
        get { shadowCasterDirectionAndEnabled.w }
        set { shadowCasterDirectionAndEnabled.w = newValue }
    }

    public var shadowMapInvSize: SIMD2<Float> {
        get { SIMD2<Float>(shadowMapInvSizeAndCount.x, shadowMapInvSizeAndCount.y) }
        set { shadowMapInvSizeAndCount.x = newValue.x; shadowMapInvSizeAndCount.y = newValue.y }
    }

    public var cascadeCount: UInt32 {
        get { UInt32(max(0.0, shadowMapInvSizeAndCount.z)) }
        set { shadowMapInvSizeAndCount.z = Float(newValue) }
    }

    public var filterMode: UInt32 {
        get { UInt32(max(0.0, shadowMapInvSizeAndCount.w)) }
        set { shadowMapInvSizeAndCount.w = Float(newValue) }
    }

    public var depthBias: Float {
        get { shadowBiasParams.x }
        set { shadowBiasParams.x = newValue }
    }

    public var normalBias: Float {
        get { shadowBiasParams.y }
        set { shadowBiasParams.y = newValue }
    }

    public var pcfRadius: Float {
        get { shadowBiasParams.z }
        set { shadowBiasParams.z = newValue }
    }

    public var maxShadowDistance: Float {
        get { shadowBiasParams.w }
        set { shadowBiasParams.w = newValue }
    }

    public var fadeOutDistance: Float {
        get { shadowFadeParams.x }
        set { shadowFadeParams.x = newValue }
    }

    public mutating func setLightViewProj(_ matrix: matrix_float4x4, index: Int) {
        switch index {
        case 0: lightViewProj0 = matrix
        case 1: lightViewProj1 = matrix
        case 2: lightViewProj2 = matrix
        case 3: lightViewProj3 = matrix
        default: break
        }
    }
}
