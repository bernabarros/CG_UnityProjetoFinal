Shader "Custom/SSAO 1"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Overlay" }

        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off
            Blend Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes  
            { 
                float4 position : POSITION; 
                float2 uv : TEXCOORD0; 
            };

            struct Varyings 
            { 
                float2 uv : TEXCOORD0; 
                float4 position : SV_POSITION; 
            };

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.position = float4(v.position.xy * 2 - 1, 0, 1);
                o.uv = v.uv;
                return o;
            }

            float3 sampleKernel[8] = {
                float3(0.1,0,0), float3(-0.1,0,0),
                float3(0,0.1,0), float3(0,-0.1,0),
                float3(0.07,0.07,0), float3(-0.07,0.07,0),
                float3(0.07,-0.07,0), float3(-0.07,-0.07,0)
            };

            half4 frag(Varyings i) : SV_Target
            {
                // --- center pixel ---
                float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv).r;
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float3 viewPos = ComputeViewSpacePosition(i.uv, rawDepth, unity_CameraInvProjection);

                // --- ambient occlusion accumulation ---
                float occlusion = 0;

                for (int s = 0; s < 8; ++s)
                {
                    float3 offsetPos = viewPos + sampleKernel[s]; // move in view-space

                    // project back to screen UV
                    float4 projPos = mul(unity_CameraProjection, float4(offsetPos, 1.0));
                    float2 sampleUV = projPos.xy / projPos.w * 0.5 + 0.5;

                    // read depth at neighbor
                    float sampleDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUV).r;
                    float linearSampleDepth = LinearEyeDepth(sampleDepth, _ZBufferParams);

                    // compare distance along view Z
                    float rangeCheck = saturate((linearDepth - linearSampleDepth) / 0.2); // 0.2 units radius
                    occlusion += rangeCheck;
                }

                occlusion = 1.0 - saturate(occlusion / 8.0);

                return half4(1,0,0,1.0);
            }
            ENDHLSL
        }
    }
    Fallback Off
}