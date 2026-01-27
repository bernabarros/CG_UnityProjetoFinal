    // Calculate 3D pixel position using depth buffer
    // Having calculated the 3D pixel position, shoot a ray to the ligth source or direction 
    // Raymarching towards the light source if it has been blocked by any geometry its a shadow pixel
    // Verify in a loop if the depth of the ray is bigger than the value which the depth buffer can see
    // if yes, the pixel has to be a shadow pixel

Shader "Custom/SSS"
{
    Properties
    {
        _Strength ("Strength", Range(0, 1)) = 0.8
        _Step ("Step", Float) = 0.02
        _MaxSteps ("Max Steps", Int) = 20
        _Thickness ("Thickness", Float) = 0.5
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
            
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            float4x4 _CustomInvViewProj; // World Position
            float3 _CustomLightDir;      // Where is the sun

            // Variables
            float _Strength;
            float _Step;
            int _MaxSteps;
            float _Thickness;

            #define MAX_ITERATION_LIMIT 64 // avoid unroll error

            struct Attributes // Vertex Input
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings // Vertex to Fragment
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                
                float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID); // Clip Space
                float2 uv  = GetFullScreenTriangleTexCoord(input.vertexID); // UVs

                output.positionCS = pos; // Clip Space Position
                output.uv = uv; // UVs
                return output; // Return to Fragment
            }

            
            float3 GetWorldPos(float2 uv, float depth) // Reconstruct World Position
            {
                // Convert UV and Depth to Clip Space
                float4 clipPos = float4(uv * 2.0 - 1.0, depth, 1.0);
                // Fix UV starts at top
                #if UNITY_UV_STARTS_AT_TOP
                    clipPos.y = -clipPos.y;
                #endif
                // Clip space to World space
                float4 worldPos = mul(_CustomInvViewProj, clipPos);
                return worldPos.xyz / worldPos.w;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv;

                // Scene Color
                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);

                // Sample Depth
                float depthRaw = SampleSceneDepth(uv);

                #if UNITY_REVERSED_Z // Handle reversed Z buffer
                    if(depthRaw <= 0.0001) return color; // Early out for skybox
                #else
                    if(depthRaw >= 0.9999) return color; 
                #endif

                // World Position
                float3 worldPos = GetWorldPos(uv, depthRaw);

                // Raymarching Setup
                float3 rayPos = worldPos;
                // Verify light direction if its blocked
                float3 rayDir = _CustomLightDir; 
                
                float shadow = 0.0;
                
                [loop]
                for(int i = 0; i < MAX_ITERATION_LIMIT; i++)
                {
                    if(i >= _MaxSteps) break; // Exit based on user setting

                    
                    rayPos += rayDir * _Step;

                    // Ray Position to Screen UVs
                    float4 clipPos = mul(GetWorldToHClipMatrix(), float4(rayPos, 1.0));
                    float2 rayUV = (clipPos.xy / clipPos.w) * 0.5 + 0.5;

                    // ray off Screen
                    if(rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1) break;

                    float sampleDepth = SampleSceneDepth(rayUV); // Sample Depth at Ray UVs
                    float sampleLin = LinearEyeDepth(sampleDepth, _ZBufferParams); // Linearize Depth

                    float4 viewPos = mul(GetWorldToViewMatrix(), float4(rayPos, 1.0)); // View Space Position
                    float rayLin = -viewPos.z; // Linear Depth of Ray Position

                    float diff = rayLin - sampleLin; // Depth Difference

                    if(diff > 0.01 && diff < _Thickness) // If blocked
                    {
                        shadow = 1.0; // Pixel is a shadow
                        float edgeFade = 1.0 - pow(length(rayUV * 2.0 - 1.0), 4.0); // Edge Fade
                        shadow *= edgeFade;
                        
                        break; // block found, stop marching
                    }
                }
                // if it is a shadow pixel, darken it
                return color * (1.0 - (shadow * _Strength));
            }
            ENDHLSL
        }
    }
}