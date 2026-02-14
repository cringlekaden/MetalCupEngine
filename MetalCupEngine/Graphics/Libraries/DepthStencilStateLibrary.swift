/// DepthStencilStateLibrary.swift
/// Defines the DepthStencilStateLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum DepthStencilStateType {
    case Less
    case LessEqualNoWrite
    case EqualNoWrite
}

public class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func fillLibrary() {
        _library[.Less] = LessDepthStencilState()
        _library[.LessEqualNoWrite] = LessEqualNoWriteDepthStencilState()
        _library[.EqualNoWrite] = EqualNoWriteDepthStencilState()
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

class EqualNoWriteDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.depthCompareFunction = .equal
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}
