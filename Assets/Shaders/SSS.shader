Shader "Custom/SSS"
{
    Properties
    {
        _Strength ("Strength", Range(0, 1)) = 0.8
        _Step ("Step", Float) = 0.05 
        _MaxSteps ("Max Steps", Int) = 40 
        _Thickness ("Thickness", Float) = 0.5
        _Bias ("Start Bias", Float) = 0.1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "SSS"
            
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" 
            
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            float _Strength;
            float _Step;
            int _MaxSteps;
            float _Thickness;
            float _Bias;

            #define MAX_ITERATION_LIMIT 64

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
                float2 uv  = GetFullScreenTriangleTexCoord(input.vertexID);
                output.positionCS = pos;
                output.uv = uv;
                return output;
            }
            
            float3 GetWorldPos(float2 uv, float depth)
            {
                return ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP);
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv;
                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);
                float depthRaw = SampleSceneDepth(uv);

                #if UNITY_REVERSED_Z
                    if(depthRaw <= 0.0001) return color;
                #else
                    if(depthRaw >= 0.9999) return color; 
                #endif

                float3 worldPos = GetWorldPos(uv, depthRaw);
                float3 rayDir = normalize(_MainLightPosition.xyz); 

                float3 rayPos = worldPos;

             
                rayPos += rayDir * _Bias; 

                rayPos += rayDir * _Step; 

                float shadow = 0.0;
                
                [loop]
                for(int i = 0; i < MAX_ITERATION_LIMIT; i++)
                {
                    if(i >= _MaxSteps) break;

                    rayPos += rayDir * _Step;

                
                    float4 clipPos = mul(GetWorldToHClipMatrix(), float4(rayPos, 1.0));
                    
                    
                    float3 ndc = clipPos.xyz / clipPos.w;


                    float2 rayUV = ndc.xy;
                    rayUV.y *= _ProjectionParams.x;
                    
                    rayUV = rayUV * 0.5 + 0.5;

                    if(rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1) break;

                    float sampleDepth = SampleSceneDepth(rayUV);

                    #if UNITY_REVERSED_Z
                        if(sampleDepth <= 0.0001) continue; 
                    #else
                        if(sampleDepth >= 0.9999) continue;
                    #endif

                    float sampleLin = LinearEyeDepth(sampleDepth, _ZBufferParams);
                    float3 viewPos = TransformWorldToView(rayPos);
                    float rayLin = -viewPos.z; 

                    float diff = rayLin - sampleLin;

                    if(diff > 0.01 && diff < _Thickness) 
                    {
                        shadow = 1.0;
                        float edgeFade = 1.0 - pow(length(rayUV * 2.0 - 1.0), 4.0);
                        shadow *= edgeFade;
                        shadow *= (1.0 - (float(i) / float(_MaxSteps)));
                        break;
                    }
                }

                return color * (1.0 - (shadow * _Strength));
            }
            ENDHLSL
        }
    }
}