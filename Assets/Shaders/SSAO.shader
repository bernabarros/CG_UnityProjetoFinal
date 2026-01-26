Shader "Custom/SSAO"
{
    Properties
    {
        _SSAORadius ("SSAO Radius", Float) = 0.09
        _SSAOBias ("SSAO Bias", Float) = 0.005
        _SSAOKernelSize ("Kernel Size", Int) = 200
        _AO_Strength("AO Strength", Float) = 20
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

            // Textures
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            TEXTURE2D(_CameraNormalsTexture);
            SAMPLER(sampler_CameraNormalsTexture);

            TEXTURE2D(_CameraColorTexture);
            SAMPLER(sampler_CameraColorTexture);

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            // Parameters
            float _SSAORadius;
            float _SSAOBias;
            int _SSAOKernelSize;
            float _AO_Strength;

            // Decode normals from XY
            float3 DecodeNormal(float2 encodedXY)
            {
                float3 normal;
                normal.xy = encodedXY * 2.0 - 1.0;
                normal.z = sqrt(saturate(1.0 - dot(normal.xy, normal.xy)));
                return normal;
            }

            float3 SampleNormalVS(float2 uv)
            {
                float2 encodedXY = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv).xy;
                return DecodeNormal(encodedXY);
            }

            // Reconstruct view-space position
            float3 ReconstructViewPos(float2 uv, float rawDepth)
            {
                float2 ndc = uv * 2.0 - 1.0;
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float3 viewDir = mul(unity_CameraInvProjection, float4(ndc, 1, 1)).xyz;
                viewDir /= viewDir.z;
                return viewDir * linearDepth;
            }

            // Compute AO for a single pixel
            float ComputeAO(float2 uv)
            {
                float rawDepth = SAMPLE_TEXTURE2D_X(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    uv).r;

                float3 viewPos = ReconstructViewPos(uv, rawDepth);
                float3 normalVS = SampleNormalVS(uv);

                // >>> NEW: noise rotation
                float2 noiseUV = uv * (_ScreenParams.xy / 4.0);
                float3 randomVec = SAMPLE_TEXTURE2D_X(
                    _NoiseTex,
                    sampler_NoiseTex,
                    noiseUV).xyz * 2.0 - 1.0;

                float3 tangent = normalize(randomVec - normalVS * dot(randomVec, normalVS));
                float3 bitangent = cross(normalVS, tangent);
                float3x3 TBN = float3x3(tangent, bitangent, normalVS);

                float occlusion = 0.0;

                [unroll(32)]
                for (int i = 0; i < _SSAOKernelSize; i++)
                {
                    // hemisphere sample
                    float3 sample = normalize(float3(
                        frac(sin(i * 12.9898) * 43758.5453) * 2 - 1,
                        frac(sin(i * 78.233)  * 43758.5453) * 2 - 1,
                        frac(sin(i * 34.567)  * 43758.5453)
                    ));

                    float scale = (i / (float)_SSAOKernelSize);
                    sample *= lerp(0.1, 1.0, scale);          // >>> CHANGE (better distribution)

                    float3 sampleVS = viewPos + mul(TBN, sample) * _SSAORadius;

                    float4 clip = mul(unity_CameraProjection, float4(sampleVS, 1));
                    clip.xyz /= clip.w;
                    float2 sampleUV = clip.xy * 0.5 + 0.5;

                    float sampleDepthRaw = SAMPLE_TEXTURE2D_X(
                        _CameraDepthTexture,
                        sampler_CameraDepthTexture,
                        sampleUV).r;

                    float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepthRaw);

                    // >>> NEW: depth difference
                    float dz = viewPos.z - sampleViewPos.z;

                    if (dz <= _SSAOBias)
                        continue;   

                    // >>> NEW: distance falloff
                    float dist = length(sampleViewPos - viewPos);
                    float rangeWeight = saturate(1.0 - dist / _SSAORadius);

                    // >>> NEW: normal alignment (corner emphasis)
                    float3 dir = normalize(sampleViewPos - viewPos);
                    float angularWeight = saturate(-dot(normalVS, dir));
                    occlusion += angularWeight * rangeWeight;
                }

                return saturate(1.0 - occlusion / _SSAOKernelSize);
            }

            // 3x3 blur
            float BlurAO(float2 uv)
            {
                float2 texel = 1.0 / _ScreenParams.xy;
                float sum = 0.0;

                [unroll(9)]
                for (int x = -1; x <= 1; x++)
                    for (int y = -1; y <= 1; y++)
                        sum += ComputeAO(uv + float2(x, y) * texel);

                return sum / 9.0;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float ao = BlurAO(input.texcoord);

                // Sample original scene color
                half4 sceneCol = SAMPLE_TEXTURE2D_X(_CameraColorTexture, sampler_CameraColorTexture, input.texcoord);

                // Composite AO over scene color
                sceneCol.rgb = lerp(sceneCol.rgb, sceneCol.rgb * ao, _AO_Strength);

                return sceneCol;
            }

            ENDHLSL
        }
    }
    Fallback Off
}
