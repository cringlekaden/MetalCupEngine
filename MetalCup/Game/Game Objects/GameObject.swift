//
//  GameObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

class GameObject: Node {
    
    private var _material: MetalCupMaterial? = nil
    private var _albedoMapTextureType: TextureType = .None
    private var _normalMapTextureType: TextureType = .None
    private var _metallicMapTextureType: TextureType = .None
    private var _roughnessMapTextureType: TextureType = .None
    private var _mrMapTextureType: TextureType = .None
    private var _aoMapTextureType: TextureType = .None
    private var _emissiveMapTextureType: TextureType = .None
    private var _modelConstants = ModelConstants()
    private var _mesh: Mesh!
    private var _cullMode: MTLCullMode = .back
    private var _frontFacing: MTLWinding = .counterClockwise
    private var _depthState: DepthStencilStateType = .Less
    
    var renderPipelineState: RenderPipelineStateType { return .HDRBasic }
    
    init(name: String, meshType: MeshType) {
        super.init(name: name)
        _mesh = Assets.Meshes[meshType]
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
}

extension GameObject: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineState])
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[_depthState])
        renderCommandEncoder.setCullMode(_cullMode)
        renderCommandEncoder.setFrontFacing(_frontFacing)
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        _mesh.drawPrimitives(renderCommandEncoder, material: _material, albedoMapTextureType: _albedoMapTextureType, normalMapTextureType: _normalMapTextureType, metallicMapTextureType: _metallicMapTextureType, roughnessMapTextureType: _roughnessMapTextureType, mrMapTextureType: _mrMapTextureType, aoMapTextureType: _aoMapTextureType, emissiveMapTextureType: _emissiveMapTextureType)
    }
}

extension GameObject {
    public func useMaterial(_ material: MetalCupMaterial) {
        _material = material
    }

    public func useAlbedoMapTexture(_ textureType: TextureType) {
        _albedoMapTextureType = textureType
    }
    
    public func useNormalMapTexture(_ textureType: TextureType) {
        _normalMapTextureType = textureType
    }
    
    public func useMetallicMapTexture(_ textureType: TextureType) {
        _metallicMapTextureType = textureType
    }
    
    public func useRoughnessMapTexture(_ textureType: TextureType) {
        _roughnessMapTextureType = textureType
    }
    
    public func useMRMapTexture(_ textureType: TextureType) {
        _mrMapTextureType = textureType
    }
    
    public func useAOMapTexture(_ textureType: TextureType) {
        _aoMapTextureType = textureType
    }
    
    public func useEmissiveMapTexture(_ textureType: TextureType) {
        _emissiveMapTextureType = textureType
    }
    
    public func setCullMode(_ mode: MTLCullMode) { _cullMode = mode }
    
    public func setFrontFacing(_ winding: MTLWinding) { _frontFacing = winding }
    
    public func setDepthState(_ type: DepthStencilStateType) { _depthState = type }
}
