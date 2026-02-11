using Sandbox;
using System;
using System.Linq;

[Icon("directions_walk")]
public class SourceMovement : Component {
	[Group("Base"), Property] public float WalkSpeed { get; set; } = 240.0f;
	[Group("Base"), Property] public float RunSpeed { get; set; } = 320.0f;
	[Group("Base"), Property] public float DuckSpeed { get; set; } = 120.0f;
	[Group("Base"), Property] public float JumpPower { get; set; } = 280.0f;
	[Group("Base"), Property] public bool RunByDefault { get; set; } = true;
	[Group("Base"), Property] public bool AutoBhop { get; set; } = false;

	[Group("Movement"), Property] public float Friction { get; set; } = 4.8f; // CSGO: 4.8, TF2: 4
	[Group("Movement"), Property] public float StopSpeed { get; set; } = 75.0f; // CSGO: 75, TF2: 100
	[Group("Movement"), Property] public float Accelerate { get; set; } = 5.6f; // CSGO: 5.6, TF2: 10
	[Group("Movement"), Property] public float AirAccelerate { get; set; } = 12.0f; // CSGO: 12.0, TF2: 10
	[Group("Movement"), Property] public float AirMaxWishSpeed { get; set; } = 30.0f;
	[Group("Movement"), Property] public float GravityScale { get; set; } = 1.0f;

	public Vector3 Velocity;
	private Vector3 WishVelocity;

	[Sync] public bool IsDucking { get; private set; } = false;
	[Sync] public bool IsRunning { get; private set; } = false;

	public GameObject Head { get; set; }
	private CharacterController Controller;

	protected override void OnStart() {
		Head = GameObject.Children.FirstOrDefault(go => go.Name == "Head");
		Controller = Components.Get<CharacterController>();
	}

	protected override void OnUpdate() {
		if (Network.IsProxy) return;

		if (!Controller.IsOnGround) UpdateJump(); else UpdateDuck();

		IsRunning = (RunByDefault == true ? !Input.Down("Run") : Input.Down("Run")) && !IsDucking;
		if ((AutoBhop ? Input.Down("Jump") : Input.Pressed("Jump")) && !IsDucking) OnJump();
	}

	protected override void OnFixedUpdate() {
		if (Network.IsProxy) return;

		Build();
		Move();
	}

	void Build() {
		WishVelocity = 0;

		var rot = Head.WorldRotation;

		if (Input.Down("Forward") && !Input.Down("Backward")) WishVelocity += rot.Forward;
		else if (Input.Down("Backward") && !Input.Down("Forward")) WishVelocity += rot.Backward;

		if (Input.Down("Left") && !Input.Down("Right")) WishVelocity += rot.Left;
		else if (Input.Down("Right") && !Input.Down("Left")) WishVelocity += rot.Right;

		WishVelocity = WishVelocity.WithZ(0);
		if (!WishVelocity.IsNearZeroLength) WishVelocity = WishVelocity.Normal;
		WishVelocity *= IsDucking ? DuckSpeed : (IsRunning ? RunSpeed : WalkSpeed);
	}

	void Move() {
		if (Controller is null) return;

		if (Controller.IsOnGround) {
			ApplyFriction();

			var wishdir = WishVelocity.WithZ(0);
			float wishspeed = wishdir.Length;
			if (wishspeed > 0f) wishdir /= wishspeed;

			AcceleratePlayer(wishdir, wishspeed);
		} else {
			var wishdir = WishVelocity.WithZ(0);

			float wishspeed = wishdir.Length;
			if (wishspeed > 0f) wishdir /= wishspeed;

			AirAcceleratePlayer(wishdir, wishspeed);

			var gravity = Scene.PhysicsWorld.Gravity * GravityScale;
			Controller.Velocity += gravity * Time.Delta;
		}

		Controller.Move();
	}

	void ApplyFriction() {
		var vel = Controller.Velocity;

		var speed = vel.Length;
		if (speed < 0.1f) return;

		float drop = 0f;
		if (Controller.IsOnGround) {
			float control = MathF.Max(speed, StopSpeed);
			drop = control * Friction * Time.Delta; // * SurfaceFriction
		}

		float newspeed = MathF.Max(speed - drop, 0);
		if (newspeed != speed) {
			newspeed /= speed;

			vel.x *= newspeed;
			vel.y *= newspeed;
			vel.z *= newspeed;
		}

		Controller.Velocity = vel;
	}

	void AcceleratePlayer(in Vector3 wishdir, float wishspeed) {
		var vel = Controller.Velocity;
		float currentspeed = vel.Dot(wishdir);

		float addspeed = wishspeed - currentspeed;
		if (addspeed <= 0f) return;

		float accelspeed = Accelerate * wishspeed * Time.Delta; // * SurfaceFriction
		if (accelspeed > addspeed) accelspeed = addspeed;

		vel += wishdir * accelspeed;
	
		Controller.Velocity = vel;
	}

	void AirAcceleratePlayer(in Vector3 wishdir, float wishspeed) {
		var vel = Controller.Velocity;
		float currentspeed = vel.Dot(wishdir);

		float wishspd = wishspeed;
		if (wishspd > AirMaxWishSpeed)
			wishspd = AirMaxWishSpeed;

		float addspeed = wishspd - currentspeed;
		if (addspeed <= 0f) return;

		float accelspeed = AirAccelerate * wishspeed * Time.Delta; // * SurfaceFriction
		if (accelspeed > addspeed) accelspeed = addspeed;

		vel += wishdir * accelspeed;
		WishVelocity += wishdir * accelspeed;

		Controller.Velocity = vel;
	}

	void OnJump() {
		if (!Controller.IsOnGround) return;

		Controller.Velocity = Controller.Velocity.WithZ(0);
		Controller.Punch(Vector3.Up * JumpPower);
	}

	void UpdateJump() {
		if (Controller is null) return;
		if (!Input.Pressed("Duck")) return;

		IsDucking = true;
		Controller.Height /= 2f;
		Controller.WorldPosition += Vector3.Up * Controller.Height;
	}

	void UpdateDuck() {
		if (Controller is null) return;

		if (Input.Pressed("Duck") && !IsDucking) {
			IsDucking = true;
			Controller.Height /= 2f;
		}

		if (!Input.Down("Duck") && IsDucking) {
			var tr = Scene.Trace.Ray(Controller.WorldPosition + Vector3.Up * 16f, Controller.WorldPosition + Vector3.Up * (Controller.Height * 2f))
				.IgnoreGameObject(GameObject)
				.IgnoreGameObject(Head)
				.Size(Controller.Radius)
				.Run();

			if (!tr.Hit) {
				IsDucking = false;
				Controller.Height *= 2f;
			}
		}
	}
}