//
//  SamplerStateLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

enum SamplerStateType {
    case None
    case Linear
    case Nearest
}

class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState> {
    
    private var _library: [SamplerStateType : SamplerState] = [:]
    
    override func fillLibrary() {
        _library[.Linear] = LinearSamplerState()
        _library[.Nearest] = NearestSamplerState()
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
        samplerDescriptor.lodMinClamp = 0.0
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
        samplerDescriptor.lodMinClamp = 0.0
        samplerDescriptor.label = name
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}
