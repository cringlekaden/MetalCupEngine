//
//  VertexDescriptorLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

enum VertexDescriptorType {
    case Basic
}

class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func fillLibrary() {
        _library[.Basic] = BasicVertexDescriptor()
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
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = SIMD3<Float>.size
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[2].offset = SIMD3<Float>.size + SIMD4<Float>.size
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[3].offset = SIMD3<Float>.size + SIMD4<Float>.size + SIMD2<Float>.size
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}
