//
//  SkysphereShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

struct SkyboxRasterizerData {
    float4 position [[ position ]];
    float3 direction;
};

vertex SkyboxRasterizerData vertex_skybox(const SimpleVertex vert [[ stage_in ]], constant SceneConstants &sceneConstants [[ buffer(1) ]], constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    SkyboxRasterizerData rd;
    float3 pos = vert.position;
    rd.direction = pos;
    rd.position = sceneConstants.projectionMatrix * sceneConstants.skyViewMatrix * float4(pos, 1.0);
    return rd;
}

fragment float4 fragment_skybox(SkyboxRasterizerData rd [[ stage_in ]], sampler sampler [[ sampler(0) ]], texturecube<float> skyboxTexture [[ texture(10) ]]) {
    float3 dir = normalize(rd.direction);
    return float4(skyboxTexture.sample(sampler, dir, level(0.0)).rgb, 1.0);
}
