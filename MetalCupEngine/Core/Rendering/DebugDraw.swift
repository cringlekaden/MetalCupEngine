/// DebugDraw.swift
/// Provides a submission queue for debug rendering.
/// Created by Kaden Cringle.

public enum DebugDraw {
    private static var submittedGridParams: GridParams?

    public static func beginFrame() {
        submittedGridParams = nil
    }

    public static func endFrame() {
        // Intentionally empty: submission queue persists until next beginFrame.
    }

    public static func submitGridXZ(_ params: GridParams) {
        submittedGridParams = params
    }

    static func gridParams() -> GridParams? {
        submittedGridParams
    }
}
