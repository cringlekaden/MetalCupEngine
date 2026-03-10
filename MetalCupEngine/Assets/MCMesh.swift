/// MCMesh.swift
/// Defines the MCMesh types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit
import Foundation
import ModelIO

private struct BakedMeshVertexDocument: Codable {
    let position: [Float]
    let normal: [Float]?
    let tangent: [Float]?
    let texCoord0: [Float]?
    let jointIndices: [UInt16]?
    let jointWeights: [Float]?
}

private struct BakedMeshSubmeshDocument: Codable {
    let name: String
    let materialIndex: Int
    let indices: [UInt32]
}

private struct BakedMeshDocument: Codable {
    let schemaVersion: Int
    let name: String
    let hasSkinning: Bool
    let vertices: [BakedMeshVertexDocument]
    let submeshes: [BakedMeshSubmeshDocument]
}

private let textureMapFlags: MetalCupMaterialFlags = [
    .hasBaseColorMap,
    .hasNormalMap,
    .hasMetallicMap,
    .hasRoughnessMap,
    .hasMetalRoughnessMap,
    .hasORMMap,
    .hasAOMap,
    .hasEmissiveMap,
    .hasClearcoatMap,
    .hasClearcoatRoughnessMap,
    .hasSheenColorMap,
    .hasSheenIntensityMap,
    .hasClearcoatGlossMap
]

private struct ResolvedPBRTextures {
    let albedo: MTLTexture
    let normal: MTLTexture
    let metallic: MTLTexture
    let roughness: MTLTexture
    let metalRoughness: MTLTexture
    let orm: MTLTexture
    let ao: MTLTexture
    let emissive: MTLTexture
    let clearcoat: MTLTexture
    let clearcoatRoughness: MTLTexture
    let sheenColor: MTLTexture
    let sheenIntensity: MTLTexture
    let flags: MetalCupMaterialFlags
}

private func resolveTexture(
    _ texture: MTLTexture?,
    fallback: MTLTexture,
    fallbackLibrary: FallbackTextureLibrary
) -> (MTLTexture, Bool) {
    let resolved = texture ?? fallback
    let isFallback = fallbackLibrary.isFallbackTexture(resolved)
    return (resolved, !isFallback)
}

private func resolvePBRTextures(
    fallback: FallbackTextureLibrary,
    assetManager: AssetManager?,
    albedoHandle: AssetHandle?,
    normalHandle: AssetHandle?,
    metallicHandle: AssetHandle?,
    roughnessHandle: AssetHandle?,
    mrHandle: AssetHandle?,
    ormHandle: AssetHandle?,
    aoHandle: AssetHandle?,
    emissiveHandle: AssetHandle?,
    embeddedAlbedo: MTLTexture?,
    embeddedNormal: MTLTexture?,
    embeddedMetallic: MTLTexture?,
    embeddedRoughness: MTLTexture?,
    embeddedMetalRoughness: MTLTexture?,
    embeddedORM: MTLTexture?,
    embeddedAO: MTLTexture?,
    embeddedEmissive: MTLTexture?,
    embeddedClearcoat: MTLTexture?,
    embeddedClearcoatRoughness: MTLTexture?,
    embeddedSheenColor: MTLTexture?,
    embeddedSheenIntensity: MTLTexture?,
    useEmbeddedTextures: Bool
) -> ResolvedPBRTextures {
    let albedoSource = albedoHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedAlbedo : nil)
    let (albedo, hasAlbedo) = resolveTexture(albedoSource, fallback: fallback.whiteRGBA, fallbackLibrary: fallback)

    let normalSource = normalHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedNormal : nil)
    let (normal, hasNormal) = resolveTexture(normalSource, fallback: fallback.flatNormal, fallbackLibrary: fallback)

    let mrSource = mrHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedMetalRoughness : nil)
    let (metalRoughness, hasMetalRoughness) = resolveTexture(mrSource, fallback: fallback.metalRoughness, fallbackLibrary: fallback)

    let ormSource = ormHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedORM : nil)
    let (orm, hasORM) = resolveTexture(ormSource, fallback: fallback.orm, fallbackLibrary: fallback)

    let metallicSource = metallicHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedMetallic : nil)
    let (metallic, hasMetallicRaw) = resolveTexture(metallicSource, fallback: fallback.blackRGBA, fallbackLibrary: fallback)

    let roughnessSource = roughnessHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedRoughness : nil)
    let (roughness, hasRoughnessRaw) = resolveTexture(roughnessSource, fallback: fallback.whiteRGBA, fallbackLibrary: fallback)

    let aoSource = aoHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedAO : nil)
    let (ao, hasAO) = resolveTexture(aoSource, fallback: fallback.aoMap, fallbackLibrary: fallback)

    let emissiveSource = emissiveHandle.flatMap { assetManager?.texture(handle: $0) }
        ?? (useEmbeddedTextures ? embeddedEmissive : nil)
    let (emissive, hasEmissive) = resolveTexture(emissiveSource, fallback: fallback.emissive, fallbackLibrary: fallback)

    let clearcoatSource = useEmbeddedTextures ? embeddedClearcoat : nil
    let (clearcoat, hasClearcoat) = resolveTexture(clearcoatSource, fallback: fallback.blackRGBA, fallbackLibrary: fallback)

    let clearcoatRoughnessSource = useEmbeddedTextures ? embeddedClearcoatRoughness : nil
    let (clearcoatRoughness, hasClearcoatRoughness) = resolveTexture(clearcoatRoughnessSource, fallback: fallback.whiteRGBA, fallbackLibrary: fallback)

    let sheenColorSource = useEmbeddedTextures ? embeddedSheenColor : nil
    let (sheenColor, hasSheenColor) = resolveTexture(sheenColorSource, fallback: fallback.blackRGBA, fallbackLibrary: fallback)

    let sheenIntensitySource = useEmbeddedTextures ? embeddedSheenIntensity : nil
    let (sheenIntensity, hasSheenIntensity) = resolveTexture(sheenIntensitySource, fallback: fallback.blackRGBA, fallbackLibrary: fallback)

    var flags = MetalCupMaterialFlags()
    if hasAlbedo { flags.insert(.hasBaseColorMap) }
    if hasNormal { flags.insert(.hasNormalMap) }
    if hasORM {
        flags.insert(.hasORMMap)
    } else if hasMetalRoughness {
        flags.insert(.hasMetalRoughnessMap)
    } else {
        if hasMetallicRaw { flags.insert(.hasMetallicMap) }
        if hasRoughnessRaw { flags.insert(.hasRoughnessMap) }
    }
    if hasAO { flags.insert(.hasAOMap) }
    if hasEmissive { flags.insert(.hasEmissiveMap) }
    if hasClearcoat { flags.insert(.hasClearcoatMap) }
    if hasClearcoatRoughness { flags.insert(.hasClearcoatRoughnessMap) }
    if hasSheenColor { flags.insert(.hasSheenColorMap) }
    if hasSheenIntensity { flags.insert(.hasSheenIntensityMap) }

    return ResolvedPBRTextures(
        albedo: albedo,
        normal: normal,
        metallic: metallic,
        roughness: roughness,
        metalRoughness: metalRoughness,
        orm: orm,
        ao: ao,
        emissive: emissive,
        clearcoat: clearcoat,
        clearcoatRoughness: clearcoatRoughness,
        sheenColor: sheenColor,
        sheenIntensity: sheenIntensity,
        flags: flags
    )
}

