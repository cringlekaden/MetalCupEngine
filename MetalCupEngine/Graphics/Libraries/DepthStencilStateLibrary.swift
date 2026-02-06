//
//  DepthStencilStateLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/18/26.
//

import MetalKit

public enum DepthStencilStateType {
    case Less
    case LessEqualNoWrite
}

public class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func fillLibrary() {
        _library[.Less] = LessDepthStencilState()
        _library[.LessEqualNoWrite] = LessEqualNoWriteDepthStencilState()
    }
    
    override subscript(_ type: DepthStencilStateType)->MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}

protocol DepthStencilState {
    var depthStencilState: MTLDepthStencilState! { get }
}

class LessDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}

class LessEqualNoWriteDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}
