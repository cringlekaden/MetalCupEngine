/// FrameContext.swift
/// Defines per-frame time and input snapshots.
/// Created by refactor.

import simd

public struct FrameTime {
    public let deltaTime: Float
    public let unscaledDeltaTime: Float
    public let timeScale: Float
    public let fixedDeltaTime: Float
    public let frameCount: UInt64
    public let totalTime: Float
    public let unscaledTotalTime: Float

    public init(deltaTime: Float,
                unscaledDeltaTime: Float,
                timeScale: Float,
                fixedDeltaTime: Float,
                frameCount: UInt64,
                totalTime: Float,
                unscaledTotalTime: Float) {
        self.deltaTime = deltaTime
        self.unscaledDeltaTime = unscaledDeltaTime
        self.timeScale = timeScale
        self.fixedDeltaTime = fixedDeltaTime
        self.frameCount = frameCount
        self.totalTime = totalTime
        self.unscaledTotalTime = unscaledTotalTime
    }
}

public struct InputState {
    public let mousePosition: SIMD2<Float>
    public let mouseDelta: SIMD2<Float>
    public let scrollDelta: Float
    public let mouseButtons: [Bool]
    public let keys: [Bool]
    public let viewportOrigin: SIMD2<Float>
    public let viewportSize: SIMD2<Float>
    public let textInput: String

    public init(mousePosition: SIMD2<Float>,
                mouseDelta: SIMD2<Float>,
                scrollDelta: Float,
                mouseButtons: [Bool],
                keys: [Bool],
                viewportOrigin: SIMD2<Float>,
                viewportSize: SIMD2<Float>,
                textInput: String) {
        self.mousePosition = mousePosition
        self.mouseDelta = mouseDelta
        self.scrollDelta = scrollDelta
        self.mouseButtons = mouseButtons
        self.keys = keys
        self.viewportOrigin = viewportOrigin
        self.viewportSize = viewportSize
        self.textInput = textInput
    }
}

public struct FrameContext {
    public let time: FrameTime
    public let input: InputState

    public init(time: FrameTime, input: InputState) {
        self.time = time
        self.input = input
    }
}
