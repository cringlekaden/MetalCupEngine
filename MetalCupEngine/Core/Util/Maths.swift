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

// Transform conventions:
// - Quaternions are stored as (x, y, z, w).
// - Matrices are column-major (simd_float4x4 / Metal float4x4).
// - Vertex shader uses: worldPos = modelMatrix * float4(localPos, 1).
// - View matrix is the inverse of camera world transform.
public enum TransformMath {
    // Quaternion layout is (x, y, z, w) and Euler order is XYZ.
    public static let identityQuaternion = SIMD4<Float>(0, 0, 0, 1)

    public static func normalizedQuaternion(_ quat: SIMD4<Float>) -> SIMD4<Float> {
        let length = simd_length(quat)
        guard length.isFinite, length > 1e-6 else { return identityQuaternion }
        return quat / length
    }

    public static func makeMatrix(position: SIMD3<Float>, rotation: SIMD4<Float>, scale: SIMD3<Float>) -> matrix_float4x4 {
        let normalized = normalizedQuaternion(rotation)
        let simdQuat = simd_quatf(real: normalized.w, imag: SIMD3<Float>(normalized.x, normalized.y, normalized.z))
        var matrix = matrix_float4x4(simdQuat)
        matrix.columns.0 *= scale.x
        matrix.columns.1 *= scale.y
        matrix.columns.2 *= scale.z
        matrix.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1.0)
        return matrix
    }

    public static func makeViewMatrix(position: SIMD3<Float>, rotation: SIMD4<Float>) -> matrix_float4x4 {
        let world = makeMatrix(position: position, rotation: rotation, scale: SIMD3<Float>(repeating: 1.0))
        return simd_inverse(world)
    }

    public static func decomposeMatrix(_ matrix: matrix_float4x4) -> (position: SIMD3<Float>, rotation: SIMD4<Float>, scale: SIMD3<Float>) {
        let position = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        var axisX = SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        var axisY = SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        var axisZ = SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)

        var scaleX = simd_length(axisX)
        var scaleY = simd_length(axisY)
        var scaleZ = simd_length(axisZ)
        if scaleX < 1e-6 || scaleY < 1e-6 || scaleZ < 1e-6 {
            return (position, identityQuaternion, SIMD3<Float>(1, 1, 1))
        }

        axisX /= scaleX
        axisY /= scaleY
        axisZ /= scaleZ

        let det = simd_dot(axisX, simd_cross(axisY, axisZ))
        if det < 0.0 {
            scaleZ = -scaleZ
            axisZ = -axisZ
        }

        let rotationMatrix = simd_float3x3(columns: (axisX, axisY, axisZ))
        let quat = simd_quatf(rotationMatrix)
        let rotation = normalizedQuaternion(SIMD4<Float>(quat.imag.x, quat.imag.y, quat.imag.z, quat.real))
        return (position, rotation, SIMD3<Float>(scaleX, scaleY, scaleZ))
    }

    public static func quaternionFromEulerXYZ(_ euler: SIMD3<Float>) -> SIMD4<Float> {
        var matrix = matrix_identity_float4x4
        matrix.rotate(angle: euler.x, axis: xAxis)
        matrix.rotate(angle: euler.y, axis: yAxis)
        matrix.rotate(angle: euler.z, axis: zAxis)
        let quat = simd_quatf(matrix)
        return normalizedQuaternion(SIMD4<Float>(quat.imag.x, quat.imag.y, quat.imag.z, quat.real))
    }

    public static func eulerFromQuaternionXYZ(_ quat: SIMD4<Float>) -> SIMD3<Float> {
        let normalized = normalizedQuaternion(quat)
        let simdQuat = simd_quatf(real: normalized.w, imag: SIMD3<Float>(normalized.x, normalized.y, normalized.z))
        let m = simd_float3x3(simdQuat)
        let r13 = m.columns.2.x
        let clampedR13 = max(-1.0, min(1.0, r13))
        let y = asin(clampedR13)
        let cy = sqrt(max(0.0, 1.0 - clampedR13 * clampedR13))
        let singular = cy < 1e-6
        let x: Float
        let z: Float

        if !singular {
            x = atan2(-m.columns.2.y, m.columns.2.z)
            z = atan2(-m.columns.1.x, m.columns.0.x)
        } else {
            x = atan2(m.columns.0.y, m.columns.1.y)
            z = 0.0
        }
        return SIMD3<Float>(x, y, z)
    }

#if DEBUG
    private static var didSanityCheck = false

    public static func runTransformSanityOnce() {
        guard !didSanityCheck else { return }
        didSanityCheck = true

        let ninetyY = simd_quatf(angle: Float.pi * 0.5, axis: yAxis)
        let rotated = simd_normalize(ninetyY.act(SIMD3<Float>(1, 0, 0)))
        let expected = SIMD3<Float>(0, 0, -1)
        if simd_length(rotated - expected) > 1e-4 {
            MC_ASSERT(false, "Transform sanity failed: +90° Y rotation expected (0,0,-1). Got \(rotated).")
        }

        let rotatedForward = simd_normalize(ninetyY.act(SIMD3<Float>(0, 0, 1)))
        let expectedForward = SIMD3<Float>(1, 0, 0)
        if simd_length(rotatedForward - expectedForward) > 1e-4 {
            MC_ASSERT(false, "Transform sanity failed: +90° Y rotation expected (0,0,1)->(1,0,0). Got \(rotatedForward).")
        }

        let position = SIMD3<Float>(3, 5, 7)
        let rotation = SIMD4<Float>(ninetyY.imag.x, ninetyY.imag.y, ninetyY.imag.z, ninetyY.real)
        let matrix = makeMatrix(position: position, rotation: rotation, scale: SIMD3<Float>(1, 1, 1))
        let p = SIMD4<Float>(1, 0, 0, 1)
        let world = matrix * p
        let expectedWorld = SIMD4<Float>(expected.x + position.x,
                                         expected.y + position.y,
                                         expected.z + position.z,
                                         1.0)
        if simd_length(world - expectedWorld) > 1e-4 {
            MC_ASSERT(false, "Transform sanity failed: matrix transform mismatch. Got \(world), expected \(expectedWorld).")
        }
    }
#endif
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
        let zRange = nearZ - farZ
        let zScale = farZ / zRange
        let wzScale = (nearZ * farZ) / zRange
        self.init(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
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
        let z: Float = far / (near - far)
        let w: Float = (near * far) / (near - far)
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

        var nearDist: Float
        var farDist: Float

        // Accept either positive near/far distances or view-space Z values (RH forward -Z).
        if near <= 0.0 || far <= 0.0 {
            let maxZ = max(near, far)
            let minZ = min(near, far)
            nearDist = max(0.001, -maxZ)
            farDist = max(nearDist + 0.001, -minZ)
        } else {
            nearDist = near
            farDist = far
            if nearDist == farDist {
                farDist += 0.001
            }
            if nearDist > farDist {
                swap(&nearDist, &farDist)
            }
        }

        let fn = nearDist - farDist
        var result = matrix_identity_float4x4
        result.columns = (
            .init(2.0 / rl, 0, 0, 0),
            .init(0, 2.0 / tb, 0, 0),
            .init(0, 0, 1.0 / fn, 0),
            .init(-(right + left) / rl, -(top + bottom) / tb, nearDist / fn, 1.0)
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
