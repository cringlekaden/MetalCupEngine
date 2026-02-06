//
//  Mouse.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

public enum MouseCodes: Int {
    case left = 0
    case right = 1
    case center = 2
}

public final class Mouse {
    
    private static let mouseButtonCount = 12
    private static var mouseButtonList = [Bool](repeating: false, count: mouseButtonCount)
    private static var overallMousePosition = SIMD2<Float>.zero
    private static var mousePositionDelta = SIMD2<Float>.zero
    private static var scrollWheelPosition: Float = 0.0
    private static var lastWheelPosition: Float = 0.0
    private static var scrollWheelChange: Float = 0.0
    private static var viewportOrigin = SIMD2<Float>.zero
    private static var viewportSize = SIMD2<Float>.zero

    public static func BeginFrame() {
        mousePositionDelta = .zero
        scrollWheelChange = 0
    }

    public static func SetViewportRect(origin: SIMD2<Float>, size: SIMD2<Float>) {
        viewportOrigin = origin
        viewportSize = size
    }
    
    public static func SetMouseButtonPressed(button: Int, isOn: Bool) {
        guard button >= 0 && button < mouseButtonList.count else { return }
        mouseButtonList[button] = isOn
    }
    
    public static func IsMouseButtonPressed(button: MouseCodes) -> Bool {
        let index = Int(button.rawValue)
        guard index >= 0 && index < mouseButtonList.count else { return false }
        return mouseButtonList[index]
    }
    
    public static func SetOverallMousePosition(position: SIMD2<Float>) {
        overallMousePosition = position
    }
    
    public static func SetMousePositionChange(overallPosition: SIMD2<Float>, deltaPosition: SIMD2<Float>) {
        overallMousePosition = overallPosition
        mousePositionDelta += deltaPosition
    }
    
    public static func ScrollMouse(deltaY: Float) {
        scrollWheelPosition += deltaY
        scrollWheelChange += deltaY
    }
    
    public static func GetMouseWindowPosition() -> SIMD2<Float> {
        return overallMousePosition
    }
    
    public static func GetDWheel() -> Float {
        let position = scrollWheelChange
        scrollWheelChange = 0
        return position
    }
    
    public static func GetDY() -> Float {
        let result = mousePositionDelta.y
        mousePositionDelta.y = 0
        return result
    }
    
    public static func GetDX() -> Float {
        let result = mousePositionDelta.x
        mousePositionDelta.x = 0
        return result
    }
    
    public static func GetMouseViewportPosition() -> SIMD2<Float> {
        guard !viewportSize.x.isZero, !viewportSize.y.isZero else { return .zero }
        let local = overallMousePosition - viewportOrigin
        let x = (local.x / viewportSize.x) * 2.0 - 1.0
        let y = (local.y / viewportSize.y) * 2.0 - 1.0
        return SIMD2<Float>(x, y)
    }

    public static func GetMouseViewportPositionPixels() -> SIMD2<Float> {
        guard !viewportSize.x.isZero, !viewportSize.y.isZero else { return .zero }
        return overallMousePosition - viewportOrigin
    }
}
