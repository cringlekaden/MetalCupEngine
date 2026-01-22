//
//  GameObject.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/17/26.
//

import MetalKit

class GameObject: Node {
    
    private var _material = Material()
    private var _textureType: TextureType = .None
    private var _modelConstants = ModelConstants()
    private var _mesh: Mesh!
    
    init(name: String, meshType: MeshType) {
        super.init(name: name)
        _mesh = Entities.Meshes[meshType]
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
}

extension GameObject: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setTriangleFillMode(Preferences.isWireframeEnabled ? .lines : .fill)
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Basic])
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        if(_material.useTexture) {
            renderCommandEncoder.setFragmentTexture(Entities.Textures[_textureType], index: 0)
        }
        renderCommandEncoder.setFragmentBytes(&_material, length: Material.stride, index: 1)
        _mesh.drawPrimitives(renderCommandEncoder)
    }
}

extension GameObject {
    public func setMaterialColor(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        setMaterialColor(SIMD4<Float>(r, g, b, a))
    }
    
    public func setMaterialColor(_ color: SIMD4<Float>) {
        self._material.color = color
        self._material.useMaterialColor = true
        self._material.useTexture = false
    }
    
    public func setTexture(textureType: TextureType) {
        self._material.useTexture = true
        self._material.useMaterialColor = false
        self._textureType = textureType
    }
    
    public func setMaterialIsLit(_ isLit: Bool) { self._material.isLit = isLit }
    public func getMaterialIsLit() -> Bool { return self._material.isLit }
    public func setMaterialAmbient(_ r: Float, _ g: Float, _ b: Float) { setMaterialAmbient(SIMD3<Float>(r,g,b)) }
    public func setMaterialAmbient(_ ambient: SIMD3<Float>) { self._material.ambient = ambient }
    public func setMaterialAmbient(_ ambient: Float) { self._material.ambient = SIMD3<Float>(ambient, ambient, ambient) }
    public func addMaterialAmbient(_ amount: Float) { self._material.ambient += amount }
    public func getMaterialAmbient() -> SIMD3<Float> { return self._material.ambient }
    public func setMaterialDiffuse(_ r: Float, _ g: Float, _ b: Float) { setMaterialDiffuse(SIMD3<Float>(r,g,b)) }
    public func setMaterialDiffuse(_ diffuse: SIMD3<Float>) { self._material.diffuse = diffuse }
    public func setMaterialDiffuse(_ diffuse: Float) { self._material.diffuse = SIMD3<Float>(diffuse, diffuse, diffuse) }
    public func addMaterialDiffuse(_ amount: Float) { self._material.diffuse += amount }
    public func getMaterialDiffuse() -> SIMD3<Float> { return self._material.diffuse }
    public func setMaterialSpecular(_ r: Float, _ g: Float, _ b: Float) { setMaterialSpecular(SIMD3<Float>(r,g,b)) }
    public func setMaterialSpecular(_ specular: SIMD3<Float>) { self._material.specular = specular }
    public func setMaterialSpecular(_ specular: Float) { self._material.specular = SIMD3<Float>(specular, specular, specular) }
    public func addMaterialSpecular(_ amount: Float) { self._material.specular += amount }
    public func getMaterialSpecular() -> SIMD3<Float> { return self._material.specular }
    public func setMaterialShininess(_ shininess: Float) { self._material.shininess = shininess }
    public func getMaterialShininess() -> Float { return self._material.shininess }
}
