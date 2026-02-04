//
//  IBLShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/27/26.
//

#include <metal_stdlib>
#include "PBR.metal"
#include "Shared.metal"
using namespace metal;

vertex CubemapRasterizerData vertex_cubemap(const SimpleVertex vert [[ stage_in ]],
                                            constant float4x4 &vp [[ buffer(1) ]]) {
    CubemapRasterizerData rd;
    float3 pos = vert.position;
    rd.localPosition = pos;
    rd.position = vp * float4(pos, 1.0);
    return rd;
}

vertex SimpleRasterizerData vertex_quad(const SimpleVertex vert [[ stage_in ]]) {
    SimpleRasterizerData rd;
    rd.position = float4(vert.position, 1.0);
    rd.texCoord = vert.position.xy * 0.5 + 0.5;
    return rd;
}

fragment float4 fragment_cubemap(CubemapRasterizerData rd [[ stage_in ]],
                                 texture2d<float> hdri [[ texture(0) ]],
                                 sampler samp [[ sampler(0) ]]) {
    float3 dir = normalize(rd.localPosition);
    // φ in [0, 2π), +X at φ=0 (u=0), -Z at φ=3π/2 (u=0.75)
    float phi = atan2(-dir.z, dir.x);
    if (phi < 0.0) phi += 2.0 * PBR::PI;
    float u = phi / (2.0 * PBR::PI);
    float v = asin(dir.y) / PBR::PI + 0.5;
    float3 color = hdri.sample(samp, float2(u, v)).rgb;
    return float4(color, 1.0);
}

fragment float4 fragment_irradiance(CubemapRasterizerData rd [[ stage_in ]],
                                    texturecube<float> envMap [[ texture(0) ]],
                                    sampler samp [[ sampler(0) ]]) {
    // Output direction (normal) per texel of the irradiance cubemap face
    float3 N = normalize(rd.localPosition);
    // Build TBN to orient cosine-weighted samples around N
    float3 T, B;
    PBR::buildOrthonormalBasis(N, T, B);
    float seed = dot(N, float3(12.9898, 78.233, 37.719));
    float angle = 2.0 * PBR::PI * PBR::hash11(seed);
    float ca = cos(angle);
    float sa = sin(angle);
    float3 Trot = ca * T + sa * B;
    float3 Brot = -sa * T + ca * B;
    float2 cp = PBR::hash22(N);
    uint res = envMap.get_width();
    uint mipCount = envMap.get_num_mip_levels();
    float omegaTexel = 4.0 * PBR::PI / (6.0 * float(res) * float(res));
    const uint SAMPLE_COUNT = 2048u;
    float3 sum = float3(0.0);
    for (uint i = 0u; i < SAMPLE_COUNT; ++i) {
        float2 Xi = fract(PBR::hammersley(i, SAMPLE_COUNT) + cp);
        float3 L_local = PBR::cosineSampleHemisphere(Xi);
        float cosTheta = max(L_local.y, 1e-4);
        float3 L = normalize(Trot * L_local.x + N * L_local.y + Brot * L_local.z);
        float pdf = cosTheta / PBR::PI;
        float omegaS = 1.0 / (float(SAMPLE_COUNT) * pdf);
        float lod = 0.5 * log2(omegaS / omegaTexel);
        lod = clamp(lod, 0.0, float(mipCount - 1));
        float3 c = envMap.sample(samp, L, level(lod)).rgb;
        sum += c;
    }
    float3 irradiance = (PBR::PI / float(SAMPLE_COUNT)) * sum;
    return float4(irradiance, 1.0);
}

fragment float4 fragment_prefiltered(CubemapRasterizerData rd [[ stage_in ]],
                                     constant float &roughness [[ buffer(0) ]],
                                     texturecube<float> envMap [[ texture(0) ]],
                                     sampler samp [[ sampler(0) ]]) {
    float3 N = normalize(rd.localPosition);
    float3 R = N;
    float3 V = R;
    constexpr uint SAMPLE_COUNT = 2048u;
    float3 prefilteredColor = float3(0.0);
    float totalWeight = 0.0;
    for(uint i = 0; i < SAMPLE_COUNT; i++) {
        float2 Xi = PBR::hammersley(i, SAMPLE_COUNT);
        float3 H = PBR::importanceSampleGGX(Xi, roughness, N);
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        float NoL = max(dot(N, L), 0.0);
        if(NoL > 0.0) {
            float mipLevel = roughness * envMap.get_num_mip_levels();
            float3 sampleColor = envMap.sample(samp, float3(L.x, -L.y, L.z), level(mipLevel)).rgb;
            prefilteredColor += sampleColor * NoL;
            totalWeight += NoL;
        }
    }
    prefilteredColor /= max(totalWeight, 1e-4);
    return float4(prefilteredColor, 1.0);
}

fragment float2 fragment_brdf(SimpleRasterizerData rd [[ stage_in ]]) {
    float2 texCoord = rd.texCoord;
    float NdotV = texCoord.x;
    float roughness = texCoord.y;
    const uint SAMPLE_COUNT = 2048;
    return PBR::integrateBRDF(NdotV, roughness, SAMPLE_COUNT);
}