public class MCMesh {

    private let device: MTLDevice
    private let graphics: Graphics
    private weak var assetManager: AssetManager?

    private var _vertices: [Vertex] = []
    private var _simpleVertices: [SimpleVertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _simpleVertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submeshes: [Submesh] = []
    private var hasJointIndexStream: Bool = false
    private var hasJointWeightStream: Bool = false
    private var localBoundsCenter = SIMD3<Float>(repeating: 0)
    private var localBoundsRadius: Float = 1_000.0

    var boundsCenter: SIMD3<Float> { localBoundsCenter }
    var boundsRadius: Float { localBoundsRadius }
    public var editorBoundsCenter: SIMD3<Float> { localBoundsCenter }
    public var editorBoundsRadius: Float { localBoundsRadius }
    public var vertexCount: Int { _vertexCount }

    init(device: MTLDevice, graphics: Graphics, assetManager: AssetManager? = nil) {
        self.device = device
        self.graphics = graphics
        self.assetManager = assetManager
        createMesh()
        createBuffer()
    }
    
    init(assetURL: URL, device: MTLDevice, graphics: Graphics, assetManager: AssetManager? = nil) {
        self.device = device
        self.graphics = graphics
        self.assetManager = assetManager
        createMeshFromURL(assetURL, name: assetURL.lastPathComponent)
    }
    
    func createMesh() {}
    
    private func createBuffer() {
        if(_vertices.count > 0){
            _vertexBuffer = device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count), options: [])
            hasJointIndexStream = true
            hasJointWeightStream = true
            updateBoundsFromVertices()
        } else if(_simpleVertices.count > 0) {
            _simpleVertexBuffer = device.makeBuffer(bytes: _simpleVertices, length: SimpleVertex.stride(_simpleVertices.count), options: [])
            hasJointIndexStream = false
            hasJointWeightStream = false
            updateBoundsFromSimpleVertices()
        }
    }
    
    private func createMeshFromURL(_ assetURL: URL, name: String) {
        if assetURL.pathExtension.lowercased() == "mcmesh" {
            createMeshFromBakedURL(assetURL, name: name)
            return
        }
        let descriptor = MTKModelIOVertexDescriptorFromMetal(graphics.vertexDescriptors[.Default])
        (descriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (descriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeColor
        (descriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (descriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (descriptor.attributes[4] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        (descriptor.attributes[5] as! MDLVertexAttribute).name = MDLVertexAttributeJointIndices
        (descriptor.attributes[6] as! MDLVertexAttribute).name = MDLVertexAttributeJointWeights
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: assetURL, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        var mdlMeshes: [MDLMesh] = []
        do {
            mdlMeshes = try MTKMesh.newMeshes(asset: asset, device: device).modelIOMeshes
        } catch {
            EngineLoggerContext.log(
                "Mesh load failed \(name): \(error)",
                level: .error,
                category: .assets
            )
        }
        guard !mdlMeshes.isEmpty else {
            EngineLoggerContext.log(
                "Mesh load failed \(name): no ModelIO meshes found.",
                level: .error,
                category: .assets
            )
            return
        }
        var mtkMeshes: [MTKMesh] = []
        for mdlMesh in mdlMeshes {
            let texcoordAttributeName = preferredTexcoordAttributeName(for: mdlMesh)
#if DEBUG
            if texcoordAttributeName != MDLVertexAttributeTextureCoordinate {
                EngineLoggerContext.log(
                    "Using fallback texcoord attribute '\(texcoordAttributeName)' for mesh \(name).",
                    level: .debug,
                    category: .assets
                )
            }
#endif
            if let meshDescriptor = descriptor.copy() as? MDLVertexDescriptor,
               let attributes = meshDescriptor.attributes as? [MDLVertexAttribute],
               attributes.count > 2 {
                attributes[2].name = texcoordAttributeName
                mdlMesh.vertexDescriptor = meshDescriptor
            } else {
                mdlMesh.vertexDescriptor = descriptor
            }
            if !hasVertexAttribute(mdlMesh, name: MDLVertexAttributeNormal) {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
            }
            let hasTexcoords = hasVertexAttribute(mdlMesh, name: texcoordAttributeName)
            let hasTangents = hasVertexAttribute(mdlMesh, name: MDLVertexAttributeTangent)
            if hasTexcoords && !hasTangents {
                mdlMesh.addTangentBasis(
                    forTextureCoordinateAttributeNamed: texcoordAttributeName,
                    normalAttributeNamed: MDLVertexAttributeNormal,
                    tangentAttributeNamed: MDLVertexAttributeTangent
                )
            }
#if DEBUG
            validateFiniteVertexPositions(mdlMesh, name: name)
#endif
            do {
                let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
                mtkMeshes.append(mtkMesh)
            } catch {
                EngineLoggerContext.log(
                    "Mesh load failed \(name): \(error)",
                    level: .error,
                    category: .assets
                )
            }
        }
        guard let mtkMesh = mtkMeshes.first, let mdlMesh = mdlMeshes.first else {
            EngineLoggerContext.log(
                "Mesh load failed \(name): no Metal meshes created.",
                level: .error,
                category: .assets
            )
            return
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        hasJointIndexStream = hasVertexAttribute(mdlMesh, name: MDLVertexAttributeJointIndices)
        hasJointWeightStream = hasVertexAttribute(mdlMesh, name: MDLVertexAttributeJointWeights)
#if DEBUG
        EngineLoggerContext.log(
            "Mesh runtime load path=\(assetURL.path)\nvertexCount=\(_vertexCount)\nhasJointIndices=\(hasJointIndexStream)\nhasJointWeights=\(hasJointWeightStream)",
            level: .debug,
            category: .assets
        )
#endif
        updateBoundsFromModelMesh(mdlMesh)
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            if let mdlSubmesh = (mdlMesh.submeshes?[i] as? MDLSubmesh) {
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, device: device, graphics: graphics, assetManager: assetManager)
                addSubmesh(submesh)
            }
        }
    }

    private func preferredTexcoordAttributeName(for mesh: MDLMesh) -> String {
        if hasVertexAttribute(mesh, name: MDLVertexAttributeTextureCoordinate) {
            return MDLVertexAttributeTextureCoordinate
        }
        let candidates = [
            "\(MDLVertexAttributeTextureCoordinate)0",
            "texcoord0",
            "TEXCOORD_0",
            "uv0"
        ]
        for name in candidates {
            if hasVertexAttribute(mesh, name: name) {
                return name
            }
        }
        return MDLVertexAttributeTextureCoordinate
    }

    private func hasVertexAttribute(_ mesh: MDLMesh, name: String) -> Bool {
        guard let data = mesh.vertexAttributeData(forAttributeNamed: name) else { return false }
        return data.stride > 0
    }

    private func createMeshFromBakedURL(_ assetURL: URL, name: String) {
        do {
            let data = try Data(contentsOf: assetURL)
            let document = try JSONDecoder().decode(BakedMeshDocument.self, from: data)
            guard !document.vertices.isEmpty else {
                EngineLoggerContext.log(
                    "Mesh load failed \(name): baked mesh has no vertices.",
                    level: .error,
                    category: .assets
                )
                return
            }

            _vertices.removeAll(keepingCapacity: true)
            _simpleVertices.removeAll(keepingCapacity: true)
            _submeshes.removeAll(keepingCapacity: true)
            _vertices.reserveCapacity(document.vertices.count)

            for sourceVertex in document.vertices {
                guard sourceVertex.position.count >= 3 else { continue }
                let position = SIMD3<Float>(sourceVertex.position[0], sourceVertex.position[1], sourceVertex.position[2])
                let normal = sourceVertex.normal.flatMap { value -> SIMD3<Float>? in
                    guard value.count >= 3 else { return nil }
                    return SIMD3<Float>(value[0], value[1], value[2])
                } ?? SIMD3<Float>(0, 1, 0)
                let tangent = sourceVertex.tangent.flatMap { value -> SIMD4<Float>? in
                    guard value.count >= 4 else { return nil }
                    return SIMD4<Float>(value[0], value[1], value[2], value[3])
                } ?? SIMD4<Float>(1, 0, 0, 1)
                let texCoord = sourceVertex.texCoord0.flatMap { value -> SIMD2<Float>? in
                    guard value.count >= 2 else { return nil }
                    return SIMD2<Float>(value[0], value[1])
                } ?? SIMD2<Float>(0, 0)
                let jointIndices = sourceVertex.jointIndices.flatMap { value -> SIMD4<UInt16>? in
                    guard value.count >= 4 else { return nil }
                    return SIMD4<UInt16>(value[0], value[1], value[2], value[3])
                } ?? SIMD4<UInt16>(0, 0, 0, 0)
                let jointWeights = sourceVertex.jointWeights.flatMap { value -> SIMD4<Float>? in
                    guard value.count >= 4 else { return nil }
                    return SIMD4<Float>(value[0], value[1], value[2], value[3])
                } ?? SIMD4<Float>(1, 0, 0, 0)

                addVertex(
                    position: position,
                    color: SIMD4<Float>(1, 1, 1, 1),
                    texCoord: texCoord,
                    normal: normal,
                    tangent: tangent,
                    jointIndices: jointIndices,
                    jointWeights: jointWeights
                )
            }

            _vertexCount = _vertices.count
            createBuffer()

            for submesh in document.submeshes where !submesh.indices.isEmpty {
                addSubmesh(
                    Submesh(
                        indices: submesh.indices,
                        device: device,
                        graphics: graphics,
                        assetManager: assetManager
                    )
                )
            }

            hasJointIndexStream = document.hasSkinning
            hasJointWeightStream = document.hasSkinning
#if DEBUG
            EngineLoggerContext.log(
                "Baked mesh runtime load path=\(assetURL.path)\nvertexCount=\(_vertexCount)\nsubmeshes=\(_submeshes.count)\nhasJointIndices=\(hasJointIndexStream)\nhasJointWeights=\(hasJointWeightStream)",
                level: .debug,
                category: .assets
            )
#endif
        } catch {
            EngineLoggerContext.log(
                "Mesh load failed \(name): unable to decode baked mesh (\(error.localizedDescription)).",
                level: .error,
                category: .assets
            )
        }
    }

    private func updateBoundsFromVertices() {
        guard !_vertices.isEmpty else { return }
        var center = SIMD3<Float>(repeating: 0)
        for vertex in _vertices {
            center += vertex.position
        }
        center /= Float(_vertices.count)
        var maxDistanceSquared: Float = 0
        for vertex in _vertices {
            maxDistanceSquared = max(maxDistanceSquared, simd_length_squared(vertex.position - center))
        }
        localBoundsCenter = center
        localBoundsRadius = max(0.001, sqrt(maxDistanceSquared))
    }

    private func updateBoundsFromSimpleVertices() {
        guard !_simpleVertices.isEmpty else { return }
        var center = SIMD3<Float>(repeating: 0)
        for vertex in _simpleVertices {
            center += vertex.position
        }
        center /= Float(_simpleVertices.count)
        var maxDistanceSquared: Float = 0
        for vertex in _simpleVertices {
            maxDistanceSquared = max(maxDistanceSquared, simd_length_squared(vertex.position - center))
        }
        localBoundsCenter = center
        localBoundsRadius = max(0.001, sqrt(maxDistanceSquared))
    }

    private func updateBoundsFromModelMesh(_ mesh: MDLMesh) {
        guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition),
              positions.stride > 0 else { return }
        let stride = positions.stride
        let count = mesh.vertexCount
        guard count > 0 else { return }
        let base = positions.dataStart
        var center = SIMD3<Float>(repeating: 0)
        for index in 0..<count {
            let ptr = base.advanced(by: index * stride).assumingMemoryBound(to: Float.self)
            center += SIMD3<Float>(ptr[0], ptr[1], ptr[2])
        }
        center /= Float(count)
        var maxDistanceSquared: Float = 0
        for index in 0..<count {
            let ptr = base.advanced(by: index * stride).assumingMemoryBound(to: Float.self)
            let position = SIMD3<Float>(ptr[0], ptr[1], ptr[2])
            maxDistanceSquared = max(maxDistanceSquared, simd_length_squared(position - center))
        }
        localBoundsCenter = center
        localBoundsRadius = max(0.001, sqrt(maxDistanceSquared))
    }

#if DEBUG
    private func validateFiniteVertexPositions(_ mesh: MDLMesh, name: String) {
        guard let attribute = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition) else { return }
        guard attribute.format == .float3 || attribute.format == .float4 else { return }
        let stride = attribute.stride
        guard stride > 0 else { return }
        let count = mesh.vertexCount
        let base = attribute.dataStart
        for index in 0..<count {
            let ptr = base.advanced(by: index * stride).assumingMemoryBound(to: Float.self)
            let x = ptr[0]
            let y = ptr[1]
            let z = ptr[2]
            if !x.isFinite || !y.isFinite || !z.isFinite {
                MC_ASSERT(false, "Mesh \(name) contains non-finite vertex positions.")
                break
            }
        }
    }
#endif
    
    func setInstanceCount(_ count: Int) {
        self._instanceCount = count
    }
    
    func addSubmesh(_ submesh: Submesh) {
        _submeshes.append(submesh)
    }
    
    func addVertex(position: SIMD3<Float>,
                   color: SIMD4<Float> = SIMD4<Float>(1, 0, 1, 1),
                   texCoord: SIMD2<Float> = SIMD2<Float>(0, 0),
                   normal: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                   tangent: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 1),
                   jointIndices: SIMD4<UInt16> = SIMD4<UInt16>(repeating: 0),
                   jointWeights: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 0)) {
        _vertices.append(
            Vertex(position: position,
                   color: color,
                   texCoord: texCoord,
                   normal: normal,
                   tangent: tangent,
                   jointIndices: jointIndices,
                   jointWeights: jointWeights)
        )
    }
    
    func addSimpleVertex(position: SIMD3<Float>) {
        _simpleVertices.append(SimpleVertex(position: position))
    }

    func hasValidSkinningVertexStreams() -> Bool {
        guard _vertexBuffer != nil, _vertexCount > 0 else { return false }
        return hasJointIndexStream && hasJointWeightStream
    }

    func skinningStreamDebugState() -> String {
        "vertexBuffer=\(_vertexBuffer != nil) vertexCount=\(_vertexCount) jointIndices=\(hasJointIndexStream) jointWeights=\(hasJointWeightStream)"
    }

    func totalIndexCount() -> Int {
        _submeshes.reduce(into: 0) { count, submesh in
            count += submesh.indexCount
        }
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        frameContext: RendererFrameContext,
                        material: MetalCupMaterial? = nil,
                        submeshMaterialHandles: [AssetHandle?]? = nil,
                        albedoMapHandle: AssetHandle? = nil,
                        normalMapHandle: AssetHandle? = nil,
                        metallicMapHandle: AssetHandle? = nil,
                        roughnessMapHandle: AssetHandle? = nil,
                        mrMapHandle: AssetHandle? = nil,
                        ormMapHandle: AssetHandle? = nil,
                        aoMapHandle: AssetHandle? = nil,
                        emissiveMapHandle: AssetHandle? = nil,
                        useEmbeddedMaterial: Bool = true) {
        if(_vertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: VertexBufferIndex.vertices)
            if(_submeshes.count > 0) {
                let hasOverrides = material != nil
                    || albedoMapHandle != nil
                    || normalMapHandle != nil
                    || metallicMapHandle != nil
                    || roughnessMapHandle != nil
                    || mrMapHandle != nil
                    || aoMapHandle != nil
                    || emissiveMapHandle != nil
                for (index, submesh) in _submeshes.enumerated() {
                    if !hasOverrides,
                       let bindings = resolveSubmeshMaterialBindings(at: index, handles: submeshMaterialHandles) {
                        let textureFlags = submesh.applyTextures(
                            renderCommandEncoder: renderCommandEncoder,
                            frameContext: frameContext,
                            albedoMapHandle: bindings.albedoMapHandle,
                            normalMapHandle: bindings.normalMapHandle,
                            metallicMapHandle: bindings.metallicMapHandle,
                            roughnessMapHandle: bindings.roughnessMapHandle,
                            mrMapHandle: bindings.mrMapHandle,
                            ormMapHandle: bindings.ormMapHandle,
                            aoMapHandle: bindings.aoMapHandle,
                            emissiveMapHandle: bindings.emissiveMapHandle,
                            useEmbeddedTextures: false
                        )
                        submesh.applyMaterials(
                            renderCommandEncoder: renderCommandEncoder,
                            customMaterial: bindings.material,
                            useEmbeddedMaterial: false,
                            textureFlags: textureFlags,
                            materialFallback: false
                        )
                    } else {
                        let textureFlags = submesh.applyTextures(
                            renderCommandEncoder: renderCommandEncoder,
                            frameContext: frameContext,
                            albedoMapHandle: albedoMapHandle,
                            normalMapHandle: normalMapHandle,
                            metallicMapHandle: metallicMapHandle,
                            roughnessMapHandle: roughnessMapHandle,
                            mrMapHandle: mrMapHandle,
                            ormMapHandle: ormMapHandle,
                            aoMapHandle: aoMapHandle,
                            emissiveMapHandle: emissiveMapHandle,
                            useEmbeddedTextures: useEmbeddedMaterial
                        )
                        let materialFallback = !useEmbeddedMaterial && material == nil
                        submesh.applyMaterials(
                            renderCommandEncoder: renderCommandEncoder,
                            customMaterial: material,
                            useEmbeddedMaterial: useEmbeddedMaterial,
                            textureFlags: textureFlags,
                            materialFallback: materialFallback
                        )
                    }
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer, indexBufferOffset: submesh.indexBufferOffset, instanceCount: _instanceCount)
                }
            } else {
#if DEBUG
                MC_ASSERT(MetalCupMaterial.stride == MetalCupMaterial.expectedMetalStride, "MetalCupMaterial stride mismatch. Keep Swift and Metal layouts in sync.")
#endif
                if material != nil
                    || albedoMapHandle != nil
                    || normalMapHandle != nil
                    || metallicMapHandle != nil
                    || roughnessMapHandle != nil
                    || mrMapHandle != nil
                    || aoMapHandle != nil
                    || emissiveMapHandle != nil {
                    var resolvedMaterial = material ?? MetalCupMaterial()
                    let textureFlags = applyTextureOverrides(
                        renderCommandEncoder: renderCommandEncoder,
                        frameContext: frameContext,
                        albedoMapHandle: albedoMapHandle,
                        normalMapHandle: normalMapHandle,
                        metallicMapHandle: metallicMapHandle,
                        roughnessMapHandle: roughnessMapHandle,
                        mrMapHandle: mrMapHandle,
                        aoMapHandle: aoMapHandle,
                        emissiveMapHandle: emissiveMapHandle
                    )
                    resolvedMaterial = applyTextureFlags(
                        resolvedMaterial,
                        textureFlags: textureFlags,
                        materialFallback: !useEmbeddedMaterial && material == nil
                    )
                    renderCommandEncoder.setFragmentBytes(&resolvedMaterial, length: MetalCupMaterial.stride, index: FragmentBufferIndex.material)
                } else {
                    var resolvedMaterial = MetalCupMaterial()
                    let textureFlags = applyTextureOverrides(
                        renderCommandEncoder: renderCommandEncoder,
                        frameContext: frameContext,
                        albedoMapHandle: nil,
                        normalMapHandle: nil,
                        metallicMapHandle: nil,
                        roughnessMapHandle: nil,
                        mrMapHandle: nil,
                        aoMapHandle: nil,
                        emissiveMapHandle: nil
                    )
                    resolvedMaterial = applyTextureFlags(
                        resolvedMaterial,
                        textureFlags: textureFlags,
                        materialFallback: !useEmbeddedMaterial
                    )
                    renderCommandEncoder.setFragmentBytes(&resolvedMaterial, length: MetalCupMaterial.stride, index: FragmentBufferIndex.material)
                }
                renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _vertices.count, instanceCount: _instanceCount)
            }
        } else if(_simpleVertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_simpleVertexBuffer, offset: 0, index: VertexBufferIndex.vertices)
            renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: _simpleVertices.count, instanceCount: _instanceCount)
        }
    }

    private func applyTextureOverrides(renderCommandEncoder: MTLRenderCommandEncoder,
                                       frameContext: RendererFrameContext,
                                       albedoMapHandle: AssetHandle?,
                                       normalMapHandle: AssetHandle?,
                                       metallicMapHandle: AssetHandle?,
                                       roughnessMapHandle: AssetHandle?,
                                       mrMapHandle: AssetHandle?,
                                       aoMapHandle: AssetHandle?,
                                       emissiveMapHandle: AssetHandle?) -> MetalCupMaterialFlags {
        let fallback = frameContext.engineContext().fallbackTextures
        renderCommandEncoder.setFragmentSamplerState(graphics.samplerStates[.Linear], index: FragmentSamplerIndex.linear)
        renderCommandEncoder.setFragmentSamplerState(graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
        let resolved = resolvePBRTextures(
            fallback: fallback,
            assetManager: assetManager,
            albedoHandle: albedoMapHandle,
            normalHandle: normalMapHandle,
            metallicHandle: metallicMapHandle,
            roughnessHandle: roughnessMapHandle,
            mrHandle: mrMapHandle,
            ormHandle: nil,
            aoHandle: aoMapHandle,
            emissiveHandle: emissiveMapHandle,
            embeddedAlbedo: nil,
            embeddedNormal: nil,
            embeddedMetallic: nil,
            embeddedRoughness: nil,
            embeddedMetalRoughness: nil,
            embeddedORM: nil,
            embeddedAO: nil,
            embeddedEmissive: nil,
            embeddedClearcoat: nil,
            embeddedClearcoatRoughness: nil,
            embeddedSheenColor: nil,
            embeddedSheenIntensity: nil,
            useEmbeddedTextures: false
        )
        renderCommandEncoder.setFragmentTexture(resolved.albedo, index: FragmentTextureIndex.albedo)
        renderCommandEncoder.setFragmentTexture(resolved.normal, index: FragmentTextureIndex.normal)
        renderCommandEncoder.setFragmentTexture(resolved.metallic, index: FragmentTextureIndex.metallic)
        renderCommandEncoder.setFragmentTexture(resolved.roughness, index: FragmentTextureIndex.roughness)
        renderCommandEncoder.setFragmentTexture(resolved.metalRoughness, index: FragmentTextureIndex.metalRoughness)
        renderCommandEncoder.setFragmentTexture(resolved.orm, index: FragmentTextureIndex.orm)
        renderCommandEncoder.setFragmentTexture(resolved.ao, index: FragmentTextureIndex.ao)
        renderCommandEncoder.setFragmentTexture(resolved.emissive, index: FragmentTextureIndex.emissive)
        renderCommandEncoder.setFragmentTexture(resolved.clearcoat, index: FragmentTextureIndex.clearcoat)
        renderCommandEncoder.setFragmentTexture(resolved.clearcoatRoughness, index: FragmentTextureIndex.clearcoatRoughness)
        renderCommandEncoder.setFragmentTexture(resolved.sheenColor, index: FragmentTextureIndex.sheenColor)
        renderCommandEncoder.setFragmentTexture(resolved.sheenIntensity, index: FragmentTextureIndex.sheenIntensity)
        let ibl = frameContext.iblTextures()
        renderCommandEncoder.setFragmentTexture(ibl.irradiance ?? fallback.blackCubemap, index: FragmentTextureIndex.irradiance)
        renderCommandEncoder.setFragmentTexture(ibl.prefiltered ?? fallback.blackCubemap, index: FragmentTextureIndex.prefiltered)
        renderCommandEncoder.setFragmentTexture(ibl.brdfLut ?? fallback.brdfLut, index: FragmentTextureIndex.brdfLut)
        return resolved.flags
    }

    private func applyTextureFlags(_ material: MetalCupMaterial,
                                   textureFlags: MetalCupMaterialFlags,
                                   materialFallback: Bool) -> MetalCupMaterial {
        var resolved = material
        var flags = MetalCupMaterialFlags(rawValue: material.flags)
        let wantsClearcoatGloss = flags.contains(.hasClearcoatGlossMap)
        flags.subtract(textureMapFlags)
        flags.formUnion(textureFlags)
        if wantsClearcoatGloss && textureFlags.contains(.hasClearcoatRoughnessMap) {
            flags.insert(.hasClearcoatGlossMap)
        }
        if materialFallback {
            flags.insert(.usesFallbackMaterial)
        } else {
            flags.remove(.usesFallbackMaterial)
        }
        resolved.flags = flags.rawValue
        return resolved
    }

    private struct SubmeshMaterialBindings {
        let material: MetalCupMaterial
        let albedoMapHandle: AssetHandle?
        let normalMapHandle: AssetHandle?
        let metallicMapHandle: AssetHandle?
        let roughnessMapHandle: AssetHandle?
        let mrMapHandle: AssetHandle?
        let ormMapHandle: AssetHandle?
        let aoMapHandle: AssetHandle?
        let emissiveMapHandle: AssetHandle?
    }

    private func resolveSubmeshMaterialBindings(at index: Int, handles: [AssetHandle?]?) -> SubmeshMaterialBindings? {
        guard let handles,
              index < handles.count,
              let handle = handles[index],
              let assetManager,
              let materialAsset = assetManager.material(handle: handle) else { return nil }

        let material = materialAsset.buildMetalMaterial(database: assetManager.assetDatabase)
        return SubmeshMaterialBindings(
            material: material,
            albedoMapHandle: materialAsset.textures.baseColor,
            normalMapHandle: materialAsset.textures.normal,
            metallicMapHandle: materialAsset.textures.metallic,
            roughnessMapHandle: materialAsset.textures.roughness,
            mrMapHandle: materialAsset.textures.metalRoughness,
            ormMapHandle: materialAsset.textures.orm,
            aoMapHandle: materialAsset.textures.ao,
            emissiveMapHandle: materialAsset.textures.emissive
        )
    }
}

