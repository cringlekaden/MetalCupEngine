//
//  InstancedGameObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit

class InstancedGameObject: Node {
    
    private var _modelConstantBuffer: MTLBuffer!
    private var _mesh: Mesh!
    private var _material = MetalCupMaterial()
    
    internal var _nodes: [Node] = []
    
    
    init(meshType: MeshType, instanceCount: Int) {
        super.init(name: "Instanced GameObject")
        _mesh = Assets.Meshes[meshType]
        _mesh.setInstanceCount(instanceCount)
        generateInstances(instanceCount)
        createBuffer(instanceCount)
    }
    
    func updateNodes(_ updateNodeFunction: (Node, Int) -> ()) {
        for (index, node) in _nodes.enumerated() {
            updateNodeFunction(node, index)
        }
    }
    
    func generateInstances(_ instanceCount: Int) {
        for _ in 0..<instanceCount {
            _nodes.append(Node(name: "\(getName())_Instanced_Node"))
        }
    }
    
    func createBuffer(_ instanceCount: Int) {
        _modelConstantBuffer = Engine.Device.makeBuffer(length: ModelConstants.stride(instanceCount), options: [])
    }
    
    override func doUpdate() {
        var pointer = _modelConstantBuffer.contents().bindMemory(to: ModelConstants.self, capacity: _nodes.count)
        for node in _nodes {
            pointer.pointee.modelMatrix = matrix_multiply(self.modelMatrix, node.modelMatrix)
            pointer = pointer.advanced(by: 1)
        }
    }
}

extension InstancedGameObject: Renderable {
    func doRender(_ renderCommandEncoder: any MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.HDRInstanced])
        renderCommandEncoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        renderCommandEncoder.setVertexBuffer(_modelConstantBuffer, offset: 0, index: 2)
        renderCommandEncoder.setFragmentBytes(&_material, length: MetalCupMaterial.stride, index: 1)
        _mesh.drawPrimitives(renderCommandEncoder)
    }
}

extension InstancedGameObject {
    public func setColor(_ color: SIMD3<Float>) {
        self._material.baseColor = color
    }
    
    public func setColor(_ r: Float,_ g: Float,_ b: Float) {
        setColor(SIMD3<Float>(r,g,b))
    }
}
