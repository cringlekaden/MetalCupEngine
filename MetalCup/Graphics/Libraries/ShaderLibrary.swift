//
//  VertexShaderLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

enum ShaderType {
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
    case BlurHFragment
    case BlurVFragment
}

class ShaderLibrary: Library<ShaderType, MTLFunction> {
    
    private var _library: [ShaderType: Shader] = [:]
    
    override func fillLibrary() {
        _library[.BasicVertex] = Shader(name: "Basic Vertex Shader", functionName: "vertex_basic")
        _library[.InstancedVertex] = Shader(name: "Instanced Vertex Shader", functionName: "vertex_instanced")
        _library[.BasicFragment] = Shader(name: "Basic Fragment Shader", functionName: "fragment_basic")
        _library[.SkyboxVertex] = Shader(name: "Skybox Vertex Shader", functionName: "vertex_skybox")
        _library[.SkyboxFragment] = Shader(name: "Skybox Fragment Shader", functionName: "fragment_skybox")
        _library[.FinalVertex] = Shader(name: "Final Vertex Shader", functionName: "vertex_final")
        _library[.FinalFragment] = Shader(name: "Final Fragment Shader", functionName: "fragment_final")
        _library[.CubemapVertex] = Shader(name: "Cubemap Vertex Shader", functionName: "vertex_cubemap")
        _library[.CubemapFragment] = Shader(name: "Cubemap Fragment Shader", functionName: "fragment_cubemap")
        _library[.IrradianceFragment] = Shader(name: "Cubemap Fragment Shader", functionName: "fragment_irradiance")
        _library[.PrefilteredFragment] = Shader(name: "Prefiltered Map Fragment Shader", functionName: "fragment_prefiltered")
        _library[.FSQuadVertex] = Shader(name: "Fullscreen Quad Vertex Shader", functionName: "vertex_quad")
        _library[.BRDFFragment] = Shader(name: "BRDF LUT Fragment Shader", functionName: "fragment_brdf")
        _library[.BloomExtractFragment] = Shader(name: "Bloom Extract Fragment Shader", functionName: "fragment_bloom_extract")
        _library[.BlurHFragment] = Shader(name: "Blur Horizontal Fragment Shader", functionName: "fragment_blur_h")
        _library[.BlurVFragment] = Shader(name: "Blur Vertical Fragment Shader", functionName: "fragment_blur_v")
        
    }
    
    override subscript(_ type: ShaderType)->MTLFunction {
        return (_library[type]?.function)!
    }
}

class Shader {
    
    var function: MTLFunction!
    
    init(name: String, functionName: String) {
        self.function = Engine.DefaultLibrary.makeFunction(name: functionName)
        self.function.label = name
    }
}
