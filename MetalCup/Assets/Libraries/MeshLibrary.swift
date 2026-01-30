import MetalKit

enum MeshType {
    case None
    case Triangle
    case Quad
    case Cube
    case Cubemap
    case Sphere
    case Skybox
    case Well
    case Sofa
    case FullscreenQuad
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
        _library[.Well] = Mesh(modelName: "well")
        _library[.Sofa] = Mesh(modelName: "sofa_03_2k")
        _library[.FullscreenQuad] = FullscreenQuadMesh()
    }
    
    override subscript(_ type: MeshType)->Mesh {
        return _library[type]!
    }
}

class Mesh {
    
    private var _vertices: [Vertex] = []
    private var _cubemapVertices: [CubemapVertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _cubemapVertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submeshes: [Submesh] = []
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(modelName: String) {
        createMeshFromModel(modelName)
    }
    
    func createMesh() {}
    
    private func createBuffer() {
        if(_vertices.count > 0){
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count), options: [])
        }
        if(_cubemapVertices.count > 0) {
            _cubemapVertexBuffer = Engine.Device.makeBuffer(bytes: _cubemapVertices, length: CubemapVertex.stride(_cubemapVertices.count), options: [])
        }
    }
    
    private func createMeshFromModel(_ modelName: String, ext: String = "obj") {
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
        let asset: MDLAsset = MDLAsset(url: assetURL, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator, preserveTopology: true, error: nil)
        asset.loadTextures()
        var mtkMeshes: [MTKMesh] = []
        var mdlMeshes: [MDLMesh] = []
        do{
            mdlMeshes = try MTKMesh.newMeshes(asset: asset, device: Engine.Device).modelIOMeshes
        } catch {
            print("ERROR::LOADING_MESH::__\(modelName)__::\(error)")
        }
        for mdlMesh in mdlMeshes {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, tangentAttributeNamed: MDLVertexAttributeTangent, bitangentAttributeNamed: MDLVertexAttributeBitangent)
            mdlMesh.vertexDescriptor = descriptor
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
    
    func addCubemapVertex(position: SIMD3<Float>) {
        _cubemapVertices.append(CubemapVertex(position: position))
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder, material: PBRMaterial? = nil, albedoMapTextureType: TextureType = .None, normalMapTextureType: TextureType = .None, metallicMapTextureType: TextureType = .None, roughnessMapTextureType: TextureType = .None, aoMapTextureType: TextureType = .None) {
        if(_vertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            if(_submeshes.count > 0) {
                for submesh in _submeshes {
                    submesh.applyTextures(renderCommandEncoder: renderCommandEncoder, albedoMapTextureType: albedoMapTextureType, normalMapTextureType: normalMapTextureType, metallicMapTextureType: metallicMapTextureType, roughnessMapTextureType: roughnessMapTextureType, aoMapTextureType: aoMapTextureType)
                    submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer, indexBufferOffset: submesh.indexBufferOffset, instanceCount: _instanceCount)
                }
            } else {
                renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
                renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _vertices.count, instanceCount: _instanceCount)
            }
        }
        if(_cubemapVertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_cubemapVertexBuffer, offset: 0, index: 0)
            renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
            renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _cubemapVertices.count, instanceCount: _instanceCount)
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
    
    private var _material = PBRMaterial()
    private var _albedoMapTexture: MTLTexture!
    private var _normalMapTexture: MTLTexture!
    private var _metallicMapTexture: MTLTexture!
    private var _roughnessMapTexture: MTLTexture!
    private var _aoMapTexture: MTLTexture!
    
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
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder, albedoMapTextureType: TextureType, normalMapTextureType: TextureType, metallicMapTextureType: TextureType, roughnessMapTextureType: TextureType, aoMapTextureType: TextureType) {
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        let albedoMapTexture = albedoMapTextureType == .None ? _albedoMapTexture : Assets.Textures[albedoMapTextureType]
        if(albedoMapTexture != nil) {
            renderCommandEncoder.setFragmentTexture(albedoMapTexture, index: 0)
        }
        let normalMapTexture = normalMapTextureType == .None ? _normalMapTexture : Assets.Textures[normalMapTextureType]
        if(normalMapTexture != nil) {
            renderCommandEncoder.setFragmentTexture(normalMapTexture, index: 1)
        }
        let metallicMapTexture = metallicMapTextureType == .None ? _metallicMapTexture : Assets.Textures[metallicMapTextureType]
        if(metallicMapTexture != nil) {
            renderCommandEncoder.setFragmentTexture(metallicMapTexture, index: 2)
        }
        let roughnessMapTexture = roughnessMapTextureType == .None ? _roughnessMapTexture : Assets.Textures[roughnessMapTextureType]
        if(roughnessMapTexture != nil) {
            renderCommandEncoder.setFragmentTexture(roughnessMapTexture, index: 3)
        }
        let aoMapTexture = aoMapTextureType == .None ? _aoMapTexture : Assets.Textures[aoMapTextureType]
        if(aoMapTexture != nil) {
            renderCommandEncoder.setFragmentTexture(aoMapTexture, index: 4)
        }
        renderCommandEncoder.setFragmentTexture(Assets.Textures[.IrradianceCubemap], index: 5)
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: PBRMaterial?) {
        var material: PBRMaterial = customMaterial ?? _material
        renderCommandEncoder.setFragmentBytes(&material, length: PBRMaterial.stride, index: 1)
    }
    
    private func createTexture(_ mdlMaterial: MDLMaterial) {
        _albedoMapTexture = texture(for: .baseColor, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: true)
        _normalMapTexture = texture(for: .tangentSpaceNormal, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
        _metallicMapTexture = texture(for: .metallic, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
        _roughnessMapTexture = texture(for: .roughness, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
        _aoMapTexture = texture(for: .ambientOcclusion, in: mdlMaterial, textureOrigin: .bottomLeft, sRGB: false)
    }
    
    private func createMaterial(_ mdlMaterial: MDLMaterial) {
        if let albedo = mdlMaterial.property(with: .baseColor)?.float3Value {
            _material.baseColor = albedo
        }
        if let metallic = mdlMaterial.property(with: .metallic)?.floatValue {
            _material.metallic = metallic
        }
        if let roughness = mdlMaterial.property(with: .roughness)?.floatValue {
            _material.roughness = roughness
        }
        if let ao = mdlMaterial.property(with: .ambientOcclusion)?.floatValue {
            _material.ao = ao
        }
    }
    
    private func texture(for semantic: MDLMaterialSemantic, in material: MDLMaterial?, textureOrigin: MTKTextureLoader.Origin, sRGB: Bool) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: Engine.Device)
        guard let materialProperty = material?.property(with: semantic) else { return nil }
        guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
        let options: [MTKTextureLoader.Option : Any] = [.origin : textureOrigin as Any, .generateMipmaps : true, .SRGB : sRGB as Any]
        let tex = try? textureLoader.newTexture(texture: sourceTexture, options: options)
        return tex
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
        addCubemapVertex(position: SIMD3<Float>(-1, -1, 0))
        addCubemapVertex(position: SIMD3<Float>( 1, -1, 0))
        addCubemapVertex(position: SIMD3<Float>(-1,  1, 0))
        addCubemapVertex(position: SIMD3<Float>(-1,  1, 0))
        addCubemapVertex(position: SIMD3<Float>( 1, -1, 0))
        addCubemapVertex(position: SIMD3<Float>( 1,  1, 0))
    }
}

class CubemapMesh: Mesh {
    override func createMesh() {
        // +X Face
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
        // -X Face
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        // +Y Face
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        // -Y Face
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        // +Z Face
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,1,1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,1))
        // -Z Face
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,1,-1))
        addCubemapVertex(position: SIMD3<Float>(-1,-1,-1))
        addCubemapVertex(position: SIMD3<Float>(1,-1,-1))
    }
}
