Shader "Custom/SSS"
{
    Properties
    {
        _Strength ("Strength", Range(0, 1)) = 0.8 // Strength controls how dark the shadow will be
        _Step ("Step", Float) = 0.05  // Step size for ray marching 
        _MaxSteps ("Max Steps", Int) = 40 // Maximum number of steps for ray marching
        _Thickness ("Thickness", Float) = 0.5 // Thickness of the shadow
        _Bias ("Start Bias", Float) = 0.1 // Bias to push the ray start position towards the light to avoid self-intersection
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" // For GetFullScreenTriangleVertexPosition and GetFullScreenTriangleTexCoord
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl" // For depth sampling
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" // Main Light
            
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            // Variables
            float _Strength;
            float _Step;
            int _MaxSteps;
            float _Thickness;
            float _Bias;

            #define MAX_ITERATION_LIMIT 64

            // Vertex Shader
            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            // Vertex to Fragment 
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
            
            // reconstruct World Position from UV and Depth
            float3 GetWorldPos(float2 uv, float depth)
            {
                return ComputeWorldSpacePosition(uv, depth, unity_MatrixInvVP); // Using Unity's function to reconstruct world position from screen UV and depth
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.uv; // Screen UV
                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv); // Screen color
                float depthRaw = SampleSceneDepth(uv); // Raw depth from depth texture

                #if UNITY_REVERSED_Z
                    if(depthRaw <= 0.0001) return color;
                #else
                    if(depthRaw >= 0.9999) return color; 
                #endif

                float3 worldPos = GetWorldPos(uv, depthRaw); // Reconstruct world position
                // Normalize ensures the vector length is 1
                float3 rayDir = normalize(_MainLightPosition.xyz); // _MainLightPosition is a directional light direction in world space

                float3 rayPos = worldPos;

             
                rayPos += rayDir * _Bias; // Push position towards light to avoid intersection

                rayPos += rayDir * _Step; 

                float shadow = 0.0;
                
                [loop]
                for(int i = 0; i < MAX_ITERATION_LIMIT; i++)
                {
                    if(i >= _MaxSteps) break;

                    rayPos += rayDir * _Step;

                    // Project the current Ray Position back to Clip Space
                    float4 clipPos = mul(GetWorldToHClipMatrix(), float4(rayPos, 1.0));
                    
                    // Convert to Normalized Coordinates -1, 1
                    float3 ndc = clipPos.xyz / clipPos.w;


                    float2 rayUV = ndc.xy;

                    // DirectX has already flipped Y coordinate
                    rayUV.y *= _ProjectionParams.x;
                    

                    // Convert range from -1, 1 to 0, 1
                    rayUV = rayUV * 0.5 + 0.5;

                    if(rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1) break;

                    float sampleDepth = SampleSceneDepth(rayUV);

                    #if UNITY_REVERSED_Z
                        if(sampleDepth <= 0.0001) continue; 
                    #else
                        if(sampleDepth >= 0.9999) continue;
                    #endif

                    float sampleLin = LinearEyeDepth(sampleDepth, _ZBufferParams); // Convert non-linear depth to linear depth
                    float3 viewPos = TransformWorldToView(rayPos); // Transform ray position to view space to get correct Z value for comparison
                    float rayLin = -viewPos.z; // Get linear depth of the ray position in view space

                    float diff = rayLin - sampleLin; // Compare the depth of the ray with the sampled depth to determine if it's in shadow

                    if(diff > 0.01 && diff < _Thickness) 
                    {
                        shadow = 1.0;
                        float edgeFade = 1.0 - pow(length(rayUV * 2.0 - 1.0), 4.0);
                        shadow *= edgeFade;
                        shadow *= (1.0 - (float(i) / float(_MaxSteps))); // Fade shadow based on distance traveled
                        break; 
                    }
                }

                return color * (1.0 - (shadow * _Strength));
            }
            ENDHLSL
        }
    }
}