//
//  ToScreenShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "Lighting.metal"
#include "Shared.metal"
using namespace metal;

struct ToScreenRasterizerData {
    float4 position [[ position ]];
    float2 texCoord;
};

vertex ToScreenRasterizerData vertex_toscreen(const Vertex vert [[ stage_in ]]) {
    ToScreenRasterizerData rd;
    rd.position = float4(vert.position, 1.0);
    rd.texCoord = vert.texCoord;
    return rd;
}

fragment half4 fragment_toscreen(ToScreenRasterizerData rd [[ stage_in ]],
                              texture2d<float> renderTexture [[ texture(0) ]]) {
    sampler s;
    float2 texCoord = rd.texCoord;
    texCoord.y = 1 - texCoord.y;
    float4 color = renderTexture.sample(s, texCoord);
    return half4(color.r, color.g, color.b, color.a);
}

