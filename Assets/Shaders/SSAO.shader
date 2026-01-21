Shader "Custom/SSAO"
{
    Properties
    {
        _SSAORadius ("SSAO Radius", Float) = 1.0
        _SSAOBias ("SSAO Bias", Float) = 0.05
        _SSAOKernelSize ("Kernel Size", Int) = 32
        _NoiseTex("Rotation/Noise Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Overlay" }

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

            TEXTURE2D(_CameraNormalsTexture);
            SAMPLER(sampler_CameraNormalsTexture);

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            float _SSAORadius;
            float _SSAOBias;
            int _SSAOKernelSize;


            float3 DecodeNormal(float2 encodedXY)
            {
                float3 normal;
                normal.xy = encodedXY * 2.0 - 1.0;         // Remap from [0,1] → [-1,1]
                normal.z = sqrt(saturate(1.0 - dot(normal.xy, normal.xy)));
                return normal;
            }

            float3 SampleNormalVS(float2 uv)
            {
                // Only use XY, Z is reconstructed
                float2 encodedXY = SAMPLE_TEXTURE2D_X(
                    _CameraNormalsTexture,
                    sampler_CameraNormalsTexture,
                    uv
                ).xy;

                return DecodeNormal(encodedXY);
            }

            float3 ReconstructViewPos(float2 uv, float rawDepth)
            {
                // Convert to NDC
                float2 ndc = uv * 2.0 - 1.0;

                // Linear eye depth (positive forward)
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // Reconstruct view position
                float3 viewDir = mul(unity_CameraInvProjection, float4(ndc, 1, 1)).xyz;
                viewDir /= viewDir.z;

                return viewDir * linearDepth;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                // 1. Sample depth & reconstruct view-space position
                float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord).r;
                float3 viewPos = ReconstructViewPos(input.texcoord, rawDepth);

                // 2. Sample normal in view space
                float3 normalVS = SampleNormalVS(input.texcoord);

                // 3. Pseudo-random rotation per pixel
                float2 noiseUV = input.texcoord * float2(_ScreenParams.x / 4.0, _ScreenParams.y / 4.0);
                float3 randomVec = SAMPLE_TEXTURE2D_X(_NoiseTex, sampler_NoiseTex, noiseUV).xyz * 2.0 - 1.0;

                // 4. Build tangent-space basis (TBN)
                float3 tangent = normalize(randomVec - normalVS * dot(randomVec, normalVS));
                float3 bitangent = cross(normalVS, tangent);
                float3x3 TBN = float3x3(tangent, bitangent, normalVS);

                // 5. Accumulate occlusion
                float occlusion = 0.0;

                [unroll(32)]
                for (int i = 0; i < _SSAOKernelSize; ++i)
                {
                    // Random hemisphere sample
                    float3 sample = normalize(float3(
                        frac(sin(i*12.9898) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i*78.233) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i*34.567) * 43758.5453)
                    ));

                    // Scale to hemisphere
                    sample *= 0.25 + 0.75 * (i / float(_SSAOKernelSize));

                    // Transform into tangent space and offset
                    float3 sampleVS = viewPos + mul(TBN, sample) * _SSAORadius;

                    // Project sample back to screen space
                    float4 offsetClip = mul(unity_CameraProjection, float4(sampleVS, 1.0));
                    offsetClip.xyz /= offsetClip.w;
                    float2 sampleUV = offsetClip.xy * 0.5 + 0.5;

                    // Sample depth
                    float sampleDepthRaw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUV).r;
                    float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepthRaw);

                    // Range-based occlusion
                    float rangeCheck = smoothstep(0.0, 1.0, _SSAORadius / length(sampleViewPos - viewPos));
                    occlusion += (sampleViewPos.z <= sampleVS.z - _SSAOBias ? 1.0 : 0.0) * rangeCheck;
                }

                occlusion = 1.0 - occlusion / _SSAOKernelSize;
                return half4(occlusion, occlusion, occlusion, 1.0);
            }
            ENDHLSL
        }
    }
    Fallback Off
}