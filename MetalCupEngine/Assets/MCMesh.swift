/// MCMesh.swift
/// Defines the MCMesh types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit
import Foundation
import ModelIO

private let textureMapFlags: MetalCupMaterialFlags = [
    .hasBaseColorMap,
    .hasNormalMap,
    .hasMetallicMap,
    .hasRoughnessMap,
    .hasMetalRoughnessMap,
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
    aoHandle: AssetHandle?,
    emissiveHandle: AssetHandle?,
    embeddedAlbedo: MTLTexture?,
    embeddedNormal: MTLTexture?,
    embeddedMetallic: MTLTexture?,
    embeddedRoughness: MTLTexture?,
    embeddedMetalRoughness: MTLTexture?,
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
    if hasMetalRoughness {
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
        } else if(_simpleVertices.count > 0) {
            _simpleVertexBuffer = device.makeBuffer(bytes: _simpleVertices, length: SimpleVertex.stride(_simpleVertices.count), options: [])
        }
    }
    
    private func createMeshFromURL(_ assetURL: URL, name: String) {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(graphics.vertexDescriptors[.Default])
        (descriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (descriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeColor
        (descriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (descriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (descriptor.attributes[4] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: assetURL, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        asset.loadTextures()
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
            let baseFolder = assetURL.deletingLastPathComponent()
            for case let sub as MDLSubmesh in (mdlMesh.submeshes ?? []) {
                if let mat = sub.material {
                    forceResolveMaterialTextures(mat, baseFolder: baseFolder)
                }
            }
            mdlMesh.vertexDescriptor = descriptor
            if !hasVertexAttribute(mdlMesh, name: MDLVertexAttributeNormal) {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
            }
            let hasTexcoords = hasVertexAttribute(mdlMesh, name: MDLVertexAttributeTextureCoordinate)
            let hasTangents = hasVertexAttribute(mdlMesh, name: MDLVertexAttributeTangent)
            if hasTexcoords && !hasTangents {
                mdlMesh.addTangentBasis(
                    forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
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
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            if let mdlSubmesh = (mdlMesh.submeshes?[i] as? MDLSubmesh) {
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, device: device, graphics: graphics, assetManager: assetManager)
                addSubmesh(submesh)
            }
        }
    }

    private func hasVertexAttribute(_ mesh: MDLMesh, name: String) -> Bool {
        guard let data = mesh.vertexAttributeData(forAttributeNamed: name) else { return false }
        return data.stride > 0
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
                   tangent: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 1)) {
        _vertices.append(Vertex(position: position, color: color, texCoord: texCoord, normal: normal, tangent: tangent))
    }
    
    func addSimpleVertex(position: SIMD3<Float>) {
        _simpleVertices.append(SimpleVertex(position: position))
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        frameContext: RendererFrameContext,
                        material: MetalCupMaterial? = nil,
                        albedoMapHandle: AssetHandle? = nil,
                        normalMapHandle: AssetHandle? = nil,
                        metallicMapHandle: AssetHandle? = nil,
                        roughnessMapHandle: AssetHandle? = nil,
                        mrMapHandle: AssetHandle? = nil,
                        aoMapHandle: AssetHandle? = nil,
                        emissiveMapHandle: AssetHandle? = nil,
                        useEmbeddedMaterial: Bool = true) {
        if(_vertexBuffer != nil) {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: VertexBufferIndex.vertices)
            if(_submeshes.count > 0) {
                for submesh in _submeshes {
                    let textureFlags = submesh.applyTextures(
                        renderCommandEncoder: renderCommandEncoder,
                        frameContext: frameContext,
                        albedoMapHandle: albedoMapHandle,
                        normalMapHandle: normalMapHandle,
                        metallicMapHandle: metallicMapHandle,
                        roughnessMapHandle: roughnessMapHandle,
                        mrMapHandle: mrMapHandle,
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
            aoHandle: aoMapHandle,
            emissiveHandle: emissiveMapHandle,
            embeddedAlbedo: nil,
            embeddedNormal: nil,
            embeddedMetallic: nil,
            embeddedRoughness: nil,
            embeddedMetalRoughness: nil,
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
        if let material = mdlSubmesh.material {
            createTexture(material)
            createMaterial(material)
        }
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
                       frameContext: RendererFrameContext,
                       albedoMapHandle: AssetHandle?,
                       normalMapHandle: AssetHandle?,
                       metallicMapHandle: AssetHandle?,
                       roughnessMapHandle: AssetHandle?,
                       mrMapHandle: AssetHandle?,
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
            aoHandle: aoMapHandle,
            emissiveHandle: emissiveMapHandle,
            embeddedAlbedo: _albedoMapTexture,
            embeddedNormal: _normalMapTexture,
            embeddedMetallic: _metallicMapTexture,
            embeddedRoughness: _roughnessMapTexture,
            embeddedMetalRoughness: _mrMapTexture,
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

        let textureLoader = MTKTextureLoader(device: device)
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
