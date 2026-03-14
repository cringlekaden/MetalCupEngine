import Foundation

struct OzzJointRestPoseC {
    var parentIndex: Int32
    var tx: Float
    var ty: Float
    var tz: Float
    var rx: Float
    var ry: Float
    var rz: Float
    var rw: Float
    var sx: Float
    var sy: Float
    var sz: Float
}

struct OzzTrackSpanC {
    var jointIndex: Int32
    var translationStart: Int32
    var translationCount: Int32
    var rotationStart: Int32
    var rotationCount: Int32
    var scaleStart: Int32
    var scaleCount: Int32
}

struct OzzVec3KeyC {
    var time: Float
    var x: Float
    var y: Float
    var z: Float
}

struct OzzQuatKeyC {
    var time: Float
    var x: Float
    var y: Float
    var z: Float
    var w: Float
}

struct OzzLocalTransformC {
    var px: Float
    var py: Float
    var pz: Float
    var rx: Float
    var ry: Float
    var rz: Float
    var rw: Float
    var sx: Float
    var sy: Float
    var sz: Float
}

struct OzzModelMatrixC {
    var c0x: Float
    var c0y: Float
    var c0z: Float
    var c0w: Float
    var c1x: Float
    var c1y: Float
    var c1z: Float
    var c1w: Float
    var c2x: Float
    var c2y: Float
    var c2z: Float
    var c2w: Float
    var c3x: Float
    var c3y: Float
    var c3z: Float
    var c3w: Float
}

final class OzzLocalToModelContextRuntime {
    let nativeHandle: UnsafeMutableRawPointer

    init(nativeHandle: UnsafeMutableRawPointer) {
        self.nativeHandle = nativeHandle
    }

    deinit {
        MCEOzzDestroyLocalToModelContext(nativeHandle)
    }
}

final class OzzBlendingContextRuntime {
    let nativeHandle: UnsafeMutableRawPointer

    init(nativeHandle: UnsafeMutableRawPointer) {
        self.nativeHandle = nativeHandle
    }

    deinit {
        MCEOzzDestroyBlendingContext(nativeHandle)
    }
}

final class OzzRootMotionRuntime {
    let nativeHandle: UnsafeMutableRawPointer

    init(nativeHandle: UnsafeMutableRawPointer) {
        self.nativeHandle = nativeHandle
    }

    deinit {
        MCEOzzDestroyRootMotionContext(nativeHandle)
    }
}

final class OzzSkeletonRuntime {
    let nativeHandle: UnsafeMutableRawPointer
    let jointCount: Int
    private var localToModelContext: OzzLocalToModelContextRuntime?
    private var blendingContext: OzzBlendingContextRuntime?

    init(nativeHandle: UnsafeMutableRawPointer, jointCount: Int) {
        self.nativeHandle = nativeHandle
        self.jointCount = jointCount
    }

    deinit {
        blendingContext = nil
        localToModelContext = nil
        MCEOzzDestroySkeletonRuntime(nativeHandle)
    }

    var maxSoaTracks: Int {
        (jointCount + 3) / 4
    }

    func context() -> OzzLocalToModelContextRuntime? {
        if let localToModelContext {
            return localToModelContext
        }
        guard let handle = MCEOzzCreateLocalToModelContext(Int32(maxSoaTracks), Int32(jointCount)) else {
            return nil
        }
        let created = OzzLocalToModelContextRuntime(nativeHandle: handle)
        localToModelContext = created
        return created
    }

    func blendingContext(maxLayers: Int) -> OzzBlendingContextRuntime? {
        if let blendingContext {
            return blendingContext
        }
        guard maxLayers > 0,
              let handle = MCEOzzCreateBlendingContext(Int32(maxSoaTracks), Int32(maxLayers)) else {
            return nil
        }
        let created = OzzBlendingContextRuntime(nativeHandle: handle)
        blendingContext = created
        return created
    }
}

final class OzzSamplingContextRuntime {
    let nativeHandle: UnsafeMutableRawPointer

    init(nativeHandle: UnsafeMutableRawPointer) {
        self.nativeHandle = nativeHandle
    }

    deinit {
        MCEOzzDestroySamplingContext(nativeHandle)
    }
}

final class OzzAnimationRuntime {
    let nativeHandle: UnsafeMutableRawPointer
    let jointCount: Int
    private var samplingContext: OzzSamplingContextRuntime?

    init(nativeHandle: UnsafeMutableRawPointer, jointCount: Int) {
        self.nativeHandle = nativeHandle
        self.jointCount = jointCount
    }

    deinit {
        samplingContext = nil
        MCEOzzDestroyAnimationRuntime(nativeHandle)
    }

    func context(maxSoaTracks: Int) -> OzzSamplingContextRuntime? {
        if let samplingContext {
            return samplingContext
        }
        guard maxSoaTracks > 0,
              let handle = MCEOzzCreateSamplingContext(Int32(maxSoaTracks)) else {
            return nil
        }
        let created = OzzSamplingContextRuntime(nativeHandle: handle)
        samplingContext = created
        return created
    }
}
