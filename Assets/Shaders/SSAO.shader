Shader "Custom/SSAO"
{
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

            // SSAO settings
            static const int KERNEL_SIZE = 16;      // Number of samples
            static const float RADIUS = 0.5;        // Sampling radius in world units
            static const float BIAS = 0.025;        // Bias to avoid self-occlusion
            static const float MAX_DISTANCE = 10.0; // Maximum distance for AO visualization

            float3 GetRandomVec(float2 uv)
            {
                float2 noise = frac(sin(dot(uv ,float2(12.9898,78.233))) * 43758.5453);
                return normalize(float3(noise * 2.0 - 1.0, 0));
            }

            float3 kernel[KERNEL_SIZE];

            void InitKernel()
            {
                [unroll]
                for (int i = 0; i < KERNEL_SIZE; ++i)
                {
                    float3 sample = normalize(float3(
                        frac(sin(i * 12.9898) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i * 78.233) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i * 34.567) * 43758.5453) // z
                    ));
                    sample *= frac(sin(i * 98.765) * 43758.5453); // random length
                    //sample *= i / float(KERNEL_SIZE);             // scale closer samples smaller
                    sample *= 0.5 + 0.5 * i / float(KERNEL_SIZE); // ensure samples reach some distance

                    kernel[i] = sample;
                }
            }

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


            /*
            float3 SampleNormalWS(float2 uv)
            {
                float4 encoded = SAMPLE_TEXTURE2D_X(
                    _CameraNormalsTexture,
                    sampler_CameraNormalsTexture,
                    uv
                );

                return DecodeNormal(encoded);
            }
            */

            float3 NormalWS_To_View(float3 normalWS)
            {
                return mul((float3x3)UNITY_MATRIX_V, normalWS);
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
            /*
            half4 Frag(Varyings input) : SV_Target
            {
                float3 normalVS = SampleNormalVS(input.texcoord);

                // Visualize normals
                return half4(normalVS * 0.5 + 0.5, 1.0);
            }
            */

            half4 Frag(Varyings input) : SV_Target
            {
                // --- 1. Sample depth & reconstruct view-space position
                float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord).r;
                float3 viewPos = ReconstructViewPos(input.texcoord, rawDepth);

                // --- 2. Sample normal in view space
                float3 normalVS = SampleNormalVS(input.texcoord);

                // --- 3. SSAO parameters
                const int KERNEL_SIZE = 32;
                const float RADIUS = 1;  // in world units
                const float BIAS = 0.05;   // avoid self-shadowing

                // --- 4. Pseudo-random rotation vector per pixel
                float2 noise = frac(sin(dot(input.texcoord ,float2(12.9898,78.233))) * 43758.5453);
                float3 randomVec = normalize(float3(noise * 2.0 - 1.0, 0));

                // --- 5. Build tangent-space basis (TBN)
                float3 tangent = normalize(randomVec - normalVS * dot(randomVec, normalVS));
                float3 bitangent = cross(normalVS, tangent);
                float3x3 TBN = float3x3(tangent, bitangent, normalVS);

                // --- 6. Generate kernel
                float3 kernel[KERNEL_SIZE];
                [unroll]
                for (int i = 0; i < KERNEL_SIZE; ++i)
                {
                    // Random hemisphere sample
                    float3 sample = normalize(float3(
                        frac(sin(i*12.9898) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i*78.233) * 43758.5453) * 2.0 - 1.0,
                        frac(sin(i*34.567) * 43758.5453)
                    ));

                    // Scale to hemisphere & kernel index
                    sample *= 0.25 + 0.75 * (i / float(KERNEL_SIZE)); // ensures some reach
                    kernel[i] = sample;
                }

                // --- 7. Accumulate occlusion
                float occlusion = 0.0;
                [unroll]
                for (int i = 0; i < KERNEL_SIZE; ++i)
                {
                    float3 sampleVS = mul(TBN, kernel[i]);   // rotate into tangent space
                    sampleVS = viewPos + sampleVS * RADIUS;  // move into view space

                    // Project sample back to clip space
                    float4 offsetClip = mul(unity_CameraProjection, float4(sampleVS, 1.0));
                    offsetClip.xyz /= offsetClip.w;
                    float2 sampleUV = offsetClip.xy * 0.5 + 0.5;

                    // Sample depth
                    float sampleDepthRaw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUV).r;
                    float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepthRaw);

                    // --- Z comparison fixed: forward is negative
                    float rangeCheck = smoothstep(0.0, 1.0, RADIUS / (length(sampleViewPos - viewPos)));
                    occlusion += (sampleViewPos.z <= sampleVS.z - BIAS ? 1.0 : 0.0) * rangeCheck;
                }

                // --- 8. Normalize and invert
                occlusion = 1.0 - occlusion / KERNEL_SIZE;

                // --- 9. Output AO
                return half4(occlusion, occlusion, occlusion, 1.0);
            }
            /*
            half4 Frag(Varyings input) : SV_Target
            {
                // 1. Sample depth & reconstruct view position
                float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord).r;
                float3 viewPos = ReconstructViewPos(input.texcoord, rawDepth);

                // 2. Sample normal
                float3 normalVS = SampleNormalVS(input.texcoord);

                // 3. Generate random rotation vector
                float3 randomVec = GetRandomVec(input.texcoord);

                // 4. Create tangent space basis (TBN)
                float3 tangent = normalize(randomVec - normalVS * dot(randomVec, normalVS));
                float3 bitangent = cross(normalVS, tangent);
                float3x3 TBN = float3x3(tangent, bitangent, normalVS);

                // 5. Accumulate occlusion
                float occlusion = 0.0;

                [unroll]
                for (int i = 0; i < KERNEL_SIZE; ++i)
                {
                    float3 sampleVS = mul(TBN, kernel[i]); // rotate sample into tangent space
                    sampleVS = viewPos + sampleVS * RADIUS; // offset in view space

                    // Project sample back to screen space
                    float4 offsetClip = mul(unity_CameraProjection, float4(sampleVS,1));
                    offsetClip.xyz /= offsetClip.w;
                    float2 sampleUV = offsetClip.xy * 0.5 + 0.5;

                    // Sample depth at this location
                    float sampleDepthRaw = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUV).r;
                    float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepthRaw);

                    float rangeCheck = smoothstep(0.0, 1.0, RADIUS / (length(sampleViewPos - viewPos)));
                    //occlusion += (sampleViewPos.z >= sampleVS.z + BIAS ? 1.0 : 0.0) * rangeCheck;
                    occlusion += (sampleViewPos.z <= sampleVS.z - BIAS ? 1.0 : 0.0) * rangeCheck;

                }

                occlusion = 1.0 - occlusion / KERNEL_SIZE; // invert to get AO

                return half4(occlusion, occlusion, occlusion, 1.0);
            }
            */

            /*
            half4 Frag(Varyings input) : SV_Target
            {
                // 1. Sample raw depth
                float rawDepth = SAMPLE_TEXTURE2D_X(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    input.texcoord
                ).r;

                // 2. Reconstruct view-space position
                float3 viewPos = ReconstructViewPos(input.texcoord, rawDepth);

                // 3. Visualize view-space Z
                float depthVis = saturate(viewPos.z / 10.0);

                // 4. Output grayscale
                return half4(depthVis, depthVis, depthVis, 1.0);
            }
            */

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