//
//  BasicShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

vertex RasterizerData vertex_basic(const Vertex vert [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                   constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    RasterizerData rd;
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstants.modelMatrix * float4(vert.position, 1);
    rd.color = vert.color;
    rd.texCoord = vert.texCoord;
    rd.totalGameTime = sceneConstants.totalGameTime;
    return rd;
}

fragment half4 fragment_basic(RasterizerData rd [[ stage_in ]],
                              constant Material &material [[ buffer(1) ]],
                              constant int &lightCount [[ buffer(2) ]],
                              constant LightData *lightDatas [[ buffer(3) ]],
                              sampler sampler2d [[ sampler(0) ]],
                              texture2d<float> texture [[ texture(0) ]]) {
    float2 texCoord = rd.texCoord;
    float4 color;
    if(material.useTexture) {
        color = texture.sample(sampler2d, texCoord);
    } else if(material.useMaterialColor) {
        color = material.color;
    } else {
        color = rd.color;
    }
    if(material.isLit) {
        float3 totalAmbient = float3(0,0,0);
        for(int i = 0; i < lightCount; i++) {
            LightData lightData = lightDatas[i];
            float3 ambientIntensity = material.ambient * lightData.ambientIntensity;
            float3 ambientColor = ambientIntensity * lightData.color;
            totalAmbient += ambientColor;
        }
        float3 phongIntensity = totalAmbient; // + totalDiffuse + totalSpecular
        color *= float4(phongIntensity, 1.0);
    }
    return half4(color.r, color.g, color.b, color.a);
}
