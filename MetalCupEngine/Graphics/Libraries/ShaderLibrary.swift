/// ShaderLibrary.swift
/// Defines the ShaderLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum ShaderType {
    case BasicVertex
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
}

public class ShaderLibrary: Library<ShaderType, MTLFunction> {
    
    private var _library: [ShaderType: Shader] = [:]
    
    public func register(_ type: ShaderType, name: String, functionName: String) {
        _library[type] = Shader(name: name, functionName: functionName)
    }

    public func registerDefaults() {
        register(.BasicVertex, name: "Basic Vertex", functionName: "vertex_basic")
        register(.InstancedVertex, name: "Instanced Vertex", functionName: "vertex_instanced")
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
    }
    
    override subscript(_ type: ShaderType)->MTLFunction {
        guard let fn = _library[type]?.function else {
            fatalError("ShaderLibrary: shader for \(type) not registered. Register shaders before building pipeline states.")
        }
        return fn
    }
}

public class Shader {
    
    var function: MTLFunction!
    
    init(name: String, functionName: String) {
        let fn = ResourceRegistry.resolveFunction(functionName, device: Engine.Device)
        guard let resolved = fn else {
            fatalError("Shader '\(functionName)' not found. Ensure the .metal file is compiled into the app target or runtime shader library.")
        }
        self.function = resolved
        self.function.label = name
    }
}
