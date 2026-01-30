//
//  FinalShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

struct FinalRasterizerData {
    float4 position [[ position ]];
    float2 texCoord;
};

vertex FinalRasterizerData vertex_final(const Vertex vert [[ stage_in ]]) {
    FinalRasterizerData rd;
    rd.position = float4(vert.position, 1.0);
    rd.texCoord = vert.texCoord;
    return rd;
}

fragment float4 fragment_final(const FinalRasterizerData rd [[ stage_in ]],
                              texture2d<float> renderTexture) {
    sampler s;
    float2 texCoord = rd.texCoord;
    texCoord.y = 1 - texCoord.y;
    float4 color = renderTexture.sample(s, texCoord);
    return float4(color);
}

