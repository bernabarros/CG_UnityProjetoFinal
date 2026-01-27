using UnityEngine;

public class CameraMovement : MonoBehaviour
{
    [Header("Camera Settings")]
    [SerializeField] private float _mouseSens = 200f;
    [SerializeField] private float _moveSpeed = 10f;
    [SerializeField] private float _boostMultiplier = 2f;

    [Header("Light Settings")]
    [SerializeField] private Transform _directionLight;
    [SerializeField] private float _lightRotSpeed = 30f;

    float xRotation = 0f;
    float yRotation = 0f;

    void Start()
    {
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;

        Vector3 rot = transform.localRotation.eulerAngles;
        yRotation = rot.y;
        xRotation = rot.x;
    }

    void Update()
    {
        CameraRotation();
        CameraMov();
        LightRotation();

        if (Input.GetKeyDown(KeyCode.Escape))
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
    }

    void CameraRotation()
    {
        float mouseX = Input.GetAxis("Mouse X") * _mouseSens * Time.deltaTime;
        float mouseY = Input.GetAxis("Mouse Y") * _mouseSens * Time.deltaTime;

        yRotation += mouseX;
        xRotation -= mouseY;

        xRotation = Mathf.Clamp(xRotation, -90f, 90f);

        transform.localRotation = Quaternion.Euler(xRotation, yRotation, 0f);
    }

    void CameraMov()
    {
        float x = Input.GetAxis("Horizontal");
        float z = Input.GetAxis("Vertical");

        Vector3 move = transform.right * x + transform.forward * z;

        float currentSpeed = _moveSpeed;
        if (Input.GetKey(KeyCode.LeftShift)) currentSpeed *= _boostMultiplier;

        transform.position += move * currentSpeed * Time.deltaTime;
    }

    void LightRotation()
    {
        if (_directionLight != null)
        {
            if (Input.GetKey(KeyCode.Q))
            {
                _directionLight.Rotate(Vector3.right, -_lightRotSpeed * Time.deltaTime);
            }
            if (Input.GetKey(KeyCode.E))
            {
                _directionLight.Rotate(Vector3.right, _lightRotSpeed * Time.deltaTime);
            }
        }
    }
}
