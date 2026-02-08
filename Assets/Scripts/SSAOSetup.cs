using UnityEngine;

public class SSAOSetup : MonoBehaviour
{
    public Material ssaoMaterial;
    public float radius = 1.0f;
    // Update is called once per frame
    void Update()
    {
        ssaoMaterial.SetMatrix("_CameraProjectionMatrix", Camera.main.projectionMatrix);
        ssaoMaterial.SetFloat("_SSAORadius", radius);
    }
}
