//
//  MeshLibrary.swift
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

import MetalKit
import Foundation
import ModelIO

enum MeshType {
    case None
    case Triangle
    case Quad
    case Cube
    case Cubemap
    case Sphere
    case Skybox
    case Sofa
    case FullscreenQuad
    case PBRTest
    case DamagedHelmet
}

class MeshLibrary: Library<MeshType, Mesh> {
    
    private var _library: [MeshType: Mesh] = [:]
    
    override func fillLibrary() {
        _library[.None] = NoMesh()
        _library[.Triangle] = TriangleMesh()
        _library[.Quad] = Mesh(modelName: "quad")
        _library[.Cube] = CubeMesh()
        _library[.Cubemap] = CubemapMesh()
        _library[.Sphere] = Mesh(modelName: "sphere")
        _library[.Skybox] = CubemapMesh()
        _library[.Sofa] = Mesh(modelName: "sofa_03_2k")
        _library[.FullscreenQuad] = FullscreenQuadMesh()
        _library[.PBRTest] = Mesh(modelName: "PBR_test", ext: "usdz")
        _library[.DamagedHelmet] = Mesh(modelName: "Helmet", ext: "usdz")
    }
    
    override subscript(_ type: MeshType)->Mesh {
        return _library[type]!
    }
}

class Mesh {
    
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
    
    init(modelName: String, ext: String = "obj") {
        createMeshFromModel(modelName, ext: ext)
    }
    
    func createMesh() {}
    
    private func createBuffer() {
        if(_vertices.count > 0){
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count), options: [])
        } else if(_simpleVertices.count > 0) {
            _simpleVertexBuffer = Engine.Device.makeBuffer(bytes: _simpleVertices, length: SimpleVertex.stride(_simpleVertices.count), options: [])
        }
    }
    
    private func createMeshFromModel(_ modelName: String, ext: String) {
        guard let assetURL = Bundle.main.url(forResource: modelName, withExtension: ext) else {
            fatalError("Asset \(modelName) does not exist...")
        }
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Basic])
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
        do{
            mdlMeshes = try MTKMesh.newMeshes(asset: asset, device: Engine.Device).modelIOMeshes
        } catch {
            print("ERROR::LOADING_MESH::__\(modelName)__::\(error)")
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
                print("ERROR::LOADING_MESH::__\(modelName)__::\(error)")
            }
        }
        let mtkMesh = mtkMeshes[0]
        let mdlMesh = mdlMeshes[0]
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
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
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder, material: MetalCupMaterial? = nil, albedoMapTextureType: TextureType = .None, normalMapTextureType: TextureType = .None, metallicMapTextureType: TextureType = .None, roughnessMapTextureType: TextureType = .None, mrMapTextureType: TextureType = .None, aoMapTextureType: TextureType = .None, emissiveMapTextureType: TextureType = .None) {
        if(_vertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            if(_submeshes.count > 0) {
                for submesh in _submeshes {
                    submesh.applyTextures(renderCommandEncoder: renderCommandEncoder, albedoMapTextureType: albedoMapTextureType, normalMapTextureType: normalMapTextureType, metallicMapTextureType: metallicMapTextureType, roughnessMapTextureType: roughnessMapTextureType, mrMapTextureType: mrMapTextureType, aoMapTextureType: aoMapTextureType, emissiveMapTextureType: emissiveMapTextureType)
                    submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer, indexBufferOffset: submesh.indexBufferOffset, instanceCount: _instanceCount)
                }
            } else {
                renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
                renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _vertices.count, instanceCount: _instanceCount)
            }
        } else if(_simpleVertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_simpleVertexBuffer, offset: 0, index: 0)
            renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
            renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _simpleVertices.count, instanceCount: _instanceCount)
        }
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
        createTexture(mdlSubmesh.material!)
        createMaterial(mdlSubmesh.material!)
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder, albedoMapTextureType: TextureType, normalMapTextureType: TextureType, metallicMapTextureType: TextureType, roughnessMapTextureType: TextureType, mrMapTextureType: TextureType, aoMapTextureType: TextureType, emissiveMapTextureType: TextureType) {
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        let albedoMapTexture = albedoMapTextureType == .None ? _albedoMapTexture : Assets.Textures[albedoMapTextureType]
        renderCommandEncoder.setFragmentTexture(albedoMapTexture, index: 0)
        let normalMapTexture = normalMapTextureType == .None ? _normalMapTexture : Assets.Textures[normalMapTextureType]
        renderCommandEncoder.setFragmentTexture(normalMapTexture, index: 1)
        let metallicMapTexture = metallicMapTextureType == .None ? _metallicMapTexture : Assets.Textures[metallicMapTextureType]
        renderCommandEncoder.setFragmentTexture(metallicMapTexture, index: 2)
        let roughnessMapTexture = roughnessMapTextureType == .None ? _roughnessMapTexture : Assets.Textures[roughnessMapTextureType]
        renderCommandEncoder.setFragmentTexture(roughnessMapTexture, index: 3)
        let mrMapTexture = mrMapTextureType == .None ? _mrMapTexture : Assets.Textures[mrMapTextureType]
        renderCommandEncoder.setFragmentTexture(mrMapTexture, index: 4)
        let aoMapTexture = aoMapTextureType == .None ? _aoMapTexture : Assets.Textures[aoMapTextureType]
        renderCommandEncoder.setFragmentTexture(aoMapTexture, index: 5)
        let emissiveMapTexture = emissiveMapTextureType == .None ? _emissiveMapTexture : Assets.Textures[emissiveMapTextureType]
        renderCommandEncoder.setFragmentTexture(emissiveMapTexture, index: 6)
        renderCommandEncoder.setFragmentTexture(Assets.Textures[.IrradianceCubemap], index: 7)
        renderCommandEncoder.setFragmentTexture(Assets.Textures[.PrefilteredCubemap], index: 8)
        renderCommandEncoder.setFragmentTexture(Assets.Textures[.BRDF_LUT], index: 9)
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: MetalCupMaterial?) {
        var material: MetalCupMaterial = customMaterial ?? _material
        material.flags = _materialFlags.rawValue
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

class NoMesh: Mesh {}

class TriangleMesh: Mesh {
    override func createMesh() {
        addVertex(position: SIMD3<Float>( 0, 1,0), color: SIMD4<Float>(1,0,0,1), texCoord: SIMD2<Float>(0.5,0.0))
        addVertex(position: SIMD3<Float>(-1,-1,0), color: SIMD4<Float>(0,1,0,1), texCoord: SIMD2<Float>(0.0,1.0))
        addVertex(position: SIMD3<Float>( 1,-1,0), color: SIMD4<Float>(0,0,1,1), texCoord: SIMD2<Float>(1.0,1.0))
    }
}

class CubeMesh: Mesh {
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

class FullscreenQuadMesh: Mesh {
    override func createMesh() {
        addSimpleVertex(position: SIMD3<Float>(-1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>(-1,  1, 0))
        addSimpleVertex(position: SIMD3<Float>(-1,  1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1, -1, 0))
        addSimpleVertex(position: SIMD3<Float>( 1,  1, 0))
    }
}

class CubemapMesh: Mesh {
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
        .emission
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
