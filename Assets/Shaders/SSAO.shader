Shader "Hidden/Custom/SSAO"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "SSAO"

            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert (Attributes v)
            {
                Varyings o;
                o.uv = float2((v.vertexID << 1) & 2, v.vertexID & 2);
                o.positionCS = float4(o.uv * 2.0 - 1.0, 0, 1);
                return o;
            }

            float _Radius;
            float _Intensity;
            //int _SampleCount;

            #define SAMPLE_COUNT 16


            float ComputeAO(float2 uv, float3 normalWS, float depth)
            {
                float occlusion = 0.0;

                for (int i = 0; i < SAMPLE_COUNT; i++)
                {
                    float2 offset = float2(
                        cos(i * 6.2831 / SAMPLE_COUNT),
                        sin(i * 6.2831 / SAMPLE_COUNT)
                    );

                    offset *= _Radius;

                    float2 sampleUV = uv + offset * _ScreenParams.zw;

                    float sampleDepth = SampleSceneDepth(sampleUV);

                    float rangeCheck = smoothstep(0.0, 1.0, _Radius / abs(depth - sampleDepth));
                    occlusion += (sampleDepth >= depth ? 1.0 : 0.0) * rangeCheck;
                }

                return 1.0 - (occlusion / SAMPLE_COUNT);
            }
            half4 Frag (Varyings i) : SV_Target
            {
                float depth = SampleSceneDepth(i.uv);

                if (depth >= 1.0)
                    return half4(1, 1, 1, 1);

                float3 normalWS = SampleSceneNormals(i.uv);

                float ao = ComputeAO(i.uv, normalWS, depth);
                ao = pow(ao, _Intensity);

                return half4(ao, ao, ao, 1);
            }
            ENDHLSL
        }
    }
}