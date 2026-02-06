//
//  RendererDelegate.swift
//  MetalCup
//
//  Created by Engine Scaffolding
//

import MetalKit

public protocol RendererDelegate: AnyObject {
    func update()
    func renderScene(into encoder: MTLRenderCommandEncoder)
    func renderOverlays(view: MTKView, commandBuffer: MTLCommandBuffer)
}
