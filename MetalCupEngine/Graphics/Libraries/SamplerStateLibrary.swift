//
//  SamplerStateLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

public enum SamplerStateType {
    case None
    case Linear
    case Nearest
    case LinearClamp
    case LinearClampToZero
}

public class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState> {
    
    private var _library: [SamplerStateType : SamplerState] = [:]
    
    override func fillLibrary() {
        _library[.Linear] = LinearSamplerState()
        _library[.Nearest] = NearestSamplerState()
        _library[.LinearClamp] = LinearClampSamplerState()
        _library[.LinearClampToZero] = LinearClampToZeroSamplerState()
    }
    
    override subscript(_ type: SamplerStateType) -> MTLSamplerState {
        return (_library[type]?.samplerState!)!
    }
}

protocol SamplerState {
    var name: String { get }
    var samplerState: MTLSamplerState! { get }
}

class LinearSamplerState: SamplerState {
    var name: String = "Linear Sampler State"
    var samplerState: MTLSamplerState!
    init() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.label = name
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class NearestSamplerState: SamplerState {
    var name: String = "Nearest Sampler State"
    var samplerState: MTLSamplerState!
    init() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.label = name
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class LinearClampSamplerState: SamplerState {
    var name: String = "Linear Clamp Sampler State"
    var samplerState: MTLSamplerState!
    init() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        samplerDescriptor.maxAnisotropy = 16
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class LinearClampToZeroSamplerState: SamplerState {
    var name: String = "Linear Clamp To Zero Sampler State"
    var samplerState: MTLSamplerState!
    init() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        samplerDescriptor.rAddressMode = .clampToZero
        samplerDescriptor.maxAnisotropy = 16
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}
