Shader "Custom/SSAO"
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

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            float3 ReconstructViewPos(float2 uv, float linearDepth)
            {
                // Convert UV to NDC (-1 to 1)
                float2 ndc = uv * 2.0 - 1.0;

                // Reconstruct view-space position
                float4 viewPos = mul(unity_CameraInvProjection, float4(ndc, 1.0, 1.0));

                // Perspective divide
                viewPos.xyz /= viewPos.w;

                // Scale by depth
                return viewPos.xyz * linearDepth;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float rawDepth = SAMPLE_TEXTURE2D_X(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    input.texcoord
                ).r;

                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                float3 viewPos = ComputeViewSpacePosition(
                    input.texcoord,
                    rawDepth,
                    unity_CameraInvProjection
                );

                // --- SSAO sampling ---
                float2 offsets[4] = {
                    float2(0.002, 0.0),
                    float2(-0.002, 0.0),
                    float2(0.0, 0.002),
                    float2(0.0, -0.002)
                };

                float occlusion = 0.0;
                for (int s = 0; s < 4; ++s)
                {
                    float2 sampleUV = input.texcoord + offsets[s];

                    // Read neighboring depth
                    float sampleDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUV).r;
                    float linearSampleDepth = LinearEyeDepth(sampleDepth, _ZBufferParams);

                    float3 sampleViewPos = ComputeViewSpacePosition(sampleUV, sampleDepth, unity_CameraInvProjection);

                    // Simple AO test: if sample is closer than center, it contributes
                    float rangeCheck = saturate((linearDepth - linearSampleDepth) / 0.1); // 0.1 = radius
                    occlusion += rangeCheck;
                }

                occlusion = 1.0 - saturate(occlusion / 4.0); // normalize and invert
                return half4(occlusion, occlusion, occlusion, 1.0);
            }

            /*
            half4 Frag(Varyings input) : SV_Target
            {
                float rawDepth = SAMPLE_TEXTURE2D_X(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    input.texcoord
                ).r;

                // Linearize depth (in view space)
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // Normalize for visualization (choose a max range, e.g., 10 units)
                float depthVis = saturate(linearDepth / 10.0);

                return half4(depthVis, depthVis, depthVis, 1.0);
            }
            */

            ENDHLSL
        }
    }
    Fallback Off
}