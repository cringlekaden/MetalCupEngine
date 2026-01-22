//
//  InstancedShader.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

vertex RasterizerData vertex_instanced(const Vertex vert [[ stage_in ]],
                                       constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                       constant ModelConstants *modelConstants [[ buffer(2) ]],
                                       uint instanceId [[ instance_id ]]){
    RasterizerData rd;
    ModelConstants modelConstant = modelConstants[instanceId];
    float4 worldPosition = modelConstant.modelMatrix * float4(vert.position, 1.0);
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    rd.color = vert.color;
    rd.texCoord = vert.texCoord;
    rd.totalGameTime = sceneConstants.totalGameTime;
    rd.worldPosition = worldPosition.xyz;
    rd.surfaceNormal = (modelConstant.modelMatrix * float4(vert.normal, 1.0)).xyz;
    rd.toCamera = sceneConstants.cameraPosition - worldPosition.xyz;
    return rd;
}
