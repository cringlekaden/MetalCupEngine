//
//  GameObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

class GameObject: Node {
    
    private var _material: MetalCupMaterial? = nil
    private var _albedoMapHandle: AssetHandle? = nil
    private var _normalMapHandle: AssetHandle? = nil
    private var _metallicMapHandle: AssetHandle? = nil
    private var _roughnessMapHandle: AssetHandle? = nil
    private var _mrMapHandle: AssetHandle? = nil
    private var _aoMapHandle: AssetHandle? = nil
    private var _emissiveMapHandle: AssetHandle? = nil
    private var _modelConstants = ModelConstants()
    private var _mesh: MCMesh?
    private var _meshHandle: AssetHandle?
    private var _cullMode: MTLCullMode = .back
    private var _frontFacing: MTLWinding = .counterClockwise
    private var _depthState: DepthStencilStateType = .Less
    
    var renderPipelineState: RenderPipelineStateType { return .HDRBasic }
    
    init(name: String, mesh: MCMesh) {
        super.init(name: name)
        _mesh = mesh
    }

    init(name: String, meshHandle: AssetHandle?) {
        super.init(name: name)
        setMesh(handle: meshHandle)
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
}

extension GameObject: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        guard let mesh = _mesh else { return }
        renderCommandEncoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineState])
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[_depthState])
        renderCommandEncoder.setCullMode(_cullMode)
        renderCommandEncoder.setFrontFacing(_frontFacing)
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        mesh.drawPrimitives(
            renderCommandEncoder,
            material: _material,
            albedoMapHandle: _albedoMapHandle,
            normalMapHandle: _normalMapHandle,
            metallicMapHandle: _metallicMapHandle,
            roughnessMapHandle: _roughnessMapHandle,
            mrMapHandle: _mrMapHandle,
            aoMapHandle: _aoMapHandle,
            emissiveMapHandle: _emissiveMapHandle
        )
    }
}

extension GameObject {
    public func useMaterial(_ material: MetalCupMaterial) {
        _material = material
    }

    public func useAlbedoMapTexture(_ handle: AssetHandle?) {
        _albedoMapHandle = handle
    }
    
    public func useNormalMapTexture(_ handle: AssetHandle?) {
        _normalMapHandle = handle
    }
    
    public func useMetallicMapTexture(_ handle: AssetHandle?) {
        _metallicMapHandle = handle
    }
    
    public func useRoughnessMapTexture(_ handle: AssetHandle?) {
        _roughnessMapHandle = handle
    }
    
    public func useMRMapTexture(_ handle: AssetHandle?) {
        _mrMapHandle = handle
    }
    
    public func useAOMapTexture(_ handle: AssetHandle?) {
        _aoMapHandle = handle
    }
    
    public func useEmissiveMapTexture(_ handle: AssetHandle?) {
        _emissiveMapHandle = handle
    }

    public func setMesh(handle: AssetHandle?) {
        _meshHandle = handle
        guard let handle else {
            _mesh = nil
            return
        }
        _mesh = AssetManager.mesh(handle: handle)
    }
    
    public func setCullMode(_ mode: MTLCullMode) { _cullMode = mode }
    
    public func setFrontFacing(_ winding: MTLWinding) { _frontFacing = winding }
    
    public func setDepthState(_ type: DepthStencilStateType) { _depthState = type }
}
