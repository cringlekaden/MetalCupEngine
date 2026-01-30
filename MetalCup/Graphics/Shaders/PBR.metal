//
//  PBR.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//


#ifndef PBR_METAL
#define PBR_METAL

#include <metal_stdlib>
using namespace metal;

class PBR {
public:
    
    constant static constexpr float PI = 3.14159265359;
    
    static float DistributionGGX(float3 N, float3 H, float roughness) {
        float a      = roughness * roughness;
        float a2     = a * a;
        float NdotH  = max(dot(N, H), 0.0);
        float NdotH2 = NdotH * NdotH;
        float denom = (NdotH2 * (a2 - 1.0) + 1.0);
        return a2 / max(PI * denom * denom, 1e-5);
    }

    static float GeometrySchlickGGX(float NdotV, float roughness) {
        float r = roughness + 1.0;
        float k = (r * r) / 8.0;
        return NdotV / (NdotV * (1.0 - k) + k);
    }

    static float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
        float NdotV = max(dot(N, V), 0.0);
        float NdotL = max(dot(N, L), 0.0);
        float ggxV = GeometrySchlickGGX(NdotV, roughness);
        float ggxL = GeometrySchlickGGX(NdotL, roughness);
        return ggxV * ggxL;
    }

    static float3 FresnelSchlick(float cosTheta, float3 F0) {
        return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
    }
};

#endif
