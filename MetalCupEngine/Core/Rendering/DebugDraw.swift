/// DebugDraw.swift
/// Provides a submission queue for debug rendering.
/// Created by Kaden Cringle.

public final class DebugDraw {
    private var submittedGridParams: GridParams?

    public init() {}

    public func beginFrame() {
        submittedGridParams = nil
    }

    public func endFrame() {
        // Intentionally empty: submission queue persists until next beginFrame.
    }

    public func submitGridXZ(_ params: GridParams) {
        submittedGridParams = params
    }

    func gridParams() -> GridParams? {
        submittedGridParams
    }
}
