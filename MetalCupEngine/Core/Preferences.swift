/// Preferences.swift
/// Defines the Preferences types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum ClearColor {
    static let White = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let Blue = MTLClearColor(red: 0.54, green: 0.78, blue: 1, alpha: 1)
    static let Grey = MTLClearColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
    static let Black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
}

public final class Preferences {
    public var clearColor: MTLClearColor = ClearColor.White
    public var HDRPixelFormat: MTLPixelFormat = .rgba16Float
    public var sRGBPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    public var defaultColorPixelFormat: MTLPixelFormat = .bgra8Unorm
    public var defaultDepthPixelFormat: MTLPixelFormat = .depth32Float
    public var isWireframeEnabled: Bool = false
}
