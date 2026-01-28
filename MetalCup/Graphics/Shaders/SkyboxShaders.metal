//
//  SkysphereShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/26/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

vertex RasterizerData vertex_skysphere(const Vertex vert [[ stage_in ]], constant SceneConstants &sceneConstants [[ buffer(1) ]], constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    RasterizerData rd;
    float4 worldPosition = modelConstants.modelMatrix * float4(vert.position, 1.0);
    rd.position = sceneConstants.projectionMatrix * sceneConstants.skyViewMatrix * worldPosition;
    rd.texCoord = vert.texCoord;
    return rd;
}

fragment float4 fragment_skysphere(RasterizerData rd [[ stage_in ]], sampler sampler2d [[ sampler(0) ]], texture2d<float> skySphereTexture [[ texture(10) ]]) {
    float2 texCoord = rd.texCoord;
    float4 color = skySphereTexture.sample(sampler2d, texCoord, level(0));
    return color;
}
