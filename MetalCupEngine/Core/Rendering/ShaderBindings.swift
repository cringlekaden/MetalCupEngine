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
    }

    enum FragmentSampler {
        static let linear = 0
        static let linearClamp = 1
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
}
