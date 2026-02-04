//
//  RendererDelegate.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import MetalKit

public protocol RendererDelegate: AnyObject {
    func update(deltaTime: Float)
    func renderScene(into encoder: MTLRenderCommandEncoder)
    func renderOverlays(into encoder: MTLRenderCommandEncoder)
}
