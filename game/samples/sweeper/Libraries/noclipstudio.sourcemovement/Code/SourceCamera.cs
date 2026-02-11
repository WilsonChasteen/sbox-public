using System;
using Sandbox;

[Icon("smartphone")]
public class SourceCamera : Component {
	[Property] public float Sensitivity { get; set; } = 0.1f;
	[Property] public SourceMovement Player { get; set; }
	[Property] public CharacterController Controller { get; set; }
	[Property] public GameObject Head { get; set; }
	[Property] public GameObject Body { get; set; }
	[Property] public GameObject Target { get; set; }

	private ModelRenderer BodyRenderer;
	private Vector3 CurrentOffset = Vector3.Zero;

	protected override void OnAwake() {
		BodyRenderer = Body.GetComponent<ModelRenderer>();
	}

	protected override void OnUpdate() {
		if (Network.IsProxy) {
			if (BodyRenderer is not null) {
				BodyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
			}
			return;
		}

		var eyeAngles = Head.WorldRotation.Angles();
		eyeAngles.pitch += Input.MouseDelta.y * Sensitivity;
		eyeAngles.yaw -= Input.MouseDelta.x * Sensitivity;
		eyeAngles.roll = 0f;
		eyeAngles.pitch = Math.Clamp(eyeAngles.pitch, -89.9f, 89.9f);

		Head.WorldRotation = eyeAngles.ToRotation();

		var tarOffset = Vector3.Zero;
		if (Player.IsDucking) tarOffset = Vector3.Down * 32f;
		CurrentOffset = Vector3.Lerp(CurrentOffset, tarOffset, Time.Delta * 10f);

		if (Scene.Camera is not null) {
			Scene.Camera.WorldPosition = Head.WorldPosition + CurrentOffset;
			Scene.Camera.WorldRotation = eyeAngles.ToRotation();

			if (BodyRenderer is not null) {
				BodyRenderer.RenderType = ModelRenderer.ShadowRenderType.ShadowsOnly;
			}
		}
	}
}