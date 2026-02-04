//
//  ApplicationSpecification.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import Foundation
import MetalKit

/// Describes how the engine should configure the initial application window and rendering surface.
public struct ApplicationSpecification {
    public var title: String
    public var width: Int
    public var height: Int
    public var resizable: Bool
    public var centered: Bool
    public var preferredFramesPerSecond: Int
    /// Optional overrides. If nil, engine defaults from `Preferences` are used.
    public var colorPixelFormat: MTLPixelFormat?
    public var depthStencilPixelFormat: MTLPixelFormat?
    public var sampleCount: Int

    public init(title: String = "MetalCup",
                width: Int = 1920,
                height: Int = 1080,
                resizable: Bool = true,
                centered: Bool = true,
                preferredFramesPerSecond: Int = 120,
                colorPixelFormat: MTLPixelFormat? = .bgra8Unorm,
                depthStencilPixelFormat: MTLPixelFormat? = .depth32Float,
                sampleCount: Int = 1) {
        self.title = title
        self.width = width
        self.height = height
        self.resizable = resizable
        self.centered = centered
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.colorPixelFormat = colorPixelFormat
        self.depthStencilPixelFormat = depthStencilPixelFormat
        self.sampleCount = sampleCount
    }
}

