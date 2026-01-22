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
}

struct ModelConstants: sizeable {
    var modelMatrix = matrix_identity_float4x4
}

struct SceneConstants: sizeable {
    var totalGameTime = Float(0)
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var cameraPosition = SIMD3<Float>(0,0,0)
}

struct Material: sizeable {
    var color = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
    var useMaterialColor: Bool = false
    var useTexture: Bool = false
    var isLit: Bool = true
    var ambient: SIMD3<Float> = SIMD3<Float>(0.1,0.1,0.1)
    var diffuse: SIMD3<Float> = .one
    var specular: SIMD3<Float> = .one
    var shininess: Float = 32.0
}

struct LightData: sizeable {
    var position: SIMD3<Float> = .zero
    var color: SIMD3<Float> = .one
    var brightness: Float = 1.0
    var ambientIntensity: Float = 1.0
    var diffuseIntensity: Float = 1.0
    var specularIntensity: Float = 1.0
}
