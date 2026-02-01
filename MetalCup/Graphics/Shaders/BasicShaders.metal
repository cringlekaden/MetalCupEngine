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
                              constant MetalCupMaterial &material [[ buffer(1) ]],
                              constant int &lightCount [[ buffer(2) ]],
                              constant LightData *lightDatas [[ buffer(3) ]],
                              sampler sam [[ sampler(0) ]],
                              texture2d<float> albedoMap [[ texture(0) ]],
                              texture2d<float> normalMap [[ texture(1) ]],
                              texture2d<float> metallicMap [[ texture(2) ]],
                              texture2d<float> roughnessMap [[ texture(3) ]],
                              texture2d<float> metalRoughness [[ texture(4) ]],
                              texture2d<float> aoMap [[ texture(5) ]],
                              texture2d<float> emissiveMap [[ texture(6) ]],
                              texturecube<float> irradianceMap [[ texture(7) ]],
                              texturecube<float> prefilteredMap [[ texture(8) ]],
                              texture2d<float> brdf_lut [[ texture(9) ]])  {
    // ------------------------------------------------------------
    // Fallback scalars (material factors)
    // ------------------------------------------------------------
    float3 albedo = material.baseColor;
    float metallic = material.metallicScalar;
    float roughness = material.roughnessScalar;
    float ao = material.aoScalar;
    
    // ------------------------------------------------------------
    // Texture overrides (textures multiply factors)
    // ------------------------------------------------------------
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasBaseColorMap)) {
        albedo = albedoMap.sample(sam, rd.texCoord).rgb;
    }
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasMetalRoughnessMap)) {
        float3 mr = metalRoughness.sample(sam, rd.texCoord).rgb;
        roughness = mr.g;
        metallic  = mr.b;
    } else {
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasMetallicMap)) {
            metallic = metallicMap.sample(sam, rd.texCoord).r;
        }
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasRoughnessMap)) {
            roughness = roughnessMap.sample(sam, rd.texCoord).r;
        }
    }
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasAOMap)) {
        ao = aoMap.sample(sam, rd.texCoord).r;
    }
    // Clamp for stability (prevents NaNs / LUT edge artifacts / fireflies)
    metallic = clamp(metallic, 0.0, 1.0);
    roughness = clamp(roughness, 0.04, 1.0); // 0.0 can cause sparkle/instability
    albedo = max(albedo, float3(0.0));
    
    // ------------------------------------------------------------
    // Normal mapping
    // ------------------------------------------------------------
    float3 N = normalize(rd.surfaceNormal);
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasNormalMap)) {
        float3 T = normalize(rd.surfaceTangent);
        // Orthonormalize T to N (helps robustness)
        T = normalize(T - N * dot(N, T));
        float3 B = normalize(cross(N, T));
        float3x3 TBN = float3x3(T, B, N);
        float3 tangentNormal = normalMap.sample(sam, rd.texCoord).xyz * 2.0 - 1.0;
        N = normalize(TBN * tangentNormal);
    }

    // ------------------------------------------------------------
    // View vector
    // ------------------------------------------------------------
    float3 V = normalize(rd.toCamera);
    float NdotV = max(dot(N, V), 0.001);

    // ------------------------------------------------------------
    // Unlit shortcut
    // ------------------------------------------------------------
    if (hasFlag(material.flags, MetalCupMaterialFlags::IsUnlit)) {
        float3 emissive = material.emissiveColor;
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasEmissiveMap)) {
            float3 e = emissiveMap.sample(sam, rd.texCoord).rgb;
            float luminance = dot(e, float3(0.2126, 0.7152, 0.0722));
            float mask = step(0.04, luminance);
            emissive = e * mask;
        }
        emissive *= material.emissiveScalar;
        return float4(albedo + emissive, 1.0);
    }

    // ------------------------------------------------------------
    // Base reflectivity
    // ------------------------------------------------------------
    float3 F0 = mix(float3(0.04), albedo, metallic);

    // ------------------------------------------------------------
    // Direct lighting (simplified lambert for now)
    // ------------------------------------------------------------
    float3 Lo = float3(0.0);
    for (int i = 0; i < lightCount; i++) {
        float3 L = normalize(lightDatas[i].position - rd.worldPosition);
        float distance = length(lightDatas[i].position - rd.worldPosition);
        float attenuation = 1.0 / max(distance * distance, 1e-4);
        float3 radiance = lightDatas[i].color * attenuation;
        float NdotL = max(dot(N, L), 0.0);
        // Simple lambert for now (restore full BRDF later)
        Lo += (albedo / PBR::PI) * radiance * NdotL;
    }

    // ------------------------------------------------------------
    // Diffuse IBL
    // ------------------------------------------------------------
    float3 irradiance = irradianceMap.sample(sam, N).rgb;
    float3 diffuseIBL = irradiance * (albedo / PBR::PI);

    // Energy conservation split
    float3 F_ibl = PBR::FresnelSchlick(NdotV, F0);
    float3 kS = F_ibl;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    // Apply AO to ambient only
    float3 ambient = kD * diffuseIBL * ao;

    // ------------------------------------------------------------
    // Specular IBL (prefilter + BRDF LUT)
    // ------------------------------------------------------------
    float3 R = normalize(reflect(-V, N));
    float maxMip = float(prefilteredMap.get_num_mip_levels()) - 1.0;
    float mipLevel = roughness * maxMip;
    float3 prefilteredColor = prefilteredMap.sample(sam, R, level(mipLevel)).rgb;
    float2 brdfUV = float2(NdotV, roughness);
    brdfUV = clamp(brdfUV, 0.001, 0.999);
    float2 brdfSample = brdf_lut.sample(sam, brdfUV).rg;
    float3 specularIBL = prefilteredColor * (F_ibl * brdfSample.x + brdfSample.y);

    // Optional: Apply AO to specular too (specular occlusion)
    // specularIBL *= ao;

    // ------------------------------------------------------------
    // Emissive (additive, unlit)
    // ------------------------------------------------------------
    float3 emissive = material.emissiveColor;
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasEmissiveMap)) {
        float3 e = emissiveMap.sample(sam, rd.texCoord).rgb;
        float luminance = dot(e, float3(0.2126, 0.7152, 0.0722));
        float mask = step(0.04, luminance);
        emissive = e * mask;
    }
    emissive *= material.emissiveScalar;

    // ------------------------------------------------------------
    // Combine
    // ------------------------------------------------------------
    float3 color = Lo + ambient + specularIBL + emissive;
    return float4(color, 1.0);
}
