//
//  ImGuiShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 2/3/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

vertex SimpleRasterizerData vertex_final(const SimpleVertex vert [[ stage_in ]]) {
    SimpleRasterizerData rd;
    rd.position = float4(vert.position, 1.0);
    rd.texCoord = vert.position.xy * 0.5 + 0.5;
    return rd;
}

fragment float4 fragment_imgui(const SimpleRasterizerData rd [[ stage_in ]],
                               texture2d<float> imGuiTexture [[ texture(0) ]],
                               sampler s [[ sampler(0) ]]) {
    return float4(1.0, 1.0, 1.0, 1.0);
}

