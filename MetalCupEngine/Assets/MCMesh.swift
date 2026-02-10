//
//  MCMesh.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit
import Foundation
import ModelIO

public class MCMesh {
    
    private var _vertices: [Vertex] = []
    private var _simpleVertices: [SimpleVertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _simpleVertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submeshes: [Submesh] = []
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(assetURL: URL) {
        createMeshFromURL(assetURL, name: assetURL.lastPathComponent)
    }
    
    func createMesh() {}
    
    private func createBuffer() {
        if(_vertices.count > 0){
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count), options: [])
        } else if(_simpleVertices.count > 0) {
            _simpleVertexBuffer = Engine.Device.makeBuffer(bytes: _simpleVertices, length: SimpleVertex.stride(_simpleVertices.count), options: [])
        }
    }
    
    private func createMeshFromURL(_ assetURL: URL, name: String) {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Default])
        (descriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (descriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeColor
        (descriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (descriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (descriptor.attributes[4] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        (descriptor.attributes[5] as! MDLVertexAttribute).name = MDLVertexAttributeBitangent
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        let asset = MDLAsset(url: assetURL, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        asset.loadTextures()
        var mdlMeshes: [MDLMesh] = []
        do {
            mdlMeshes = try MTKMesh.newMeshes(asset: asset, device: Engine.Device).modelIOMeshes
        } catch {
            print("ERROR::LOADING_MESH::__\(name)__::\(error)")
        }
        guard !mdlMeshes.isEmpty else {
            print("ERROR::LOADING_MESH::__\(name)__::No model IO meshes found.")
            return
        }
        var mtkMeshes: [MTKMesh] = []
        for mdlMesh in mdlMeshes {
            let baseFolder = assetURL.deletingLastPathComponent()
            for case let sub as MDLSubmesh in (mdlMesh.submeshes ?? []) {
                if let mat = sub.material {
                    forceResolveMaterialTextures(mat, baseFolder: baseFolder)
                }
            }
            mdlMesh.vertexDescriptor = descriptor
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, tangentAttributeNamed: MDLVertexAttributeTangent, bitangentAttributeNamed: MDLVertexAttributeBitangent)
            do {
                let mtkMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
                mtkMeshes.append(mtkMesh)
            } catch {
                print("ERROR::LOADING_MESH::__\(name)__::\(error)")
            }
        }
        guard let mtkMesh = mtkMeshes.first, let mdlMesh = mdlMeshes.first else {
            print("ERROR::LOADING_MESH::__\(name)__::No Metal meshes created.")
            return
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            if let mdlSubmesh = (mdlMesh.submeshes?[i] as? MDLSubmesh) {
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
                addSubmesh(submesh)
            }
        }
    }
    
    func setInstanceCount(_ count: Int) {
        self._instanceCount = count
    }
    
    func addSubmesh(_ submesh: Submesh) {
        _submeshes.append(submesh)
    }
    
    func addVertex(position: SIMD3<Float>, color: SIMD4<Float> = SIMD4<Float>(1,0,1,1), texCoord: SIMD2<Float> = SIMD2<Float>(0,0), normal: SIMD3<Float> = SIMD3<Float>(0,1,0), tangent: SIMD3<Float> = SIMD3<Float>(1,0,0), bitangent: SIMD3<Float> = SIMD3<Float>(0,0,1)) {
        _vertices.append(Vertex(position: position, color: color, texCoord: texCoord, normal: normal, tangent: tangent, bitangent: bitangent))
    }
    
    func addSimpleVertex(position: SIMD3<Float>) {
        _simpleVertices.append(SimpleVertex(position: position))
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        material: MetalCupMaterial? = nil,
                        albedoMapHandle: AssetHandle? = nil,
                        normalMapHandle: AssetHandle? = nil,
                        metallicMapHandle: AssetHandle? = nil,
                        roughnessMapHandle: AssetHandle? = nil,
                        mrMapHandle: AssetHandle? = nil,
                        aoMapHandle: AssetHandle? = nil,
                        emissiveMapHandle: AssetHandle? = nil) {
        if(_vertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            if(_submeshes.count > 0) {
                for submesh in _submeshes {
                    submesh.applyTextures(
                        renderCommandEncoder: renderCommandEncoder,
                        albedoMapHandle: albedoMapHandle,
                        normalMapHandle: normalMapHandle,
                        metallicMapHandle: metallicMapHandle,
                        roughnessMapHandle: roughnessMapHandle,
                        mrMapHandle: mrMapHandle,
                        aoMapHandle: aoMapHandle,
                        emissiveMapHandle: emissiveMapHandle
                    )
                    submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer, indexBufferOffset: submesh.indexBufferOffset, instanceCount: _instanceCount)
                }
            } else {
                if material != nil
                    || albedoMapHandle != nil
                    || normalMapHandle != nil
                    || metallicMapHandle != nil
                    || roughnessMapHandle != nil
                    || mrMapHandle != nil
                    || aoMapHandle != nil
                    || emissiveMapHandle != nil {
                    var resolvedMaterial = material ?? MetalCupMaterial()
                    if resolvedMaterial.flags == 0 {
                        var flags = MetalCupMaterialFlags()
                        if albedoMapHandle != nil { flags.insert(.hasBaseColorMap) }
                        if normalMapHandle != nil { flags.insert(.hasNormalMap) }
                        if mrMapHandle != nil {
                            flags.insert(.hasMetalRoughnessMap)
                        } else {
                            if metallicMapHandle != nil { flags.insert(.hasMetallicMap) }
                            if roughnessMapHandle != nil { flags.insert(.hasRoughnessMap) }
                        }
                        if aoMapHandle != nil { flags.insert(.hasAOMap) }
                        if emissiveMapHandle != nil { flags.insert(.hasEmissiveMap) }
                        resolvedMaterial.flags = flags.rawValue
                    }
                    renderCommandEncoder.setFragmentBytes(&resolvedMaterial, length: MetalCupMaterial.stride, index: 1)
                    applyTextureOverrides(
                        renderCommandEncoder: renderCommandEncoder,
                        albedoMapHandle: albedoMapHandle,
                        normalMapHandle: normalMapHandle,
                        metallicMapHandle: metallicMapHandle,
                        roughnessMapHandle: roughnessMapHandle,
                        mrMapHandle: mrMapHandle,
                        aoMapHandle: aoMapHandle,
                        emissiveMapHandle: emissiveMapHandle
                    )
                } else {
                    renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
                }
                renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _vertices.count, instanceCount: _instanceCount)
            }
        } else if(_simpleVertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_simpleVertexBuffer, offset: 0, index: 0)
            renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
            renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _simpleVertices.count, instanceCount: _instanceCount)
        }
    }

    private func applyTextureOverrides(renderCommandEncoder: MTLRenderCommandEncoder,
                                       albedoMapHandle: AssetHandle?,
                                       normalMapHandle: AssetHandle?,
                                       metallicMapHandle: AssetHandle?,
                                       roughnessMapHandle: AssetHandle?,
                                       mrMapHandle: AssetHandle?,
                                       aoMapHandle: AssetHandle?,
                                       emissiveMapHandle: AssetHandle?) {
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        renderCommandEncoder.setFragmentTexture(albedoMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 0)
        renderCommandEncoder.setFragmentTexture(normalMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 1)
        renderCommandEncoder.setFragmentTexture(metallicMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 2)
        renderCommandEncoder.setFragmentTexture(roughnessMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 3)
        renderCommandEncoder.setFragmentTexture(mrMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 4)
        renderCommandEncoder.setFragmentTexture(aoMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 5)
        renderCommandEncoder.setFragmentTexture(emissiveMapHandle.flatMap { AssetManager.texture(handle: $0) }, index: 6)
        renderCommandEncoder.setFragmentTexture(nil, index: 10)
        renderCommandEncoder.setFragmentTexture(nil, index: 11)
        renderCommandEncoder.setFragmentTexture(nil, index: 12)
        renderCommandEncoder.setFragmentTexture(nil, index: 13)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.irradianceCubemap), index: 7)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.prefilteredCubemap), index: 8)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.brdfLut), index: 9)
    }
}

