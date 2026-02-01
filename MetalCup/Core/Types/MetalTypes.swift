//
//  MetalTypes.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import simd

protocol sizeable {}

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

extension float4x4 {
    
    static var identity: float4x4 {
        matrix_identity_float4x4
    }
    
    init(perspectiveFov fovY: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
        self.init(columns: (SIMD4<Float>(xScale, 0, 0, 0), SIMD4<Float>(0, yScale, 0, 0), SIMD4<Float>(0, 0, zScale, -1), SIMD4<Float>(0, 0, wzScale, 0)))
    }
    
    init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        self.init(columns: (SIMD4<Float>( s.x,  u.x, -f.x, 0), SIMD4<Float>( s.y,  u.y, -f.y, 0), SIMD4<Float>( s.z,  u.z, -f.z, 0), SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
    }
}

extension UInt32: sizeable {}
extension Int32: sizeable {}
extension Float: sizeable {}
extension SIMD2<Float>: sizeable {}
extension SIMD3<Float>: sizeable {}
extension SIMD4<Float>: sizeable {}

struct Vertex: sizeable {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var texCoord: SIMD2<Float>
    var normal: SIMD3<Float>
    var tangent: SIMD3<Float>
    var bitangent: SIMD3<Float>
}

struct CubemapVertex: sizeable {
    var position: SIMD3<Float>
}

struct ModelConstants: sizeable {
    var modelMatrix = matrix_identity_float4x4
}

struct SceneConstants: sizeable {
    var totalGameTime = Float(0)
    var viewMatrix = matrix_identity_float4x4
    var skyViewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var cameraPosition = SIMD3<Float>(0,0,0)
}

struct MetalCupMaterial: sizeable {
    var baseColor = SIMD3<Float>(1.0, 1.0, 1.0)
    var metallicScalar: Float = 1.0
    var roughnessScalar: Float = 1.0
    var aoScalar: Float = 1.0
    var emissiveColor = SIMD3<Float>(1.0, 1.0, 1.0)
    var emissiveScalar: Float = 10.0
    var flags: UInt32 = 0
}

struct MetalCupMaterialFlags: OptionSet {
    let rawValue: UInt32
    static let hasBaseColorMap =      MetalCupMaterialFlags(rawValue: 1 << 0)
    static let hasNormalMap =         MetalCupMaterialFlags(rawValue: 1 << 1)
    static let hasMetallicMap =       MetalCupMaterialFlags(rawValue: 1 << 2)
    static let hasRoughnessMap =      MetalCupMaterialFlags(rawValue: 1 << 3)
    static let hasMetalRoughnessMap = MetalCupMaterialFlags(rawValue: 1 << 4)
    static let hasAOMap =             MetalCupMaterialFlags(rawValue: 1 << 5)
    static let hasEmissiveMap =       MetalCupMaterialFlags(rawValue: 1 << 6)
    static let isUnlit =              MetalCupMaterialFlags(rawValue: 1 << 7)
    static let isDoubleSided =        MetalCupMaterialFlags(rawValue: 1 << 8)
    static let alphaMasked =          MetalCupMaterialFlags(rawValue: 1 << 9)
    static let alphaBlended =         MetalCupMaterialFlags(rawValue: 1 << 10)
}

struct LightData: sizeable {
    var position: SIMD3<Float> = .zero
    var color: SIMD3<Float> = .one
    var brightness: Float = 1.0
    var ambientIntensity: Float = 1.0
    var diffuseIntensity: Float = 1.0
    var specularIntensity: Float = 1.0
}

struct BloomParams {
    var threshold: Float = 1.2
    var knee: Float = 0.2
    var intensity: Float = 0.15
    var texelSize: SIMD2<Float> = .zero
    var padding: SIMD2<Float> = .zero
};
