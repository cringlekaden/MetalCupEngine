//
//  Mouse.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

enum MouseCodes: Int {
    case left = 0
    case right = 1
    case center = 2
}

class Mouse {
    
    private static var MOUSE_BUTTON_COUNT = 12
    private static var mouseButtonList = [Bool].init(repeating: false, count: MOUSE_BUTTON_COUNT)
    private static var overallMousePosition = SIMD2<Float>.zero
    private static var mousePositionDelta = SIMD2<Float>.zero
    private static var scrollWheelPosition: Float = 0.0
    private static var lastWheelPosition: Float = 0.0
    private static var scrollWheelChange: Float = 0.0
    
    public static func SetMouseButtonPressed(button: Int, isOn: Bool){
        mouseButtonList[button] = isOn
    }
    
    public static func IsMouseButtonPressed(button: MouseCodes)->Bool{
        return mouseButtonList[Int(button.rawValue)] == true
    }
    
    public static func SetOverallMousePosition(position: SIMD2<Float>){
        self.overallMousePosition = position
    }
    
    public static func SetMousePositionChange(overallPosition: SIMD2<Float>, deltaPosition: SIMD2<Float>){
        self.overallMousePosition = overallPosition
        self.mousePositionDelta = deltaPosition
    }
    
    public static func ScrollMouse(deltaY: Float){
        scrollWheelPosition += deltaY
        scrollWheelChange += deltaY
    }
    
    public static func GetMouseWindowPosition()->SIMD2<Float>{
        return overallMousePosition
    }
    
    public static func GetDWheel()->Float{
        let position = scrollWheelChange
        scrollWheelChange = 0
        return position
    }
    
    public static func GetDY()->Float{
        let result = mousePositionDelta.y
        mousePositionDelta.y = 0
        return result
    }
    
    public static func GetDX()->Float{
        let result = mousePositionDelta.x
        mousePositionDelta.x = 0
        return result
    }
    
    public static func GetMouseViewportPosition()->SIMD2<Float>{
        let x = (overallMousePosition.x - Renderer.ScreenSize.x * 0.5) / (Renderer.ScreenSize.x * 0.5)
        let y = (overallMousePosition.y - Renderer.ScreenSize.y * 0.5) / (Renderer.ScreenSize.y * 0.5)
        return SIMD2<Float>(x, y)
    }
}
