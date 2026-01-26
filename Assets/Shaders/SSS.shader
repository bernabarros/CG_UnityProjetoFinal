Shader "Custom/SSS"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _ShadowStrength ("Intensity", Range(0, 1)) = 1.0
        _Step ("Step", Float) = 0.05
        _MaxSteps ("Max Steps", Int) = 20
        _Thickness ("Thickness", Float) = 0.5
    }
    
    // Calculate 3D pixel position using depth buffer
    // Having calculated the 3D pixel position, shoot a ray to the ligth source or direction 
    // Verify in a loop if the depth of the ray is bigger than the value which the depth buffer can see
    // if yes, the pixel has to be a shadow pixel

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            // Include necessary libraries
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"


            // Vertex structure
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };


            // Vertex to Fragment structure 
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            // Textures
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            // Matrices
            float4x4 _InverseViewProjectionMatrix;
            float3 _LightDirection;

            // Parameters
            float _ShadowStrength;
            float _Step;
            int _MaxSteps;
            float _Thickness;

            #define MAX_ITERATIONS 128

            v2f Vert (appdata v) // Vertex Shader
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = v.uv;
                return o;
            }

            float3 GetWorldPositionFromDepth(float2 uv, float depth) // Reconstruct world position from depth
            {
                float4 clipPos = float4(uv * 2.0 - 1.0, depth, 1.0);
                
                #if UNITY_UV_STARTS_AT_TOP
                clipPos.y = -clipPos.y; // Adjust for UV origin
                #endif

                float4 worldPos = mul(_InverseViewProjectionMatrix, clipPos); // Transform to world space
                return worldPos.xyz / worldPos.w;
            }

            float RaymarchShadow(float3 startPos, float3 lightDir, float2 startUV) // Raymarching for subsurface scattering shadow
            {
                float3 currentPos = startPos;
                
                float dither = frac(sin(dot(startUV, float2(12.9898, 78.233))) * 43758.5453); // Dithering to reduce banding
                currentPos += lightDir * _Step * dither;

                [loop]
                for (int i = 0; i < MAX_ITERATIONS; i++) // Raymarch loop
                {
                    if (i >= _MaxSteps)
                        break;

                    currentPos += lightDir * _Step;

                    float4 clipPos = mul(GetWorldToHClipMatrix(), float4(currentPos, 1.0)); // Transform to clip space
                    float2 rayUV = (clipPos.xy / clipPos.w) * 0.5 + 0.5; // Convert to UV space

                    if (rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1) // Exit if outside screen
                        break;

                    float sampledDepthRaw = SampleSceneDepth(rayUV);// Sample depth buffer
                    float sampledDepthLinear = LinearEyeDepth(sampledDepthRaw, _ZBufferParams); // Convert to linear depth

                    float4 viewPosRay = mul(GetWorldToViewMatrix(), float4(currentPos, 1.0)); // Transform to view space
                    float rayDepthLinear = -viewPosRay.z;  // Get linear depth of the ray position

                    float depthDiff = rayDepthLinear - sampledDepthLinear; // Depth difference

                    if (depthDiff > 0.001 && depthDiff < _Thickness) // Check for shadow condition
                    {
                        float shadow = 1.0;
                        float edgeFade = 1.0 - pow(length(rayUV * 2.0 - 1.0), 4.0); // Edge fading
                        shadow *= edgeFade;
                        return shadow;
                    }
                }
                return 0.0;
            }

            float4 Frag (v2f i) : SV_Target // Fragment Shader
            {
                float4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, i.uv); // Sample original scene color

                float depth = SampleSceneDepth(i.uv); // Sample depth buffer
                
                #if UNITY_REVERSED_Z // Handle reversed Z buffer
                    if (depth <= 0.0001) return col;
                #else
                    if (depth >= 0.9999) return col;
                #endif

                float3 worldPos = GetWorldPositionFromDepth(i.uv, depth); // Reconstruct world position

                float shadowMap = RaymarchShadow(worldPos, _LightDirection, i.uv); // Perform raymarching for shadow
                float shadowFactor = 1.0 - (shadowMap * _ShadowStrength); // Calculate shadow factor
                return col * shadowFactor; // Apply shadow to original color
            }
            ENDHLSL
        }
    }
}