class Submesh {

    private var _indices: [UInt32] = []
    private var _indexCount: Int = 0
    public var indexCount: Int { return _indexCount }
    private let device: MTLDevice
    private let graphics: Graphics
    private weak var assetManager: AssetManager?
    
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
    
    init(indices: [UInt32], device: MTLDevice, graphics: Graphics, assetManager: AssetManager?) {
        self.device = device
        self.graphics = graphics
        self.assetManager = assetManager
        self._indices = indices
        self._indexCount = indices.count
        createIndexBuffer()
    }
    
    init(mtkSubmesh: MTKSubmesh, mdlSubmesh: MDLSubmesh, device: MTLDevice, graphics: Graphics, assetManager: AssetManager?) {
        self.device = device
        self.graphics = graphics
        self.assetManager = assetManager
        _indexBuffer = mtkSubmesh.indexBuffer.buffer
        _indexBufferOffset = mtkSubmesh.indexBuffer.offset
        _indexCount = mtkSubmesh.indexCount
        _indexType = mtkSubmesh.indexType
        _primitiveType = mtkSubmesh.primitiveType
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
                       frameContext: RendererFrameContext,
                       albedoMapHandle: AssetHandle?,
                       normalMapHandle: AssetHandle?,
                       metallicMapHandle: AssetHandle?,
                       roughnessMapHandle: AssetHandle?,
                       mrMapHandle: AssetHandle?,
                       ormMapHandle: AssetHandle?,
                       aoMapHandle: AssetHandle?,
                       emissiveMapHandle: AssetHandle?,
                       useEmbeddedTextures: Bool) -> MetalCupMaterialFlags {
        let fallback = frameContext.engineContext().fallbackTextures
        renderCommandEncoder.setFragmentSamplerState(graphics.samplerStates[.Linear], index: FragmentSamplerIndex.linear)
        renderCommandEncoder.setFragmentSamplerState(graphics.samplerStates[.LinearClamp], index: FragmentSamplerIndex.linearClamp)
        let resolved = resolvePBRTextures(
            fallback: fallback,
            assetManager: assetManager,
            albedoHandle: albedoMapHandle,
            normalHandle: normalMapHandle,
            metallicHandle: metallicMapHandle,
            roughnessHandle: roughnessMapHandle,
            mrHandle: mrMapHandle,
            ormHandle: ormMapHandle,
            aoHandle: aoMapHandle,
            emissiveHandle: emissiveMapHandle,
            embeddedAlbedo: _albedoMapTexture,
            embeddedNormal: _normalMapTexture,
            embeddedMetallic: _metallicMapTexture,
            embeddedRoughness: _roughnessMapTexture,
            embeddedMetalRoughness: _mrMapTexture,
            embeddedORM: nil,
            embeddedAO: _aoMapTexture,
            embeddedEmissive: _emissiveMapTexture,
            embeddedClearcoat: _clearcoatMapTexture,
            embeddedClearcoatRoughness: _clearcoatRoughnessMapTexture,
            embeddedSheenColor: _sheenColorMapTexture,
            embeddedSheenIntensity: _sheenIntensityMapTexture,
            useEmbeddedTextures: useEmbeddedTextures
        )
        renderCommandEncoder.setFragmentTexture(resolved.albedo, index: FragmentTextureIndex.albedo)
        renderCommandEncoder.setFragmentTexture(resolved.normal, index: FragmentTextureIndex.normal)
        renderCommandEncoder.setFragmentTexture(resolved.metallic, index: FragmentTextureIndex.metallic)
        renderCommandEncoder.setFragmentTexture(resolved.roughness, index: FragmentTextureIndex.roughness)
        renderCommandEncoder.setFragmentTexture(resolved.metalRoughness, index: FragmentTextureIndex.metalRoughness)
        renderCommandEncoder.setFragmentTexture(resolved.orm, index: FragmentTextureIndex.orm)
        renderCommandEncoder.setFragmentTexture(resolved.ao, index: FragmentTextureIndex.ao)
        renderCommandEncoder.setFragmentTexture(resolved.emissive, index: FragmentTextureIndex.emissive)
        renderCommandEncoder.setFragmentTexture(resolved.clearcoat, index: FragmentTextureIndex.clearcoat)
        renderCommandEncoder.setFragmentTexture(resolved.clearcoatRoughness, index: FragmentTextureIndex.clearcoatRoughness)
        renderCommandEncoder.setFragmentTexture(resolved.sheenColor, index: FragmentTextureIndex.sheenColor)
        renderCommandEncoder.setFragmentTexture(resolved.sheenIntensity, index: FragmentTextureIndex.sheenIntensity)
        let ibl = frameContext.iblTextures()
        renderCommandEncoder.setFragmentTexture(ibl.irradiance ?? fallback.blackCubemap, index: FragmentTextureIndex.irradiance)
        renderCommandEncoder.setFragmentTexture(ibl.prefiltered ?? fallback.blackCubemap, index: FragmentTextureIndex.prefiltered)
        renderCommandEncoder.setFragmentTexture(ibl.brdfLut ?? fallback.brdfLut, index: FragmentTextureIndex.brdfLut)
        return resolved.flags
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder,
                        customMaterial: MetalCupMaterial?,
                        useEmbeddedMaterial: Bool,
                        textureFlags: MetalCupMaterialFlags,
                        materialFallback: Bool) {
        var material: MetalCupMaterial = customMaterial ?? MetalCupMaterial()
        var flags = MetalCupMaterialFlags(rawValue: material.flags)
        if useEmbeddedMaterial {
            if customMaterial == nil {
                material = _material
                flags = MetalCupMaterialFlags(rawValue: material.flags)
            }
            if flags.isEmpty {
                flags = _materialFlags
            } else {
                flags.formUnion(_materialFlags)
            }
        }
        let wantsClearcoatGloss = flags.contains(.hasClearcoatGlossMap)
        flags.subtract(textureMapFlags)
        flags.formUnion(textureFlags)
        if wantsClearcoatGloss && textureFlags.contains(.hasClearcoatRoughnessMap) {
            flags.insert(.hasClearcoatGlossMap)
        }
        if materialFallback {
            flags.insert(.usesFallbackMaterial)
        } else {
            flags.remove(.usesFallbackMaterial)
        }
        material.flags = flags.rawValue
        renderCommandEncoder.setFragmentBytes(&material, length: MetalCupMaterial.stride, index: FragmentBufferIndex.material)
    }
    
