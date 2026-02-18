///// InputAccumulator.swift
///// Collects per-frame input from platform events without global state.

import simd

public final class InputAccumulator {
    private var mousePosition = SIMD2<Float>.zero
    private var mouseDelta = SIMD2<Float>.zero
    private var scrollDelta: Float = 0.0
    private var mouseButtons: [Bool]
    private var keys: [Bool]
    private var viewportOrigin = SIMD2<Float>.zero
    private var viewportSize = SIMD2<Float>.zero
    private var textInput = ""

    public init(mouseButtonCount: Int = 12, keyCount: Int = 256) {
        mouseButtons = [Bool](repeating: false, count: max(mouseButtonCount, 1))
        keys = [Bool](repeating: false, count: max(keyCount, 1))
    }

    public func setViewportRect(origin: SIMD2<Float>, size: SIMD2<Float>) {
        viewportOrigin = origin
        viewportSize = size
    }

    public func setMouseButton(button: Int, isOn: Bool) {
        guard button >= 0 && button < mouseButtons.count else { return }
        mouseButtons[button] = isOn
    }

    public func setMousePositionChange(overallPosition: SIMD2<Float>, deltaPosition: SIMD2<Float>) {
        mousePosition = overallPosition
        mouseDelta += deltaPosition
    }

    public func scroll(deltaY: Float) {
        scrollDelta += deltaY
    }

    public func setKeyPressed(_ keyCode: UInt16, isOn: Bool) {
        let index = Int(keyCode)
        guard index >= 0 && index < keys.count else { return }
        keys[index] = isOn
    }

    public func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        textInput.append(text)
    }


    public func snapshotAndReset() -> InputState {
        let state = InputState(
            mousePosition: mousePosition,
            mouseDelta: mouseDelta,
            scrollDelta: scrollDelta,
            mouseButtons: mouseButtons,
            keys: keys,
            viewportOrigin: viewportOrigin,
            viewportSize: viewportSize,
            textInput: textInput
        )
        mouseDelta = .zero
        scrollDelta = 0.0
        textInput = ""
        return state
    }
}
