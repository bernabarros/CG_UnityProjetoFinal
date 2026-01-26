using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class ContactShadowsFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public Material shaderMaterial;
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public Settings settings = new Settings();
    CustomRenderPass m_ScriptablePass;

    class PassData // Container for pass data
    {
        public Material material;
        public TextureHandle sourceTexture;
        public TextureHandle tempTexture;
    }

    class CustomRenderPass : ScriptableRenderPass
    {
        public Material material;
        private const string ProfilerTag = "Contact Shadows";

        public CustomRenderPass(Material material) // Constructor
        {
            this.material = material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData) // RenderGraph implementation
        { 
            if (material == null) return;

            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            if (resourceData.isActiveTargetBackBuffer || !resourceData.activeColorTexture.IsValid()) // No need to apply if rendering to backbuffer
                return;

            TextureHandle source = resourceData.activeColorTexture;
            TextureDesc desc = source.GetDescriptor(renderGraph);
            desc.name = "_TempContactShadows"; 
            desc.clearBuffer = false;
            desc.depthBufferBits = 0;

            TextureHandle tempTexture = renderGraph.CreateTexture(desc);

            UpdateShaderParameters(cameraData);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(ProfilerTag + " Apply", out var passData)) // First pass: Apply contact shadows
            {
                passData.material = material;
                passData.sourceTexture = source;

                builder.UseTexture(source, AccessFlags.Read); // Read from source texture
                builder.SetRenderAttachment(tempTexture, 0, AccessFlags.Write); // Write to temporary texture

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.sourceTexture, new Vector4(1, 1, 0, 0), data.material, 0); // Blit with material
                });
            }

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(ProfilerTag + " CopyBack", out var passData)) // Second pass: Copy back to source
            {
                passData.sourceTexture = tempTexture;
                builder.UseTexture(tempTexture, AccessFlags.Read);
                builder.SetRenderAttachment(source, 0, AccessFlags.Write);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) => // Copy back
                {
                    Blitter.BlitTexture(context.cmd, data.sourceTexture, new Vector4(1, 1, 0, 0), 0, false); // Blit back to source
                });
            }
        }

        private void UpdateShaderParameters(UniversalCameraData cameraData) // Update shader parameters
        {
            Camera cam = cameraData.camera;

            Matrix4x4 viewMat = cam.worldToCameraMatrix;
            Matrix4x4 projMat = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false);
            Matrix4x4 viewProj = projMat * viewMat;
            material.SetMatrix("_InverseViewProjectionMatrix", viewProj.inverse);

            Light mainLight = RenderSettings.sun;
            if (mainLight != null)
                material.SetVector("_LightDirection", -mainLight.transform.forward);
            else
                material.SetVector("_LightDirection", Vector3.up);
        }
    }

    public override void Create() // Create the render pass
    {
        m_ScriptablePass = new CustomRenderPass(settings.shaderMaterial);
        m_ScriptablePass.renderPassEvent = settings.renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData) // Add the render pass
    {
        if (settings.shaderMaterial != null)
        {
            renderer.EnqueuePass(m_ScriptablePass); // Enqueue the custom render pass
        }
    }
}