class Submesh {
    
    private var _indices: [UInt32] = []
    private var _indexCount: Int = 0
    public var indexCount: Int { return _indexCount }
    
    private var _indexBuffer: MTLBuffer!
    public var indexBuffer: MTLBuffer { return _indexBuffer }

    private var _primitiveType: MTLPrimitiveType = .triangle
    public var primitiveType: MTLPrimitiveType { return _primitiveType }
    
    private var _indexType: MTLIndexType = .uint32
    public var indexType: MTLIndexType { return _indexType }
    
    private var _indexBufferOffset: Int = 0
    public var indexBufferOffset: Int { return _indexBufferOffset }
    
    private var _material = MetalCupMaterial()
    private var _materialFlags = MetalCupMaterialFlags()
    private var _albedoMapTexture: MTLTexture!
    private var _normalMapTexture: MTLTexture!
    private var _metallicMapTexture: MTLTexture!
    private var _roughnessMapTexture: MTLTexture!
    private var _mrMapTexture: MTLTexture!
    private var _aoMapTexture: MTLTexture!
    private var _emissiveMapTexture: MTLTexture!
    private var _clearcoatMapTexture: MTLTexture!
    private var _clearcoatRoughnessMapTexture: MTLTexture!
    private var _sheenColorMapTexture: MTLTexture!
    private var _sheenIntensityMapTexture: MTLTexture!
    
