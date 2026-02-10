Shader "Custom/SSAO Final"
{
    Properties
    {
        _SSAORadius ("Radius", Range(0.1, 5.0)) = 1.0
        _AOIntensity ("Intensity", Range(0, 4)) = 1.0
        _AOPower ("Contrast", Range(0.5, 4)) = 1.0
        _AOBias ("Depth Bias", Range(0.0, 0.1)) = 0.02
        _AORange ("Range Limit", Range(0.1, 10)) = 2.0
        _AOFadeStart ("Fade Start", Range(0, 20)) = 5
        _AOFadeEnd ("Fade End", Range(1, 50)) = 20
        _SampleCount ("Samples", Range(8, 64)) = 32
    }

    SubShader
    {
        Tags { "RenderPipeline" ="UniversalPipeline" "RenderType"="Opaque"}

        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _SSAORadius;
                float _AOIntensity;
                float _AOPower;
                float _AOBias;
                float _AORange;
                float _AOFadeStart;
                float _AOFadeEnd;
                int   _SampleCount;
            CBUFFER_END



            float GetLinearEyeDepth(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            float3 ReconstructViewPosition(float2 uv)
            {
                float depth = SampleSceneDepth(uv);

                float3 worldPos = ComputeWorldSpacePosition(
                    uv,
                    depth,
                    UNITY_MATRIX_I_VP
                );

                return mul(UNITY_MATRIX_V, float4(worldPos, 1.0)).xyz;
            }

            float3 GetNormal(float2 uv)
            {
                float4 tex = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv);

                float3 normalVS = UnpackNormal(tex);

                return normalize(normalVS);
            }
            
            float ComputeAO(float2 uv)
            {
                float3 viewPos = ReconstructViewPosition(uv);
                float3 normal = GetNormal(uv);

                float3 randomVec = normalize(float3(
                    frac(sin(dot(uv * _ScreenParams.xy, float2(12.9898, 78.233))) * 43758.5453),
                    frac(sin(dot(uv * _ScreenParams.xy, float2(39.425, 11.135))) * 43758.5453),
                    0.0
                ));

                float3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
                float3 bitangent = cross(normal, tangent);
                float3x3 TangBitNorm = float3x3(tangent, bitangent, normal);

                float occlusion = 0;
                float bias = _AOBias;

                [unroll(32)]
                for(int i = 0; i < _SampleCount; i++)
                {
                    float3 sampleDir = float3(
                        frac(sin(i * 12.9898) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i * 78.233) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i * 39.425) * 43758.5453)            
                    );

                    sampleDir.z = abs(sampleDir.z);

                    sampleDir = normalize(sampleDir);

                    sampleDir = mul(TangBitNorm, sampleDir);

                    float NdotS = dot(normal, sampleDir);
                    if (NdotS < 0.15)
                        continue;

                    float scale = float(i) / _SampleCount;
                    scale = lerp(0.1, 1.0, scale * scale);

                    float3 samplePos = viewPos + sampleDir * (_SSAORadius * scale);

                    float4 clipPos = mul(UNITY_MATRIX_P, float4(samplePos, 1.0));

                    float2 sampleUV = clipPos.xy / clipPos.w;
                    sampleUV = sampleUV * 0.5 + 0.5;
                    sampleUV.y = 1.0 - sampleUV.y;

                    if(sampleUV.x < 0 || sampleUV.x > 1 || sampleUV.y < 0 || sampleUV.y > 1)
                        continue;

                    float sampleDepth = GetLinearEyeDepth(sampleUV);

                    // Depth of our sample point along view direction
                    float samplePointDepth = -samplePos.z;

                    float dist = abs(sampleDepth - samplePointDepth);

                    float rangeCheck = 1.0 - smoothstep(0.0, _AORange, dist);

                    if(sampleDepth < samplePointDepth - bias)//bias, prevent self occlusion
                        occlusion += rangeCheck;
                }
                occlusion = 1.0 - (occlusion / _SampleCount);

                float viewDepth = -viewPos.z;
                float fade = smoothstep(_AOFadeEnd, _AOFadeStart, viewDepth);
                occlusion = lerp(1.0, occlusion, fade);

                occlusion = pow(saturate(occlusion), _AOPower);

                occlusion = lerp(1.0, occlusion, _AOIntensity);

                return saturate(occlusion);
            }
            
            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                float linearDepth = GetLinearEyeDepth(uv);

                float aoFactor = ComputeAO(uv);
                
                return sceneColor * aoFactor;
            }
            ENDHLSL
        }
    }
    Fallback Off
}