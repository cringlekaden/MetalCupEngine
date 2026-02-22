/// VertexDescriptorLibrary.swift
/// Defines the VertexDescriptorLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum VertexDescriptorType {
    case Default
    case Simple
}

public class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func fillLibrary() {
        _library[.Default] = DefaultVertexDescriptor()
        _library[.Simple] = SimpleVertexDescriptor()
    }
    
    override subscript(_ type: VertexDescriptorType)->MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}

protocol VertexDescriptor {
    var name: String { get }
    var vertexDescriptor: MTLVertexDescriptor! { get }
}

struct DefaultVertexDescriptor: VertexDescriptor {
    var name: String = "Basic Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = MemoryLayout<Vertex>.offset(of: \Vertex.position) ?? 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<Vertex>.offset(of: \Vertex.color) ?? 0
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[2].offset = MemoryLayout<Vertex>.offset(of: \Vertex.texCoord) ?? 0
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[3].offset = MemoryLayout<Vertex>.offset(of: \Vertex.normal) ?? 0
        vertexDescriptor.attributes[4].format = .float4
        vertexDescriptor.attributes[4].bufferIndex = 0
        vertexDescriptor.attributes[4].offset = MemoryLayout<Vertex>.offset(of: \Vertex.tangent) ?? 0
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}

struct SimpleVertexDescriptor: VertexDescriptor {
    var name: String = "Cubemap Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.layouts[0].stride = SimpleVertex.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
    }
}
