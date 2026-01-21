Shader "Custom/SSAO"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Overlay"}
        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata //Data from mesh
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
            struct v2f //Vertex to fragment data
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;

            v2f vert(appdata v) //Vertex shader
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }
            half4 frag(v2f i) : SV_Target //Fragment shader
            {
                return tex2D(_MainTex, i.uv);
            }
            ENDHLSL
        }
    }
}