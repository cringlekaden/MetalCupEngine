//
//  MetalTypes.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

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
    public var cameraPosition = SIMD3<Float>(0,0,0)
}

public struct MetalCupMaterial: sizeable {
    public var baseColor = SIMD3<Float>(1.0, 1.0, 1.0)
    public var metallicScalar: Float = 1.0
    public var roughnessScalar: Float = 1.0
    public var aoScalar: Float = 1.0
    public var emissiveColor = SIMD3<Float>(1.0, 1.0, 1.0)
    public var emissiveScalar: Float = 10.0
    public var flags: UInt32 = 0
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
}

public struct LightData: sizeable {
    public var position: SIMD3<Float> = .zero
    public var color: SIMD3<Float> = .one
    public var brightness: Float = 1.0
    public var ambientIntensity: Float = 1.0
    public var diffuseIntensity: Float = 1.0
    public var specularIntensity: Float = 1.0
}

public struct BloomParams: sizeable {
    public var threshold: Float = 1.2
    public var knee: Float = 0.2
    public var intensity: Float = 0.15
    public var texelSize: SIMD2<Float> = .zero
    public var padding: SIMD2<Float> = .zero
};
