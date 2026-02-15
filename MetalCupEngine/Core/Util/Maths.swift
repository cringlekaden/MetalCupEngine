/// Maths.swift
/// Defines the Maths types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public var xAxis:  SIMD3<Float> {
    .init(1, 0, 0)
}

public var yAxis:  SIMD3<Float> {
    .init(0, 1, 0)
}

public var zAxis:  SIMD3<Float> {
    .init(0, 0, 1)
}

extension Float {
    var toRadians: Float {
        return (self / 180.0) * Float.pi
    }
    var toDegrees: Float {
        return self * (180.0 / Float.pi)
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

extension matrix_float4x4 {
    mutating func translate(direction: SIMD3<Float>) {
        var result = matrix_identity_float4x4
        result.columns = (
            SIMD4<Float>(1,0,0,0),
            SIMD4<Float>(0,1,0,0),
            SIMD4<Float>(0,0,1,0),
            SIMD4<Float>(direction.x,direction.y,direction.z,1)
        )
        self = matrix_multiply(self, result)
    }
    mutating func scale(axis: SIMD3<Float>) {
        var result = matrix_identity_float4x4
        result.columns = (
            SIMD4<Float>(axis.x,0,0,0),
            SIMD4<Float>(0,axis.y,0,0),
            SIMD4<Float>(0,0,axis.z,0),
            SIMD4<Float>(0,0,0,1)
        )
        self = matrix_multiply(self, result)
    }
    mutating func rotate(angle: Float, axis: SIMD3<Float>) {
        var result = matrix_identity_float4x4
        let x = axis.x
        let y = axis.y
        let z = axis.z
        let c = cos(angle)
        let s = sin(angle)
        let mc = 1 - c
        let r1c1 = x * x * mc + c
        let r2c1 = y * x * mc + z * s
        let r3c1 = z * x * mc - y * s
        let r4c1: Float = 0.0
        let r1c2 = x * y * mc - z * s
        let r2c2 = y * y * mc + c
        let r3c2 = z * y * mc + x * s
        let r4c2: Float = 0.0
        let r1c3 = x * z * mc + y * s
        let r2c3 = y * z * mc - x * s
        let r3c3 = z * z * mc + c
        let r4c3: Float = 0.0
        let r1c4: Float = 0.0
        let r2c4: Float = 0.0
        let r3c4: Float = 0.0
        let r4c4: Float = 1.0
        result.columns = (
                SIMD4<Float>(r1c1,r2c1,r3c1,r4c1),
                SIMD4<Float>(r1c2,r2c2,r3c2,r4c2),
                SIMD4<Float>(r1c3,r2c3,r3c3,r4c3),
                SIMD4<Float>(r1c4,r2c4,r3c4,r4c4)
        )
        self = matrix_multiply(self, result)
    }
    static func perspective(fovDegrees: Float, aspectRatio: Float, near: Float, far: Float)->matrix_float4x4 {
        let fov = fovDegrees.toRadians
        let t: Float = tan(fov / 2)
        let x: Float = 1 / (aspectRatio * t)
        let y: Float = 1 / t
        let z: Float = -((far + near) / (far - near))
        let w: Float = -((2 * far * near) / (far - near))
        var result = matrix_identity_float4x4
        result.columns = (
            .init(x,0,0,0),
            .init(0,y,0,0),
            .init(0,0,z,-1),
            .init(0,0,w,0)
        )
        return result
    }

    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let rl = right - left
        let tb = top - bottom
        let fn = far - near
        var result = matrix_identity_float4x4
        result.columns = (
            .init(2.0 / rl, 0, 0, 0),
            .init(0, 2.0 / tb, 0, 0),
            .init(0, 0, -2.0 / fn, 0),
            .init(-(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn, 1.0)
        )
        return result
    }

    static func orthographic(size: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
        let halfHeight = size * 0.5
        let halfWidth = halfHeight * aspectRatio
        return orthographic(
            left: -halfWidth,
            right: halfWidth,
            bottom: -halfHeight,
            top: halfHeight,
            near: near,
            far: far
        )
    }
}
