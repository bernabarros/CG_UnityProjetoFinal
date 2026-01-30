using UnityEngine;

[ExecuteAlways]
public class SSSFeeder : MonoBehaviour
{
    [SerializeField] private Light sunLight;

    void Update()
    {
        if (sunLight != null)
        {
            Shader.SetGlobalVector("_CustomLightDir", sunLight.transform.forward); // Send light direction to Shader
        }
        else
        {
            Shader.SetGlobalVector("_CustomLightDir", Vector3.up); // Default direction if no light is assigned
        }

        // Send Inverse View-Projection Matrix to Shader
        Camera cam = Camera.main;
        if (cam != null)
        {
            Matrix4x4 viewMat = cam.worldToCameraMatrix; // View Matrix
            Matrix4x4 projMat = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false); // false for not render into texture
            Matrix4x4 viewProj = projMat * viewMat;
            Matrix4x4 invViewProj = viewProj.inverse; // Calculate Inverse View-Projection Matrix

            Shader.SetGlobalMatrix("_CustomInvViewProj", invViewProj);
            Shader.SetGlobalVector("_CustomCamPos", cam.transform.position);
        }
    }
}