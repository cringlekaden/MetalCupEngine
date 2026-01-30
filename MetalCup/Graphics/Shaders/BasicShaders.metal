//
//  BasicShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "PBR.metal"
#include "Shared.metal"
using namespace metal;

vertex RasterizerData vertex_basic(const Vertex vert [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                   constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    RasterizerData rd;
    float4 worldPosition = modelConstants.modelMatrix * float4(vert.position, 1.0);
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    rd.color = vert.color;
    rd.texCoord = vert.texCoord;
    rd.totalGameTime = sceneConstants.totalGameTime;
    rd.worldPosition = worldPosition.xyz;
    rd.surfaceNormal = normalize(modelConstants.modelMatrix * float4(vert.normal, 0.0)).xyz;
    rd.surfaceTangent = normalize(modelConstants.modelMatrix * float4(vert.tangent, 0.0)).xyz;
    rd.surfaceBitangent = normalize(modelConstants.modelMatrix * float4(vert.bitangent, 0.0)).xyz;
    rd.toCamera = sceneConstants.cameraPosition - worldPosition.xyz;
    return rd;
}

fragment float4 fragment_basic(RasterizerData rd [[ stage_in ]],
                              constant PBRMaterial &material [[ buffer(1) ]],
                              constant int &lightCount [[ buffer(2) ]],
                              constant LightData *lightDatas [[ buffer(3) ]],
                              sampler sam [[ sampler(0) ]],
                              texture2d<float> albedoMap [[ texture(0) ]],
                              texture2d<float> normalMap [[ texture(1) ]],
                              texture2d<float> metallicMap [[ texture(2) ]],
                              texture2d<float> roughnessMap [[ texture(3) ]],
                              texture2d<float> aoMap [[ texture(4) ]],
                              texturecube<float> irradianceMap [[ texture(5) ]])  {
    // --- Sample textures ---
    float3 albedo = pow(albedoMap.sample(sam, rd.texCoord).rgb, float3(2.2));
    float metallic = metallicMap.sample(sam, rd.texCoord).r;
    float roughness = roughnessMap.sample(sam, rd.texCoord).r;
    float ao = aoMap.sample(sam, rd.texCoord).r;

    // --- Normal mapping (tangent space) ---
    float3 N = normalize(rd.surfaceNormal);
    float3 T = normalize(rd.surfaceTangent);
    float3 B = normalize(rd.surfaceBitangent);
    float3x3 TBN = float3x3(T, B, N);
    float3 tangentNormal = normalMap.sample(sam, rd.texCoord).xyz * 2.0 - 1.0;
    N = normalize(TBN * tangentNormal);

    // --- View vector ---
    float3 V = normalize(rd.toCamera);

    // --- Base reflectivity ---
    float3 F0 = mix(float3(0.04), albedo, metallic);
    float3 Lo = float3(0.0);

    // --- Direct lighting ---
    for(int i = 0; i < lightCount; i++) {
        float3 L = normalize(lightDatas[i].position - rd.worldPosition);
        float3 H = normalize(V + L);

        float distance = length(lightDatas[i].position - rd.worldPosition);
        float attenuation = 1.0 / (distance * distance);
        float3 radiance = lightDatas[i].color * attenuation;

        float NDF = PBR::DistributionGGX(N, H, roughness);
        float G = PBR::GeometrySmith(N, V, L, roughness);
        float3 F = PBR::FresnelSchlick(max(dot(H, V), 0.0), F0);

        float3 numerator = NDF * G * F;
        float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 1e-5;
        float3 specular = numerator / denom;

        float3 kS = F;
        float3 kD = (1.0 - kS) * (1.0 - metallic);

        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * albedo / PBR::PI + specular) * radiance * NdotL;
    }

    // --- Diffuse IBL
    float3 irradiance = irradianceMap.sample(sam, N).rgb;
    float3 diffuseIBL = irradiance * albedo / PBR::PI;
    diffuseIBL *= ao;
    float3 color = diffuseIBL + Lo;

    // --- Tonemap + gamma ---
    color = color / (color + float3(1.0));
    color = pow(color, float3(1.0 / 2.2));
    return float4(color, 1.0);
}
