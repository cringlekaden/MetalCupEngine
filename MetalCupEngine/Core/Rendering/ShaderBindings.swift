/// ShaderBindings.swift
/// Shared shader binding indices mirrored in Metal shaders.
/// Created by Kaden Cringle

enum ShaderBindings {
    // NOTE: Keep these values in sync with Shared.metal.
    enum VertexBuffer {
        static let vertices = 0
        static let sceneConstants = 1
        static let modelConstants = 2
        static let instances = 3
        static let cubemapViewProjection = 1
    }

    enum FragmentBuffer {
        static let material = 1
        static let rendererSettings = 2
        static let lightCount = 3
        static let lightData = 4
        static let iblParams = 0
        static let skyParams = 0
        static let skyIntensity = 0
        static let outlineParams = 5
        static let gridParams = 6
        static let shadowConstants = 7
        static let lightGrid = 8
        static let lightIndexList = 9
        static let lightIndexCount = 10
        static let lightClusterParams = 11
        static let tileLightGrid = 12
        static let tileParams = 13
        static let directionalLightCount = 14
        static let directionalLightData = 15
    }

    enum FragmentTexture {
        static let albedo = 0
        static let normal = 1
        static let metallic = 2
        static let roughness = 3
        static let metalRoughness = 4
        static let ao = 5
        static let emissive = 6
        static let irradiance = 7
        static let prefiltered = 8
        static let brdfLut = 9
        static let clearcoat = 10
        static let clearcoatRoughness = 11
        static let sheenColor = 12
        static let sheenIntensity = 13
        static let skybox = 14
        static let shadowMap = 15
        static let shadowMapSample = 16
        static let orm = 17
    }

    enum FragmentSampler {
        static let linear = 0
        static let linearClamp = 1
        static let shadowCompare = 2
        static let shadowDepth = 3
    }

    enum PostProcessTexture {
        static let source = 0
        static let bloom = 1
        static let outlineMask = 2
        static let depth = 3
        static let grid = 4
    }

    enum IBLTexture {
        static let environment = 0
    }

    enum ComputeBuffer {
        static let cullLights = 0
        static let clusterParams = 1
        static let indexHeader = 2
        static let cullUniforms = 3
        static let lightGrid = 4
        static let lightIndexList = 5
        static let tileParams = 6
        static let tileLightGrid = 7
        static let tileLightIndexList = 8
        static let tileLightIndexCount = 9
        static let forwardPlusStats = 10
        static let clearUniforms = 11
        static let activeTileList = 12
        static let activeTileCount = 13
        static let dispatchThreadgroups = 14
    }

    enum ComputeTexture {
        static let depth = 0
    }
}
