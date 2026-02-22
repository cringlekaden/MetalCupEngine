/// SamplerStateLibrary.swift
/// Defines the SamplerStateLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum SamplerStateType {
    case None
    case Linear
    case Nearest
    case LinearClamp
    case LinearClampToZero
    case ShadowCompare
    case ShadowDepth
}

public class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState> {
    private var _library: [SamplerStateType : SamplerState] = [:]
    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
        super.init()
    }

    override func fillLibrary() {
        _library[.Linear] = LinearSamplerState(device: device)
        _library[.Nearest] = NearestSamplerState(device: device)
        _library[.LinearClamp] = LinearClampSamplerState(device: device)
        _library[.LinearClampToZero] = LinearClampToZeroSamplerState(device: device)
        _library[.ShadowCompare] = ShadowCompareSamplerState(device: device)
        _library[.ShadowDepth] = ShadowDepthSamplerState(device: device)
    }

    override subscript(_ type: SamplerStateType) -> MTLSamplerState {
        guard let sampler = _library[type]?.samplerState else {
            MC_ASSERT(false, "Missing sampler state for \(type).")
            fatalError("Missing sampler state for \(type).")
        }
        return sampler
    }
}

protocol SamplerState {
    var name: String { get }
    var samplerState: MTLSamplerState! { get }
}

class LinearSamplerState: SamplerState {
    var name: String = "Linear Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.label = name
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class NearestSamplerState: SamplerState {
    var name: String = "Nearest Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .nearest
        samplerDescriptor.label = name
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class LinearClampSamplerState: SamplerState {
    var name: String = "Linear Clamp Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        samplerDescriptor.maxAnisotropy = 16
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class LinearClampToZeroSamplerState: SamplerState {
    var name: String = "Linear Clamp To Zero Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        samplerDescriptor.rAddressMode = .clampToZero
        samplerDescriptor.maxAnisotropy = 16
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

class ShadowCompareSamplerState: SamplerState {
    var name: String = "Shadow Compare Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        samplerDescriptor.compareFunction = .lessEqual
        samplerDescriptor.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}
class ShadowDepthSamplerState: SamplerState {
    var name: String = "Shadow Depth Sampler State"
    var samplerState: MTLSamplerState!
    init(device: MTLDevice) {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        samplerDescriptor.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
}

