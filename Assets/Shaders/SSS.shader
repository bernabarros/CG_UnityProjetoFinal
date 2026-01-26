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

}
