//
//  IBLShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/27/26.
//

#include <metal_stdlib>
#include "PBR.metal"
using namespace metal;

struct CubemapVertex {
    float3 position [[ attribute(0) ]];
};

struct CubemapRasterizerData {
    float4 position [[ position ]];
    float3 localPosition;
};

vertex CubemapRasterizerData vertex_cubemap(const CubemapVertex vert [[ stage_in ]],
                                            constant float4x4 &vp [[ buffer(1) ]]) {
    CubemapRasterizerData rd;
    float3 pos = vert.position;
    rd.localPosition = pos;
    rd.position = vp * float4(pos, 1.0);
    return rd;
}

fragment float4 fragment_cubemap(CubemapRasterizerData rd [[ stage_in ]],
                                 texture2d<float> hdri [[ texture(0) ]],
                                 sampler samp [[ sampler(0) ]]) {
    float3 dir = normalize(rd.localPosition);
    float2 uv;
    uv.x = atan2(dir.z, dir.x) / (2.0 * PBR::PI) + 0.5;
    uv.y = asin(dir.y) / PBR::PI + 0.5;
    float3 color = hdri.sample(samp, uv).rgb;
    return float4(color, 1.0);
}

// Real SH basis (Schmidt semi-normalized) for l <= 2
inline float Y00(float3 n) { return 0.282095f; }
inline float Y1m1(float3 n) { return 0.488603f * n.y; }
inline float Y10(float3 n)  { return 0.488603f * n.z; }
inline float Y11(float3 n)  { return 0.488603f * n.x; }
inline float Y2m2(float3 n) { return 1.092548f * n.x * n.y; }
inline float Y2m1(float3 n) { return 1.092548f * n.y * n.z; }
inline float Y20(float3 n)  { return 0.315392f * (3.0f * n.z * n.z - 1.0f); }
inline float Y21(float3 n)  { return 1.092548f * n.x * n.z; }
inline float Y22(float3 n)  { return 0.546274f * (n.x * n.x - n.y * n.y); }

inline void evalSH9(float3 n, thread float b[9]) {
    b[0] = Y00(n);
    b[1] = Y1m1(n); b[2] = Y10(n); b[3] = Y11(n);
    b[4] = Y2m2(n); b[5] = Y2m1(n); b[6] = Y20(n); b[7] = Y21(n); b[8] = Y22(n);
}

fragment float4 fragment_irradiance(CubemapRasterizerData rd [[ stage_in ]],
                                    constant float3 *shCoeffs [[ buffer(0) ]]) {
    float3 N = normalize(rd.localPosition);
    // Evaluate SH basis for direction N
    float b[9];
    evalSH9(N, b);
    // Accumulate irradiance from pre-convolved SH coefficients (already scaled by cosine kernel per band)
    float3 irradiance = float3(0.0);
    for (int i = 0; i < 9; ++i) {
        irradiance += shCoeffs[i] * b[i];
    }
    return float4(irradiance, 1.0);
}