    init(indices: [UInt32]) {
        self._indices = indices
        self._indexCount = indices.count
        createIndexBuffer()
    }
    
    init(mtkSubmesh: MTKSubmesh, mdlSubmesh: MDLSubmesh) {
        _indexBuffer = mtkSubmesh.indexBuffer.buffer
        _indexBufferOffset = mtkSubmesh.indexBuffer.offset
        _indexCount = mtkSubmesh.indexCount
        _indexType = mtkSubmesh.indexType
        _primitiveType = mtkSubmesh.primitiveType
        if let material = mdlSubmesh.material {
            createTexture(material)
            createMaterial(material)
        }
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
                       albedoMapHandle: AssetHandle?,
                       normalMapHandle: AssetHandle?,
                       metallicMapHandle: AssetHandle?,
                       roughnessMapHandle: AssetHandle?,
                       mrMapHandle: AssetHandle?,
                       aoMapHandle: AssetHandle?,
                       emissiveMapHandle: AssetHandle?) {
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        let albedoMapTexture = albedoMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _albedoMapTexture
        renderCommandEncoder.setFragmentTexture(albedoMapTexture, index: 0)
        let normalMapTexture = normalMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _normalMapTexture
        renderCommandEncoder.setFragmentTexture(normalMapTexture, index: 1)
        let metallicMapTexture = metallicMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _metallicMapTexture
        renderCommandEncoder.setFragmentTexture(metallicMapTexture, index: 2)
        let roughnessMapTexture = roughnessMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _roughnessMapTexture
        renderCommandEncoder.setFragmentTexture(roughnessMapTexture, index: 3)
        let mrMapTexture = mrMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _mrMapTexture
        renderCommandEncoder.setFragmentTexture(mrMapTexture, index: 4)
        let aoMapTexture = aoMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _aoMapTexture
        renderCommandEncoder.setFragmentTexture(aoMapTexture, index: 5)
        let emissiveMapTexture = emissiveMapHandle.flatMap { AssetManager.texture(handle: $0) } ?? _emissiveMapTexture
        renderCommandEncoder.setFragmentTexture(emissiveMapTexture, index: 6)
        let clearcoatMapTexture = _clearcoatMapTexture
        renderCommandEncoder.setFragmentTexture(clearcoatMapTexture, index: 10)
        let clearcoatRoughnessMapTexture = _clearcoatRoughnessMapTexture
        renderCommandEncoder.setFragmentTexture(clearcoatRoughnessMapTexture, index: 11)
        let sheenColorMapTexture = _sheenColorMapTexture
        renderCommandEncoder.setFragmentTexture(sheenColorMapTexture, index: 12)
        let sheenIntensityMapTexture = _sheenIntensityMapTexture
        renderCommandEncoder.setFragmentTexture(sheenIntensityMapTexture, index: 13)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.irradianceCubemap), index: 7)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.prefilteredCubemap), index: 8)
        renderCommandEncoder.setFragmentTexture(AssetManager.texture(handle: BuiltinAssets.brdfLut), index: 9)
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: MetalCupMaterial?) {
        var material: MetalCupMaterial = customMaterial ?? _material
        if material.flags == 0 {
            material.flags = _materialFlags.rawValue
        } else {
            material.flags |= _materialFlags.rawValue
        }
        renderCommandEncoder.setFragmentBytes(&material, length: MetalCupMaterial.stride, index: 1)
    }
    
    private func createTexture(_ mdlMaterial: MDLMaterial) {
        if(mdlMaterial.property(with: .baseColor)?.type == .texture) {
            _albedoMapTexture = texture(for: .baseColor, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: true)
            _materialFlags.insert(.hasBaseColorMap)
        }
        if(mdlMaterial.property(with: .tangentSpaceNormal)?.type == .texture) {
            _normalMapTexture = texture(for: .tangentSpaceNormal, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasNormalMap)
        }
        let metallicProperty = mdlMaterial.property(with: .metallic)
        let roughnessProperty = mdlMaterial.property(with: .roughness)
        let metallicTexture = metallicProperty?.type == .texture ? metallicProperty?.textureSamplerValue?.texture : nil
        let roughnessTexture = roughnessProperty?.type == .texture ? roughnessProperty?.textureSamplerValue?.texture : nil
        let usesCombinedMetalRoughness = metallicTexture != nil && roughnessTexture != nil && metallicTexture === roughnessTexture
        if(usesCombinedMetalRoughness) {
            _mrMapTexture = texture(for: .metallic, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasMetalRoughnessMap)
        } else {
            if(metallicTexture != nil) {
                _metallicMapTexture = texture(for: .metallic, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
                _materialFlags.insert(.hasMetallicMap)
            }
            if(roughnessTexture != nil) {
                _roughnessMapTexture = texture(for: .roughness, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
                _materialFlags.insert(.hasRoughnessMap)
            }
        }
        if(mdlMaterial.property(with: .ambientOcclusion)?.type == .texture) {
            _aoMapTexture = texture(for: .ambientOcclusion, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasAOMap)
        }
        if(mdlMaterial.property(with: .emission)?.type == .texture) {
            _emissiveMapTexture = texture(for: .emission, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: true)
            _materialFlags.insert(.hasEmissiveMap)
        }
        if(mdlMaterial.property(with: .clearcoat)?.type == .texture) {
            _clearcoatMapTexture = texture(for: .clearcoat, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasClearcoatMap)
            _materialFlags.insert(.hasClearcoat)
        }
        if(mdlMaterial.property(with: .clearcoatGloss)?.type == .texture) {
            _clearcoatRoughnessMapTexture = texture(for: .clearcoatGloss, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasClearcoatRoughnessMap)
            _materialFlags.insert(.hasClearcoatGlossMap)
            _materialFlags.insert(.hasClearcoat)
        }
        if(mdlMaterial.property(with: .sheenTint)?.type == .texture) {
            _sheenColorMapTexture = texture(for: .sheenTint, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: true)
            _materialFlags.insert(.hasSheenColorMap)
            _materialFlags.insert(.hasSheen)
        }
        if(mdlMaterial.property(with: .sheen)?.type == .texture) {
            _sheenIntensityMapTexture = texture(for: .sheen, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
            _materialFlags.insert(.hasSheenIntensityMap)
            _materialFlags.insert(.hasSheen)
        }
    }
    
    private func createMaterial(_ mdlMaterial: MDLMaterial) {
        if let albedo = mdlMaterial.property(with: .baseColor)?.float3Value {
            _material.baseColor = albedo
        }
        if let metallic = mdlMaterial.property(with: .metallic)?.floatValue {
            _material.metallicScalar = metallic
        }
        if let roughness = mdlMaterial.property(with: .roughness)?.floatValue {
            _material.roughnessScalar = roughness
        }
        if let ao = mdlMaterial.property(with: .ambientOcclusion)?.floatValue {
            _material.aoScalar = ao
        }
        if let clearcoat = mdlMaterial.property(with: .clearcoat)?.floatValue {
            _material.clearcoatFactor = clearcoat
            if clearcoat > 0.0 {
                _materialFlags.insert(.hasClearcoat)
            }
        }
        if let clearcoatGloss = mdlMaterial.property(with: .clearcoatGloss)?.floatValue {
            _material.clearcoatRoughness = max(0.0, min(1.0, 1.0 - clearcoatGloss))
            _materialFlags.insert(.hasClearcoat)
        }
        if let sheenValue = mdlMaterial.property(with: .sheen)?.floatValue {
            _material.sheenColor = SIMD3<Float>(repeating: sheenValue)
            if sheenValue > 0.0 {
                _materialFlags.insert(.hasSheen)
            }
        }
        if let sheenTint = mdlMaterial.property(with: .sheenTint) {
            if sheenTint.type == .float4 {
                let tint = SIMD3<Float>(sheenTint.float4Value.x, sheenTint.float4Value.y, sheenTint.float4Value.z)
                let intensity = max(_material.sheenColor.x, max(_material.sheenColor.y, _material.sheenColor.z))
                _material.sheenColor = intensity > 0.0 ? tint * intensity : tint
                _materialFlags.insert(.hasSheen)
            } else if sheenTint.type == .float3 {
                let tint = sheenTint.float3Value
                let intensity = max(_material.sheenColor.x, max(_material.sheenColor.y, _material.sheenColor.z))
                _material.sheenColor = intensity > 0.0 ? tint * intensity : tint
                _materialFlags.insert(.hasSheen)
            }
        }
        guard let emissiveProperty = mdlMaterial.property(with: .emission) else { return }
        if emissiveProperty.type == .float4 {
            _material.emissiveColor = SIMD3<Float>(emissiveProperty.float4Value.x, emissiveProperty.float4Value.y, emissiveProperty.float4Value.z)
        } else if emissiveProperty.type == .float3 {
            _material.emissiveColor = emissiveProperty.float3Value
        } else if emissiveProperty.type == .float {
            _material.emissiveScalar = emissiveProperty.floatValue
        }
    }
    
    private func texture(for semantic: MDLMaterialSemantic,
                         in material: MDLMaterial?,
                         generateMipmaps: Bool = false,
                         textureOrigin: MTKTextureLoader.Origin,
                         sRGB: Bool) -> MTLTexture? {

        let textureLoader = MTKTextureLoader(device: Engine.Device)
        guard let materialProperty = material?.property(with: semantic) else { return nil }
        guard let sampler = materialProperty.textureSamplerValue else { return nil }
        guard let sourceTexture = sampler.texture else { return nil }
        let options: [MTKTextureLoader.Option : Any] = [
            .origin: textureOrigin as Any,
            .generateMipmaps: generateMipmaps,
            .SRGB: sRGB
        ]
        if let urlTex = sourceTexture as? MDLURLTexture, urlTex.url.isFileURL {
            return try? textureLoader.newTexture(URL: urlTex.url, options: options)
        }
        if let cg = sourceTexture.imageFromTexture()?.takeUnretainedValue() {
            return try? textureLoader.newTexture(cgImage: cg, options: options)
        }
        return try? textureLoader.newTexture(texture: sourceTexture, options: options)
    }
    
    private func createIndexBuffer() {
        if(_indices.count > 0) {
            _indexBuffer = Engine.Device.makeBuffer(bytes: _indices, length: UInt32.stride(_indices.count), options: [])
        }
    }
}

class NoMesh: MCMesh {}

class TriangleMesh: MCMesh {
    override func createMesh() {
        addVertex(position: SIMD3<Float>( 0, 1,0), color: SIMD4<Float>(1,0,0,1), texCoord: SIMD2<Float>(0.5,0.0))
        addVertex(position: SIMD3<Float>(-1,-1,0), color: SIMD4<Float>(0,1,0,1), texCoord: SIMD2<Float>(0.0,1.0))
        addVertex(position: SIMD3<Float>( 1,-1,0), color: SIMD4<Float>(0,0,1,1), texCoord: SIMD2<Float>(1.0,1.0))
    }
}

class CubeMesh: MCMesh {
    override func createMesh() {
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(1.0, 0.5, 0.0, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>(-1.0,-1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 0.5, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0, 1.0), color: SIMD4<Float>(0.0, 0.5, 1.0, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0,-1.0), color: SIMD4<Float>(1.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>(-1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 0.0, 0.5, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0,-1.0), color: SIMD4<Float>(0.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0,-1.0), color: SIMD4<Float>(0.0, 0.5, 1.0, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0,-1.0), color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0, 1.0), color: SIMD4<Float>(1.0, 0.5, 1.0, 1.0), normal: SIMD3<Float>( 1, 0, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0,-1.0), color: SIMD4<Float>(0.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0,-1.0), color: SIMD4<Float>(0.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0,-1.0), color: SIMD4<Float>(0.5, 1.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>(-1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 1, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0, 1.0), color: SIMD4<Float>(1.0, 0.5, 0.0, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(0.5, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0,-1.0), color: SIMD4<Float>(0.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>( 1.0,-1.0, 1.0), color: SIMD4<Float>(1.0, 1.0, 0.5, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>(-1.0,-1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(1.0, 0.5, 1.0, 1.0), normal: SIMD3<Float>( 0,-1, 0))
        addVertex(position: SIMD3<Float>( 1.0, 1.0,-1.0), color: SIMD4<Float>(1.0, 0.5, 0.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(0.5, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>(-1.0, 1.0,-1.0), color: SIMD4<Float>(0.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>( 1.0, 1.0,-1.0), color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>( 1.0,-1.0,-1.0), color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>(-1.0,-1.0,-1.0), color: SIMD4<Float>(1.0, 0.5, 1.0, 1.0), normal: SIMD3<Float>( 0, 0,-1))
        addVertex(position: SIMD3<Float>(-1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 0.5, 0.0, 1.0), normal: SIMD3<Float>( 0, 0, 1))
        addVertex(position: SIMD3<Float>(-1.0,-1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 0.0, 1.0), normal: SIMD3<Float>( 0, 0, 1))
        addVertex(position: SIMD3<Float>( 1.0,-1.0, 1.0), color: SIMD4<Float>(0.5, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 0, 1))
        addVertex(position: SIMD3<Float>( 1.0, 1.0, 1.0), color: SIMD4<Float>(1.0, 1.0, 0.5, 1.0), normal: SIMD3<Float>( 0, 0, 1))
        addVertex(position: SIMD3<Float>(-1.0, 1.0, 1.0), color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 0, 1))
        addVertex(position: SIMD3<Float>( 1.0,-1.0, 1.0), color: SIMD4<Float>(1.0, 0.0, 1.0, 1.0), normal: SIMD3<Float>( 0, 0, 1))
    }
}

class FullscreenQuadMesh: MCMesh {
    override func createMesh() {
        addSimpleVertex(position: SIMD3<Float>(-1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>(-1,  1, 0))
        addSimpleVertex(position: SIMD3<Float>(-1,  1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1,  1, 0))
    }
}

class PlaneMesh: MCMesh {
    override func createMesh() {
        let normal = SIMD3<Float>(0, 1, 0)
        let tangent = SIMD3<Float>(1, 0, 0)
        let bitangent = SIMD3<Float>(0, 0, 1)
        let color = SIMD4<Float>(1, 1, 1, 1)
        let uvScale: Float = 10.0
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
        addVertex(position: SIMD3<Float>( 1, 0, -1), color: color, texCoord: SIMD2<Float>(1, 0) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
        addVertex(position: SIMD3<Float>(-1, 0,  1), color: color, texCoord: SIMD2<Float>(0, 1) * uvScale, normal: normal, tangent: tangent, bitangent: bitangent)
    }
}

class CubemapMesh: MCMesh {
    override func createMesh() {
        // +X Face
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
        // -X Face
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        // +Y Face
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        // -Y Face
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        // +Z Face
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,1,1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,1))
        // -Z Face
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,1,-1))
        addSimpleVertex(position: SIMD3<Float>(-1,-1,-1))
        addSimpleVertex(position: SIMD3<Float>(1,-1,-1))
    }
}

private func forceResolveMaterialTextures(_ material: MDLMaterial, baseFolder: URL) {
    let semantics: [MDLMaterialSemantic] = [
        .baseColor,
        .tangentSpaceNormal,
        .metallic,
        .roughness,
        .ambientOcclusion,
        .emission,
        .clearcoat,
        .clearcoatGloss,
        .sheen,
        .sheenTint
    ]
    for sem in semantics {
        guard let prop = material.property(with: sem) else { continue }
        guard prop.type == .texture, let sampler = prop.textureSamplerValue else { continue }
        guard let mdlTex = sampler.texture else { continue }
        var candidateURL: URL? = nil
        if let urlTex = mdlTex as? MDLURLTexture {
            let url = urlTex.url
            candidateURL = url.isFileURL ? url : nil
            if candidateURL == nil {}
        } else if !mdlTex.name.isEmpty {
            candidateURL = baseFolder.appendingPathComponent(mdlTex.name)
        }
        if candidateURL == nil, let str = prop.stringValue, !str.isEmpty {
            candidateURL = baseFolder.appendingPathComponent(str)
        }
        if candidateURL == nil, let url = prop.urlValue {
            candidateURL = url.isFileURL ? url : nil
        }
        guard let url = candidateURL else { continue }
        let finalURL: URL
        if url.isFileURL {
            finalURL = url
        } else {
            finalURL = baseFolder.appendingPathComponent(url.path)
        }
        if FileManager.default.fileExists(atPath: finalURL.path) {
            let texName = finalURL.lastPathComponent
            let fixed = MDLURLTexture(url: finalURL, name: texName)
            let fixedSampler = MDLTextureSampler()
            fixedSampler.texture = fixed
            prop.textureSamplerValue = fixedSampler
        }
    }
}
