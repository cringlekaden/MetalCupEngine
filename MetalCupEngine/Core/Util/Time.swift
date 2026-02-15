/// Time.swift
/// Defines the engine time utilities with variable and fixed timestep support.
/// Created by Kaden Cringle.

import Foundation

public final class Time {
    private static var _deltaTime: Float = 0.0
    private static var _unscaledDeltaTime: Float = 0.0
    private static var _timeScale: Float = 1.0
    private static var _fixedDeltaTime: Float = 1.0 / 60.0
    private static var _frameCount: UInt64 = 0
    private static var _totalTime: Float = 0.0
    private static var _unscaledTotalTime: Float = 0.0
    private static var _fixedAccumulator: Float = 0.0
    private static var _lastFrameTimestamp: TimeInterval?

    private static let maxFrameDelta: Float = 0.25
    private static let maxFixedSteps: Int = 5

    public static func UpdateFrame(at timestamp: TimeInterval) {
        let deltaSeconds: Float
        if let last = _lastFrameTimestamp {
            deltaSeconds = Float(timestamp - last)
        } else {
            deltaSeconds = 0.0
        }
        _lastFrameTimestamp = timestamp
        Update(deltaSeconds)
    }

    public static func Update(_ deltaSeconds: Float) {
        let clampedUnscaled = min(max(deltaSeconds, 0.0), maxFrameDelta)
        _unscaledDeltaTime = clampedUnscaled
        _deltaTime = clampedUnscaled * _timeScale
        _unscaledTotalTime += _unscaledDeltaTime
        _totalTime += _deltaTime
        _frameCount &+= 1

        let maxStepDelta = _fixedDeltaTime * Float(maxFixedSteps)
        let clampedStepDelta = min(_deltaTime, maxStepDelta)
        _fixedAccumulator += clampedStepDelta
    }

    public static func ConsumeFixedSteps() -> Int {
        guard _fixedDeltaTime > 0.0 else { return 0 }
        let availableSteps = Int(_fixedAccumulator / _fixedDeltaTime)
        if availableSteps <= 0 { return 0 }
        let steps = min(availableSteps, maxFixedSteps)
        _fixedAccumulator -= Float(steps) * _fixedDeltaTime
        return steps
    }

    public static func Reset() {
        _deltaTime = 0.0
        _unscaledDeltaTime = 0.0
        _totalTime = 0.0
        _unscaledTotalTime = 0.0
        _frameCount = 0
        _fixedAccumulator = 0.0
        _lastFrameTimestamp = nil
    }
}

extension Time {
    public static var DeltaTime: Float { _deltaTime }
    public static var UnscaledDeltaTime: Float { _unscaledDeltaTime }

    public static var TimeScale: Float {
        get { _timeScale }
        set { _timeScale = max(newValue, 0.0) }
    }

    public static var FixedDeltaTime: Float {
        get { _fixedDeltaTime }
        set { _fixedDeltaTime = max(newValue, 0.000_001) }
    }

    public static var FrameCount: UInt64 { _frameCount }
    public static var TotalTime: Float { _totalTime }
    public static var UnscaledTotalTime: Float { _unscaledTotalTime }
}
