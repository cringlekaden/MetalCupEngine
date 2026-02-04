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
    
    static float radicalInverse_VdC(uint bits) {
        bits = (bits << 16u) | (bits >> 16u);
        bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
        bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
        bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
        bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
        return float(bits) * 2.3283064365386963e-10; // / 2^32
    }

    static float2 hammersley(uint i, uint N) {
        return float2(float(i) / float(N), radicalInverse_VdC(i));
    }

    static float hash11(float n) { return fract(sin(n) * 43758.5453123); }

    static float2 hash22(float3 p) {
        float n1 = dot(p, float3(12.9898,78.233,37.719));
        float n2 = dot(p, float3(39.3467,11.1351,83.1559));
        return fract(sin(float2(n1, n2)) * 43758.5453123);
    }

    static void buildOrthonormalBasis(float3 N, thread float3 &T, thread float3 &B) {
        float sign = copysign(1.0, N.z);
        float a = -1.0 / (sign + N.z);
        float b = N.x * N.y * a;
        T = float3(1.0 + sign * N.x * N.x * a, sign * b, -sign * N.x);
        B = float3(b, sign + N.y * N.y * a, -N.y);
    }

    static float3 cosineSampleHemisphere(float2 Xi) {
        float r = sqrt(Xi.x);
        float phi = 2.0 * PBR::PI * Xi.y;
        float x = r * cos(phi);
        float z = r * sin(phi);
        float y = sqrt(max(0.0, 1.0 - Xi.x));
        return float3(x, y, z);
    }

    static float3 importanceSampleGGX(float2 Xi, float roughness, float3 N) {
        float a = roughness * roughness;
        float phi = 2.0 * PBR::PI * Xi.x;
        float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        float3 H;
        H.x = cos(phi) * sinTheta;
        H.y = sin(phi) * sinTheta;
        H.z = cosTheta;
        float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
        float3 T = normalize(cross(up, N));
        float3 B = cross(N, T);
        return normalize(T * H.x + B * H.y + N * H.z);
    }
    
    static float2 integrateBRDF(float NdotV, float roughness, uint sampleCount) {
        float3 V = float3(sqrt(1.0 - NdotV * NdotV), 0.0, NdotV);
        float A = 0.0;
        float B = 0.0;
        float3 N = float3(0.0, 0.0, 1.0);
        for(uint i = 0; i < sampleCount; ++i) {
            float2 Xi = hammersley(i, sampleCount);
            float3 H = importanceSampleGGX(Xi, roughness, N);
            float3 L = normalize(2.0 * dot(V, H) * H - V);
            float NdotL = max(L.z, 0.0);
            float NdotH = max(H.z, 0.0);
            float VdotH = max(dot(V, H), 0.0);
            if(NdotL > 0.0) {
                float G = GeometrySmith(N, V, L, roughness);
                float G_Vis = (G * VdotH) / (NdotH * NdotV);
                float Fc = pow(1.0 - VdotH, 5.0);
                A += (1.0 - Fc) * G_Vis;
                B += Fc * G_Vis;
            }
        }
        return float2(A, B) / float(sampleCount);
    }
};

#endif
