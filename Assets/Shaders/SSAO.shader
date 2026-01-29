Shader "Custom/SSAO"
{
    Properties
    {
        //Max distance that samples can reach
        _SSAORadius ("SSAO Radius", Float) = 0.09
        //Prevent self-occlusion, large values makes occlusion detach from surface
        //small values produce acne
        _SSAOBias ("SSAO Bias", Float) = 0.005
        //Number of rays per pixel
        _SSAOKernelSize ("Kernel Size", Int) = 200
        //Determines strength of the occlusion effect
        _AO_Strength("AO Strength", Float) = 20
        //Tiling Texture used to rotate sample kernels per pixel
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

            // Sample depth to detect occluders and compare distances
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            //Sample normals to determine which hemisphere to sample and which direction counts as occluding
            TEXTURE2D(_CameraNormalsTexture);
            SAMPLER(sampler_CameraNormalsTexture);
            //Sample the fully lit scene, where Ambient Occlusion will modify
            //the ambient lighting's effect
            TEXTURE2D(_CameraColorTexture);
            SAMPLER(sampler_CameraColorTexture);
            //Rotate each sample kernel to avoid noise
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
            //Use the normal to determine the direction a pixel is facing
            float3 SampleNormalVS(float2 uv)
            {
                float2 encodedXY = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv).xy;
                return DecodeNormal(encodedXY);
            }

            // Reconstruct view-space position of the pixel
            float3 ReconstructViewPos(float2 uv, float rawDepth)
            {
                float2 ndc = uv * 2.0 - 1.0;
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float3 viewDir = mul(unity_CameraInvProjection, float4(ndc, 1, 1)).xyz;
                viewDir /= viewDir.z;
                return viewDir * linearDepth;
            }

            // Compute AO for a single pixel, determine the level of occlusion
            //for each pixel
            float ComputeAO(float2 uv)
            {
                float rawDepth = SAMPLE_TEXTURE2D_X(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    uv).r;//retrieve pixel's raw depth from depth buffer

                float3 viewPos = ReconstructViewPos(uv, rawDepth);//pixel's position in 3D
                float3 normalVS = SampleNormalVS(uv);//determine the direction the surface is facing

                // Insure each pixel gets different rotations
                float2 noiseUV = uv * (_ScreenParams.xy / 4.0);
                //Generate a random vector on which to rotate sample
                float3 randomVec = SAMPLE_TEXTURE2D_X(
                    _NoiseTex,
                    sampler_NoiseTex,
                    noiseUV).xyz * 2.0 - 1.0;
                //Retrieve a tangent direction from surface
                float3 tangent = normalize(randomVec - normalVS * dot(randomVec, normalVS));
                //Compute a second direction perpendicular to the tangent one
                float3 bitangent = cross(normalVS, tangent);
                //Generate a coordinate system to make noise rotations relative to surface
                float3x3 TBN = float3x3(tangent, bitangent, normalVS);
                //Occlusion counter
                float occlusion = 0.0;

                [unroll(32)]
                //Sample loop, check number of directions equal to value
                for (int i = 0; i < _SSAOKernelSize; i++)
                {
                    // Create a pseudo-random sample direction
                    float3 sample = normalize(float3(
                        frac(sin(i * 12.9898) * 43758.5453) * 2 - 1,
                        frac(sin(i * 78.233)  * 43758.5453) * 2 - 1,
                        frac(sin(i * 34.567)  * 43758.5453)
                    ));
                    //Maintain samples close to surface
                    float scale = (i / (float)_SSAOKernelSize);
                    sample *= lerp(0.1, 1.0, scale);          
                    //Rotate sample to match the surface
                    float3 sampleVS = viewPos + mul(TBN, sample) * _SSAORadius;
                    //Project sample point into Screen Space
                    float4 clip = mul(unity_CameraProjection, float4(sampleVS, 1));
                    clip.xyz /= clip.w;
                    float2 sampleUV = clip.xy * 0.5 + 0.5;
                    //Retrive depth of this screen position
                    float sampleDepthRaw = SAMPLE_TEXTURE2D_X(
                        _CameraDepthTexture,
                        sampler_CameraDepthTexture,
                        sampleUV).r;
                    //Where position is in 3D
                    float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepthRaw);

                    //Check if direction is occluded
                    float dz = viewPos.z - sampleViewPos.z;

                    if (dz <= _SSAOBias)
                        continue;   

                    //Determine how much a blocker should matter for occlusion testing
                    float dist = length(sampleViewPos - viewPos);
                    float rangeWeight = saturate(1.0 - dist / _SSAORadius);

                    //Determine a angle to darken corner points more significantly
                    float3 dir = normalize(sampleViewPos - viewPos);
                    float angularWeight = saturate(-dot(normalVS, dir));
                    //Accumulate occlusion
                    occlusion += angularWeight * rangeWeight;
                }
                //Convert the accumulated occlusion to a Ambient Occlusion factor
                return saturate(1.0 - occlusion / _SSAOKernelSize);
            }

            // Blur the Ambient Occlusion factor to smooth it
            float BlurAO(float2 uv)
            {
                //Determine the size of one pixel in UV coordinates
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
