/// ShaderLibrary.swift
/// Defines the ShaderLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum ShaderType {
    case InstancedVertex
    case BasicFragment
    case SkyboxVertex
    case SkyboxFragment
    case FinalVertex
    case FinalFragment
    case CubemapVertex
    case CubemapFragment
    case IrradianceFragment
    case PrefilteredVertex
    case PrefilteredFragment
    case FSQuadVertex
    case BRDFFragment
    case BloomExtractFragment
    case BloomDownsampleFragment
    case BlurHFragment
    case BlurVFragment
    case ProceduralSkyFragment
    case HDRILuminanceFragment
    case PickInstancedVertex
    case PickFragment
    case GridFragment
    case OutlineFragment
    case DebugLineVertex
    case DebugLineFragment
    case DepthAlphaFragment
    case ShadowAlphaFragment
}

public class ShaderLibrary: Library<ShaderType, MTLFunction> {
    private var _library: [ShaderType: Shader] = [:]
    private let resourceRegistry: ResourceRegistry
    private let device: MTLDevice
    private let fallbackLibrary: MTLLibrary?

    public init(resourceRegistry: ResourceRegistry, device: MTLDevice, fallbackLibrary: MTLLibrary?) {
        self.resourceRegistry = resourceRegistry
        self.device = device
        self.fallbackLibrary = fallbackLibrary
    }

    public func register(_ type: ShaderType, name: String, functionName: String) {
        _library[type] = Shader(
            name: name,
            functionName: functionName,
            resourceRegistry: resourceRegistry,
            device: device,
            fallbackLibrary: fallbackLibrary
        )
    }

    public func registerDefaults() {
        register(.InstancedVertex, name: "Scene Instanced Vertex", functionName: "vertex_scene_instanced")
        register(.BasicFragment, name: "Basic Fragment", functionName: "fragment_basic")
        register(.SkyboxVertex, name: "Skybox Vertex", functionName: "vertex_skybox")
        register(.SkyboxFragment, name: "Skybox Fragment", functionName: "fragment_skybox")
        register(.FinalVertex, name: "Final Vertex", functionName: "vertex_final")
        register(.FinalFragment, name: "Final Fragment", functionName: "fragment_final")
        register(.CubemapVertex, name: "Cubemap Vertex", functionName: "vertex_cubemap")
        register(.CubemapFragment, name: "Cubemap Fragment", functionName: "fragment_cubemap")
        register(.IrradianceFragment, name: "Irradiance Fragment", functionName: "fragment_irradiance")
        register(.PrefilteredFragment, name: "Prefiltered Fragment", functionName: "fragment_prefiltered")
        register(.FSQuadVertex, name: "Fullscreen Quad Vertex", functionName: "vertex_quad")
        register(.BRDFFragment, name: "BRDF Fragment", functionName: "fragment_brdf")
        register(.BloomExtractFragment, name: "Bloom Extract Fragment", functionName: "fragment_bloom_extract")
        register(.BloomDownsampleFragment, name: "Bloom Downsample Fragment", functionName: "fragment_bloom_downsample")
        register(.BlurHFragment, name: "Blur Horizontal Fragment", functionName: "fragment_blur_h")
        register(.BlurVFragment, name: "Blur Vertical Fragment", functionName: "fragment_blur_v")
        register(.ProceduralSkyFragment, name: "Procedural Sky Fragment", functionName: "fragment_procedural_sky")
        register(.HDRILuminanceFragment, name: "HDRI Luminance Fragment", functionName: "fragment_hdri_luminance")
        register(.PickInstancedVertex, name: "Pick Instanced Vertex", functionName: "vertex_pick_instanced")
        register(.PickFragment, name: "Pick Fragment", functionName: "fragment_pick_id")
        register(.GridFragment, name: "Grid Fragment", functionName: "fragment_grid")
        register(.OutlineFragment, name: "Outline Fragment", functionName: "fragment_outline_mask")
        register(.DebugLineVertex, name: "Debug Line Vertex", functionName: "vertex_debug_line")
        register(.DebugLineFragment, name: "Debug Line Fragment", functionName: "fragment_debug_line")
        register(.DepthAlphaFragment, name: "Depth Alpha Fragment", functionName: "fragment_depth_alpha")
        register(.ShadowAlphaFragment, name: "Shadow Alpha Fragment", functionName: "fragment_shadow_alpha")
    }

    override subscript(_ type: ShaderType)->MTLFunction {
        guard let fn = _library[type]?.function else {
            fatalError("ShaderLibrary: shader for \(type) not registered. Register shaders before building pipeline states.")
        }
        return fn
    }

    public func function(_ type: ShaderType, constants: MTLFunctionConstantValues?) -> MTLFunction {
        guard let shader = _library[type] else {
            fatalError("ShaderLibrary: shader for \(type) not registered. Register shaders before building pipeline states.")
        }
        return shader.makeFunction(constants: constants)
    }
}

public class Shader {
    let name: String
    let functionName: String
    private let resourceRegistry: ResourceRegistry
    private let device: MTLDevice
    private let fallbackLibrary: MTLLibrary?
    var function: MTLFunction!

    init(name: String, functionName: String, resourceRegistry: ResourceRegistry, device: MTLDevice, fallbackLibrary: MTLLibrary?) {
        self.name = name
        self.functionName = functionName
        self.resourceRegistry = resourceRegistry
        self.device = device
        self.fallbackLibrary = fallbackLibrary
        self.function = makeFunction(constants: nil)
    }

    func makeFunction(constants: MTLFunctionConstantValues?) -> MTLFunction {
        let fn = resourceRegistry.resolveFunction(functionName, device: device, fallbackLibrary: fallbackLibrary, constants: constants)
        guard let resolved = fn else {
            if let compileError = resourceRegistry.lastShaderCompileError {
                fatalError("Shader '\(functionName)' not found. Metal compile error: \(compileError)")
            }
            fatalError("Shader '\(functionName)' not found. Ensure the .metal file is compiled into the app target or runtime shader library.")
        }
        resolved.label = name
        return resolved
    }
}
