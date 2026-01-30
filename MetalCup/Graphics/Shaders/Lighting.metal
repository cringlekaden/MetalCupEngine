//
//  Lighting.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/22/26.
//

#ifndef LIGHTING_METAL
#define LIGHTING_METAL

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

class Lighting {
public:
    
    static float3 GetPhongIntensity(constant Material &material, constant LightData *lightDatas, int lightCount, float3 worldPosition, float3 unitNormal, float3 unitToCamera) {
        float3 totalAmbient = float3(0,0,0);
        float3 totalDiffuse = float3(0,0,0);
        float3 totalSpecular = float3(0,0,0);
        for(int i = 0; i < lightCount; i++) {
            LightData lightData = lightDatas[i];
            float3 unitToLight = normalize(lightData.position - worldPosition);
            float3 unitReflection = normalize(reflect(-unitToLight, unitNormal));
            float nDotL = dot(unitNormal, unitToLight);
            float correctedNDotL = max(nDotL, 0.3);
            float rDotV = max(dot(unitReflection, unitToCamera), 0.0);
            //Ambient
            float3 ambientIntensity = material.ambient * lightData.ambientIntensity;
            float3 ambientColor = clamp(ambientIntensity * lightData.color * lightData.brightness, 0.0, 1.0);
            if(nDotL <= 0) {
                totalAmbient += ambientColor;
            }
            //Diffuse
            float3 diffuseIntensity = material.diffuse * lightData.diffuseIntensity;
            float3 diffuseColor = clamp(diffuseIntensity * correctedNDotL * lightData.color * lightData.brightness, 0.0, 1.0);
            totalDiffuse += diffuseColor;
            //Specular
            float3 specularIntensity = material.specular * lightData.specularIntensity;
            float specularExponent = pow(rDotV, material.shininess);
            float3 specularColor = clamp(specularIntensity * specularExponent * lightData.color * lightData.brightness, 0.0, 1.0);
            totalSpecular += specularColor;
        }
        return totalAmbient + totalDiffuse + totalSpecular;
    }
};

#endif

