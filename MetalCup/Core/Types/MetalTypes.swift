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
        self.init(columns: (
            SIMD4<Float>( xScale, 0,      0,  0),
            SIMD4<Float>( 0,      yScale, 0,  0),
            SIMD4<Float>( 0,      0,      zScale, -1),
            SIMD4<Float>( 0,      0,      wzScale,  0)
        ))
    }
    
    init(lookAt eye: SIMD3<Float>,
         center: SIMD3<Float>,
         up: SIMD3<Float>) {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        self.init(columns: (
            SIMD4<Float>( s.x,  u.x, -f.x, 0),
            SIMD4<Float>( s.y,  u.y, -f.y, 0),
            SIMD4<Float>( s.z,  u.z, -f.z, 0),
            SIMD4<Float>(-dot(s, eye),
                          -dot(u, eye),
                           dot(f, eye),
                           1)
        ))
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

struct Material: sizeable {
    var color = SIMD4<Float>(0.3, 0.3, 0.3, 1.0)
    var isLit: Bool = true
    var ambient: SIMD3<Float> = SIMD3<Float>(0.1,0.1,0.1)
    var diffuse: SIMD3<Float> = .one
    var specular: SIMD3<Float> = .one
    var shininess: Float = 32.0
}

struct PBRMaterial: sizeable {
    var baseColor = SIMD3<Float>(0.8, 0.8, 0.8)
    var metallic: Float = 0.5
    var roughness: Float = 0.2
    var ao: Float = 0.0
}

struct LightData: sizeable {
    var position: SIMD3<Float> = .zero
    var color: SIMD3<Float> = .one
    var brightness: Float = 1.0
    var ambientIntensity: Float = 1.0
    var diffuseIntensity: Float = 1.0
    var specularIntensity: Float = 1.0
}
