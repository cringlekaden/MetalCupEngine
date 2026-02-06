//
//  Preferences.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

public enum ClearColor {
    static let White = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let Blue = MTLClearColor(red: 0.54, green: 0.78, blue: 1, alpha: 1)
    static let Grey = MTLClearColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
    static let Black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
}

class Preferences {
    public static var clearColor : MTLClearColor = ClearColor.White
    public static var HDRPixelFormat: MTLPixelFormat = .rgba16Float
    public static var sRGBPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    public static var defaultColorPixelFormat: MTLPixelFormat = .bgra8Unorm
    public static var defaultDepthPixelFormat: MTLPixelFormat = .depth32Float
    public static var isWireframeEnabled: Bool = false
    public static var initialSceneType: SceneType = .Sandbox
}
