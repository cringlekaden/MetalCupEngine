//
//  Shared.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#ifndef SHARED_METAL
#define SHARED_METAL

#include <metal_stdlib>
using namespace metal;

struct SimpleVertex {
    float3 position [[ attribute(0) ]];
};

struct Vertex {
    float3 position [[ attribute(0) ]];
    float4 color [[ attribute(1) ]];
    float2 texCoord [[ attribute(2) ]];
    float3 normal [[ attribute(3) ]];
    float3 tangent [[ attribute(4) ]];
    float3 bitangent [[ attribute(5) ]];
};

struct CubemapRasterizerData {
    float4 position [[ position ]];
    float3 localPosition;
};

struct RasterizerData {
    float4 position [[ position ]];
    float4 color;
    float2 texCoord;
    float totalGameTime;
    float3 worldPosition;
    float3 surfaceNormal;
    float3 surfaceTangent;
    float3 surfaceBitangent;
    float3 toCamera;
};

struct SimpleRasterizerData {
    float4 position [[ position ]];
    float2 texCoord;
};

struct ModelConstants {
    float4x4 modelMatrix;
};

struct SceneConstants {
    float totalGameTime;
    float4x4 viewMatrix;
    float4x4 skyViewMatrix;
    float4x4 projectionMatrix;
    float3 cameraPosition;
};

struct MetalCupMaterial {
    float3 baseColor;
    float metallicScalar;
    float roughnessScalar;
    float aoScalar;
    float3 emissiveColor;
    float emissiveScalar;
    uint flags;
};

enum MetalCupMaterialFlags : uint {
    HasBaseColorMap =      1 << 0,
    HasNormalMap =         1 << 1,
    HasMetallicMap =       1 << 2,
    HasRoughnessMap =      1 << 3,
    HasMetalRoughnessMap = 1 << 4,
    HasAOMap =             1 << 5,
    HasEmissiveMap =       1 << 6,
    IsUnlit =              1 << 7,
    IsDoubleSided =        1 << 8,
    AlphaMasked =          1 << 9,
    AlphaBlended =         1 << 10
};
    
inline bool hasFlag(uint flags, uint bit) { return (flags & bit) != 0u; }

struct LightData {
    float3 position;
    float3 color;
    float brightness;
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
};

#endif
