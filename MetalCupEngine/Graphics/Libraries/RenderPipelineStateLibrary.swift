/// RenderPipelineStateLibrary.swift
/// Defines the RenderPipelineStateLibrary types and helpers for the engine.
/// Created by Kaden Cringle.

import MetalKit

public enum RenderPipelineStateType {
    case HDRBasic
    case HDRInstanced
    case PickID
    case DepthPrepass
    case DepthPrepassInstanced
    case Skybox
    case Final
    case Cubemap
    case IrradianceMap
    case PrefilteredMap
    case BRDF
    case BloomExtract
    case BloomDownsample
    case BloomBlurH
    case BloomBlurV
    case GridOverlay
    case SelectionOutline
    case ProceduralSkyCubemap
    case HDRILuminance
}

public final class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    private var library: [RenderPipelineStateType: RenderPipelineState] = [:]

    public func build() {
        if !library.isEmpty { return }

        // Binding Contract (mesh pipelines):
        // Vertex buffers:
        //  - [[buffer(0)]] Vertex (pos/color/uv/normal/tangent/bitangent)
        //  - [[buffer(1)]] SceneConstants (SceneConstants)
        //  - [[buffer(2)]] ModelConstants (ModelConstants) for non-instanced
        //  - [[buffer(3)]] InstanceData (InstanceData) for instanced
        // Fragment buffers:
        //  - [[buffer(1)]] Material (MetalCupMaterial)
        //  - [[buffer(2)]] RendererSettings (RendererSettings)
        //  - [[buffer(3)]] LightCount (int)
        //  - [[buffer(4)]] LightData (LightData[])
        // Textures/samplers:
        //  - See Shared.metal FragmentTextureIndex / FragmentSamplerIndex

        library[.HDRBasic] = buildPipeline(label: "HDRBasic") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.BasicVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        }

        library[.HDRInstanced] = buildPipeline(label: "HDRInstanced") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.InstancedVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BasicFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        }

        library[.PickID] = buildPipeline(label: "PickID") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r32Uint
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.PickInstancedVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.PickFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        }

        library[.DepthPrepass] = buildPipeline(label: "DepthPrepass") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.DepthOnlyVertex]
            descriptor.fragmentFunction = nil
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        }

        library[.DepthPrepassInstanced] = buildPipeline(label: "DepthPrepassInstanced") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.DepthOnlyInstancedVertex]
            descriptor.fragmentFunction = nil
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Default]
        }

        library[.Skybox] = buildPipeline(label: "Skybox") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.Final] = buildPipeline(label: "Final") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.defaultColorPixelFormat
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        }

        library[.Cubemap] = buildPipeline(label: "Cubemap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.CubemapFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.ProceduralSkyCubemap] = buildPipeline(label: "ProceduralSkyCubemap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.ProceduralSkyFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.IrradianceMap] = buildPipeline(label: "IrradianceMap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.IrradianceFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.PrefilteredMap] = buildPipeline(label: "PrefilteredMap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = Graphics.Shaders[.CubemapVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.PrefilteredFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.BRDF] = buildPipeline(label: "BRDF") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .rg16Float
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FSQuadVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BRDFFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        }

        library[.BloomExtract] = buildPipeline(label: "BloomExtract") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BloomExtractFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.BloomDownsample] = buildPipeline(label: "BloomDownsample") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BloomDownsampleFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.BloomBlurH] = buildPipeline(label: "BloomBlurH") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlurHFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.BloomBlurV] = buildPipeline(label: "BloomBlurV") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlurVFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.GridOverlay] = buildPipeline(label: "GridOverlay") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.GridFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.SelectionOutline] = buildPipeline(label: "SelectionOutline") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.OutlineFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.HDRILuminance] = buildPipeline(label: "HDRILuminance") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r32Float
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = Graphics.Shaders[.FSQuadVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.HDRILuminanceFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Simple]
        }
    }

    override subscript(_ type: RenderPipelineStateType) -> MTLRenderPipelineState {
        guard let state = library[type]?.renderPipelineState else {
            fatalError("Missing render pipeline state: \(type)")
        }
        return state
    }

    private func buildPipeline(label: String, configure: (MTLRenderPipelineDescriptor) -> Void) -> RenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        configure(descriptor)
        return RenderPipelineState(renderPipelineDescriptor: descriptor)
    }
}

final class RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState!

    init(renderPipelineDescriptor: MTLRenderPipelineDescriptor) {
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch let error as NSError {
            EngineLog.shared.logError("Failed to create render pipeline state: \(error)", category: .renderer)
        }
    }
}
