//
//  VertexDescriptorLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

enum VertexDescriptorType {
    case Basic
    case Cubemap
}

class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func fillLibrary() {
        _library[.Basic] = BasicVertexDescriptor()
        _library[.Cubemap] = CubemapVertexDescriptor()
    }
    
    override subscript(_ type: VertexDescriptorType)->MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}

protocol VertexDescriptor {
    var name: String { get }
    var vertexDescriptor: MTLVertexDescriptor! { get }
}

public struct BasicVertexDescriptor: VertexDescriptor {
    var name: String = "Basic Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    init() {
        var offset: Int = 0
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = offset
        offset += SIMD3<Float>.size
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = offset
        offset += SIMD4<Float>.size
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[2].offset = offset
        offset += SIMD3<Float>.size
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[3].offset = offset
        offset += SIMD3<Float>.size
        vertexDescriptor.attributes[4].format = .float3
        vertexDescriptor.attributes[4].bufferIndex = 0
        vertexDescriptor.attributes[4].offset = offset
        offset += SIMD3<Float>.size
        vertexDescriptor.attributes[5].format = .float3
        vertexDescriptor.attributes[5].bufferIndex = 0
        vertexDescriptor.attributes[5].offset = offset
        offset += SIMD3<Float>.size
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}

public struct CubemapVertexDescriptor: VertexDescriptor {
    var name: String = "Cubemap Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.layouts[0].stride = CubemapVertex.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
    }
}
