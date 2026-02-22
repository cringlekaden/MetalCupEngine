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
    private let shaders: ShaderLibrary
    private let vertexDescriptors: VertexDescriptorLibrary
    private let preferences: Preferences
    private let device: MTLDevice

    public init(shaders: ShaderLibrary, vertexDescriptors: VertexDescriptorLibrary, preferences: Preferences, device: MTLDevice) {
        self.shaders = shaders
        self.vertexDescriptors = vertexDescriptors
        self.preferences = preferences
        self.device = device
        super.init()
    }

    public func build() {
        if !library.isEmpty { return }

        // Binding Contract (mesh pipelines):
        // Vertex buffers:
        //  - [[buffer(0)]] Vertex (pos/color/uv/normal/tangent.xyz + tangent.w handedness)
        //  - [[buffer(1)]] SceneConstants (SceneConstants)
        //  - [[buffer(2)]] ModelConstants (ModelConstants) for non-instanced
        //  - [[buffer(3)]] InstanceData (InstanceData) for instanced
        // Fragment buffers:
        //  - [[buffer(1)]] Material (MetalCupMaterial)
        //  - [[buffer(2)]] RendererSettings (RendererSettings)
        //  - [[buffer(3)]] LightCount (int)
        //  - [[buffer(4)]] LightData (LightData[])
        //  - [[buffer(7)]] ShadowConstants (ShadowConstants)
        // Textures/samplers:
        //  - See Shared.metal FragmentTextureIndex / FragmentSamplerIndex

        library[.HDRBasic] = buildPipeline(label: "HDRBasic") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.BasicVertex]
            descriptor.fragmentFunction = shaders[.BasicFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Default]
        }

        library[.HDRInstanced] = buildPipeline(label: "HDRInstanced") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.InstancedVertex]
            descriptor.fragmentFunction = shaders[.BasicFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Default]
        }

        library[.PickID] = buildPipeline(label: "PickID") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r32Uint
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.PickInstancedVertex]
            descriptor.fragmentFunction = shaders[.PickFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Default]
        }

        library[.DepthPrepass] = buildPipeline(label: "DepthPrepass") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.DepthOnlyVertex]
            descriptor.fragmentFunction = nil
            descriptor.vertexDescriptor = vertexDescriptors[.Default]
        }

        library[.DepthPrepassInstanced] = buildPipeline(label: "DepthPrepassInstanced") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.DepthOnlyInstancedVertex]
            descriptor.fragmentFunction = nil
            descriptor.vertexDescriptor = vertexDescriptors[.Default]
        }

        library[.Skybox] = buildPipeline(label: "Skybox") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.depthAttachmentPixelFormat = preferences.defaultDepthPixelFormat
            descriptor.vertexFunction = shaders[.SkyboxVertex]
            descriptor.fragmentFunction = shaders[.SkyboxFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.Final] = buildPipeline(label: "Final") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.defaultColorPixelFormat
            descriptor.vertexFunction = shaders[.FinalVertex]
            descriptor.fragmentFunction = shaders[.FinalFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.Cubemap] = buildPipeline(label: "Cubemap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = shaders[.CubemapVertex]
            descriptor.fragmentFunction = shaders[.CubemapFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.ProceduralSkyCubemap] = buildPipeline(label: "ProceduralSkyCubemap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = shaders[.CubemapVertex]
            descriptor.fragmentFunction = shaders[.ProceduralSkyFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.IrradianceMap] = buildPipeline(label: "IrradianceMap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = shaders[.CubemapVertex]
            descriptor.fragmentFunction = shaders[.IrradianceFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.PrefilteredMap] = buildPipeline(label: "PrefilteredMap") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.vertexFunction = shaders[.CubemapVertex]
            descriptor.fragmentFunction = shaders[.PrefilteredFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.rasterSampleCount = 1
            descriptor.inputPrimitiveTopology = .triangle
        }

        library[.BRDF] = buildPipeline(label: "BRDF") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .rg16Float
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.BRDFFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.BloomExtract] = buildPipeline(label: "BloomExtract") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.BloomExtractFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.BloomDownsample] = buildPipeline(label: "BloomDownsample") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.BloomDownsampleFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.BloomBlurH] = buildPipeline(label: "BloomBlurH") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.BlurHFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.BloomBlurV] = buildPipeline(label: "BloomBlurV") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.BlurVFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.GridOverlay] = buildPipeline(label: "GridOverlay") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = preferences.HDRPixelFormat
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.GridFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.SelectionOutline] = buildPipeline(label: "SelectionOutline") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r8Unorm
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.OutlineFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }

        library[.HDRILuminance] = buildPipeline(label: "HDRILuminance") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .r16Float
            descriptor.vertexFunction = shaders[.FSQuadVertex]
            descriptor.fragmentFunction = shaders[.HDRILuminanceFragment]
            descriptor.vertexDescriptor = vertexDescriptors[.Simple]
        }
    }

    override subscript(_ type: RenderPipelineStateType) -> MTLRenderPipelineState {
        return library[type]!.renderPipelineState
    }
}

protocol RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState! { get }
}

class BasicRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState!
    init(label: String, descriptor: MTLRenderPipelineDescriptor, device: MTLDevice) {
        descriptor.label = label
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
    }
}

extension RenderPipelineStateLibrary {
    private func buildPipeline(label: String, configure: (MTLRenderPipelineDescriptor) -> Void) -> RenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        configure(descriptor)
        return BasicRenderPipelineState(label: label, descriptor: descriptor, device: device)
    }
}