    private func createIndexBuffer() {
        if(_indices.count > 0) {
            _indexBuffer = device.makeBuffer(bytes: _indices, length: UInt32.stride(_indices.count), options: [])
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
        let tangent = SIMD4<Float>(1, 0, 0, 1)
        let color = SIMD4<Float>(1, 1, 1, 1)
        let uvScale: Float = 10.0
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0, -1), color: color, texCoord: SIMD2<Float>(1, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>(-1, 0,  1), color: color, texCoord: SIMD2<Float>(0, 1) * uvScale, normal: normal, tangent: tangent)
    }
}

class EditorPlaneMesh: MCMesh {
    override func createMesh() {
        let normal = SIMD3<Float>(0, 1, 0)
        let tangent = SIMD4<Float>(1, 0, 0, 1)
        let color = SIMD4<Float>(1, 1, 1, 1)
        let uvScale: Float = 1.0
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0, -1), color: color, texCoord: SIMD2<Float>(1, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>(-1, 0, -1), color: color, texCoord: SIMD2<Float>(0, 0) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>(-1, 0,  1), color: color, texCoord: SIMD2<Float>(0, 1) * uvScale, normal: normal, tangent: tangent)
        addVertex(position: SIMD3<Float>( 1, 0,  1), color: color, texCoord: SIMD2<Float>(1, 1) * uvScale, normal: normal, tangent: tangent)
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
