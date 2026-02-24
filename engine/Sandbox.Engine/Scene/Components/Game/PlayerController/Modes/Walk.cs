namespace Sandbox.Movement;

/// <summary>
/// The character is walking
/// </summary>
[Icon( "transfer_within_a_station" ), Group( "Movement" ), Title( "MoveMode - Walk" ), Alias( "Sandbox.PhysicsCharacterMode.PhysicsCharacterWalkMode" )]
public partial class MoveModeWalk : MoveMode
{
	[Property] public int Priority { get; set; } = 0;

	[Property] public float GroundAngle { get; set; } = 45.0f;
	[Property] public float StepUpHeight { get; set; } = 18.0f;
	[Property] public float StepDownHeight { get; set; } = 18.0f;
	[Property, Group( "Movement Tuning" ), Range( 1, 40 )] public float GroundAcceleration { get; set; } = 14.0f;
	[Property, Group( "Movement Tuning" ), Range( 0, 20 )] public float GroundFriction { get; set; } = 6.0f;
	[Property, Group( "Movement Tuning" ), Range( 0, 400 )] public float StopSpeed { get; set; } = 100.0f;
	[Property, Group( "Movement Tuning" ), Range( 0, 40 )] public float AirAcceleration { get; set; } = 8.0f;
	[Property, Group( "Movement Tuning" ), Range( 0, 200 )] public float AirMaxWishSpeed { get; set; } = 35.0f;
	[Property, Group( "Movement Tuning" ), Range( 0, 2 )] public float AirControl { get; set; } = 0.3f;
	[Property, Group( "Flow" ), Range( 0, 500 )] public float FlowBuildSpeed { get; set; } = 220.0f;
	[Property, Group( "Flow" ), Range( 0.1f, 30 )] public float FlowBuildRate { get; set; } = 8.0f;
	[Property, Group( "Flow" ), Range( 0.1f, 30 )] public float FlowDecayRate { get; set; } = 2.5f;
	[Property, Group( "Flow" ), Range( 0, 2 )] public float FlowAccelerationBonus { get; set; } = 0.45f;
	[Property, Group( "Flow" ), Range( 0, 2 )] public float FlowAirControlBonus { get; set; } = 0.6f;
	[Property, Group( "Slide" ), Range( 0, 700 )] public float SlideEnterSpeed { get; set; } = 220.0f;
	[Property, Group( "Slide" ), Range( 0, 600 )] public float SlideExitSpeed { get; set; } = 130.0f;
	[Property, Group( "Slide" ), Range( 0, 400 )] public float SlideBoost { get; set; } = 90.0f;
	[Property, Group( "Slide" ), Range( 0, 20 )] public float SlideFriction { get; set; } = 1.5f;
	[Property, Group( "Slide" ), Range( 0, 40 )] public float SlideSteerAcceleration { get; set; } = 14.0f;
	[Property, Group( "Slide" ), Range( 0, 3 )] public float SlideSteerFactor { get; set; } = 1.1f;
	[Property, Group( "Slope" ), Range( 0, 2000 )] public float SlopeGravity { get; set; } = 700.0f;
	[Property, Group( "Slope" ), Range( 0, 2 )] public float SlopeJumpCarry { get; set; } = 0.2f;
	[Property, Group( "Bunny Hop Assist" )] public bool EnableBhopAssist { get; set; } = true;
	[Property, Group( "Bunny Hop Assist" ), Range( 1, 20 )] public int BhopMaxStacks { get; set; } = 8;
	[Property, Group( "Bunny Hop Assist" ), Range( 0.01f, 0.35f )] public float BhopPerfectJumpWindow { get; set; } = 0.12f;
	[Property, Group( "Bunny Hop Assist" ), Range( 0.05f, 0.6f )] public float BhopLandingForgivenessTime { get; set; } = 0.2f;
	[Property, Group( "Bunny Hop Assist" ), Range( 0.1f, 1.0f )] public float BhopMinLandingFrictionMultiplier { get; set; } = 0.35f;
	[Property, Group( "Bunny Hop Assist" ), Range( 0, 500 )] public float BhopMinSpeed { get; set; } = 140.0f;
	[Property, Group( "Bunny Hop Assist" ), Range( 0.1f, 2.0f )] public float BhopStackDecayDelay { get; set; } = 0.45f;
	[Property, Group( "Bunny Hop Assist" ), Range( 0.1f, 10.0f )] public float BhopStackDecayRate { get; set; } = 2.0f;

	float _flow;
	bool _isSliding;
	Vector3 _slideDirection;
	float _bhopStacks;
	bool _wasGrounded;
	TimeSince _timeSinceLanded = 999;


	public override bool AllowGrounding => true;
	public override bool AllowFalling => true;

	public override int Score( PlayerController controller ) => Priority;

	public override void OnModeBegin()
	{
		base.OnModeBegin();
		_wasGrounded = Controller.IsOnGround;
	}

	public override void AddVelocity()
	{
		var body = Controller.Body;
		if ( !body.IsValid() )
			return;

		var inputWish = Controller.WishVelocity.WithZ( 0 );
		Controller.WishVelocity = inputWish;

		var relativeVelocity = body.Velocity - Controller.GroundVelocity;
		var vertical = relativeVelocity.z;
		var planarVelocity = relativeVelocity.WithZ( 0 );
		var planarSpeed = planarVelocity.Length;

		var wishSpeed = inputWish.Length;
		var wishDir = wishSpeed > 0.001f ? inputWish / wishSpeed : 0;

		UpdateGroundTransitions();
		UpdateFlow( planarSpeed, wishSpeed );
		UpdateSlideState( planarSpeed );
		UpdateBhopStackDecay();

		if ( Controller.IsOnGround )
		{
			if ( _isSliding )
			{
				ApplySlide( ref planarVelocity, wishDir, wishSpeed );
			}
			else
			{
				ApplyGroundFriction( ref planarVelocity );
				Accelerate( ref planarVelocity, wishDir, wishSpeed, GroundAcceleration * (1.0f + _flow * FlowAccelerationBonus) );
			}

			ApplySlopeForces( ref planarVelocity );
		}
		else
		{
			var cappedAirWishSpeed = AirMaxWishSpeed > 0 ? MathF.Min( wishSpeed, AirMaxWishSpeed ) : wishSpeed;
			Accelerate( ref planarVelocity, wishDir, cappedAirWishSpeed, AirAcceleration );
			ApplyAirControl( ref planarVelocity, wishDir, wishSpeed, AirControl + (_flow * FlowAirControlBonus) );
		}

		var finalVelocity = planarVelocity + Controller.GroundVelocity;
		finalVelocity.z = Controller.IsOnGround ? body.Velocity.z : vertical;
		body.Velocity = finalVelocity;
	}

	public override void PrePhysicsStep()
	{
		base.PrePhysicsStep();

		if ( StepUpHeight > 0 )
		{
			TrySteppingUp( StepUpHeight );
		}
	}

	public override void PostPhysicsStep()
	{
		base.PostPhysicsStep();

		StickToGround( StepDownHeight );
	}

	public override bool IsStandableSurface( in SceneTraceResult result )
	{
		if ( Vector3.GetAngle( Vector3.Up, result.Normal ) > GroundAngle )
			return false;

		return true;
	}

	public override Vector3 UpdateMove( Rotation eyes, Vector3 input )
	{
		// ignore pitch when walking
		eyes = eyes.Angles() with { pitch = 0 };

		return base.UpdateMove( eyes, input );
	}

	public override void OnJumped()
	{
		base.OnJumped();

		if ( !EnableBhopAssist )
			return;

		if ( !Controller.IsOnGround )
			return;

		var speed = Controller.Velocity.WithZ( 0 ).Length;
		bool quickJump = _timeSinceLanded <= BhopPerfectJumpWindow;
		bool fastEnough = speed >= BhopMinSpeed;

		if ( quickJump && fastEnough )
		{
			_bhopStacks = (_bhopStacks + 1.0f).Clamp( 0.0f, Math.Max( 1, BhopMaxStacks ) );
		}
		else if ( _timeSinceLanded > BhopPerfectJumpWindow * 1.5f )
		{
			_bhopStacks = MathF.Max( 0.0f, _bhopStacks - 1.0f );
		}
	}

	void UpdateFlow( float planarSpeed, float wishSpeed )
	{
		float flowTarget = 0.0f;

		if ( planarSpeed > FlowBuildSpeed * 0.4f )
		{
			flowTarget = ((planarSpeed - FlowBuildSpeed * 0.4f) / MathF.Max( FlowBuildSpeed, 1.0f )).Clamp( 0.0f, 1.0f );
		}

		if ( wishSpeed < 5.0f && Controller.IsOnGround )
		{
			flowTarget *= 0.25f;
		}

		var rate = flowTarget > _flow ? FlowBuildRate : FlowDecayRate;
		_flow = _flow.LerpTo( flowTarget, Time.Delta * rate );
	}

	void UpdateSlideState( float planarSpeed )
	{
		if ( !Controller.IsOnGround )
		{
			_isSliding = false;
			return;
		}

		if ( _isSliding )
		{
			if ( !Controller.IsDucking || planarSpeed < SlideExitSpeed )
			{
				_isSliding = false;
			}

			return;
		}

		if ( !Controller.IsDucking ) return;
		if ( !Input.Pressed( "duck" ) ) return;
		if ( planarSpeed < SlideEnterSpeed ) return;

		_isSliding = true;
		_slideDirection = Controller.Velocity.WithZ( 0 ).Normal;
		if ( _slideDirection.IsNearlyZero() )
		{
			_slideDirection = Controller.EyeAngles.ToRotation().Forward.WithZ( 0 ).Normal;
		}

		Controller.Body.Velocity += _slideDirection * SlideBoost;
	}

	void ApplyGroundFriction( ref Vector3 velocity )
	{
		var speed = velocity.Length;
		if ( speed <= 0.001f )
		{
			velocity = 0;
			return;
		}

		var frictionScale = MathF.Max( Controller.GroundFriction, 0.05f );
		var control = MathF.Max( speed, StopSpeed );
		var drop = control * GroundFriction * frictionScale * Time.Delta;
		drop *= GetBhopFrictionMultiplier();
		var newSpeed = MathF.Max( speed - drop, 0f );

		if ( newSpeed == speed )
			return;

		velocity *= newSpeed / speed;
	}

	void UpdateGroundTransitions()
	{
		if ( Controller.IsOnGround && !_wasGrounded )
		{
			_timeSinceLanded = 0;
		}

		_wasGrounded = Controller.IsOnGround;
	}

	void UpdateBhopStackDecay()
	{
		if ( !EnableBhopAssist )
		{
			_bhopStacks = 0.0f;
			return;
		}

		if ( !Controller.IsOnGround )
			return;

		if ( _timeSinceLanded < BhopStackDecayDelay )
			return;

		float decay = BhopStackDecayRate * Time.Delta;
		_bhopStacks = MathF.Max( 0.0f, _bhopStacks - decay );
	}

	float GetBhopFrictionMultiplier()
	{
		if ( !EnableBhopAssist )
			return 1.0f;

		if ( _bhopStacks <= 0.001f )
			return 1.0f;

		if ( !Controller.IsOnGround || _timeSinceLanded > BhopLandingForgivenessTime )
			return 1.0f;

		float stackFraction = (_bhopStacks / (float)Math.Max( 1, BhopMaxStacks )).Clamp( 0.0f, 1.0f );
		float multiplier = 1.0f.LerpTo( BhopMinLandingFrictionMultiplier, stackFraction );
		return multiplier.Clamp( 0.05f, 1.0f );
	}

	void Accelerate( ref Vector3 velocity, Vector3 wishDir, float wishSpeed, float acceleration )
	{
		if ( wishSpeed <= 0.001f || wishDir.IsNearlyZero() )
			return;

		var currentSpeed = velocity.Dot( wishDir );
		var addSpeed = wishSpeed - currentSpeed;
		if ( addSpeed <= 0 )
			return;

		var accelSpeed = acceleration * wishSpeed * Time.Delta;
		accelSpeed = MathF.Min( accelSpeed, addSpeed );

		velocity += wishDir * accelSpeed;
	}

	void ApplyAirControl( ref Vector3 velocity, Vector3 wishDir, float wishSpeed, float airControl )
	{
		if ( airControl <= 0 || wishSpeed <= 0.001f || wishDir.IsNearlyZero() )
			return;

		var speed = velocity.Length;
		if ( speed <= 0.001f )
			return;

		var direction = velocity / speed;
		var dot = direction.Dot( wishDir );
		if ( dot <= 0 )
			return;

		var controlAmount = 32.0f * airControl * dot * dot * Time.Delta;
		direction = direction * speed + wishDir * controlAmount;
		direction = direction.Normal;

		velocity = direction * speed;
	}

	void ApplySlide( ref Vector3 velocity, Vector3 wishDir, float wishSpeed )
	{
		var speed = velocity.Length;
		if ( speed <= 0.001f )
			return;

		var drop = MathF.Max( speed, StopSpeed ) * SlideFriction * Time.Delta;
		var newSpeed = MathF.Max( speed - drop, 0f );
		velocity = velocity * (newSpeed / speed);

		if ( !_slideDirection.IsNearlyZero() )
		{
			var align = velocity.Dot( _slideDirection );
			if ( align < newSpeed * 0.7f )
			{
				velocity = velocity + _slideDirection * (newSpeed * 0.7f - align);
			}
		}

		if ( wishSpeed > 1.0f && !wishDir.IsNearlyZero() )
		{
			var steerTarget = (_slideDirection + wishDir * SlideSteerFactor).Normal;
			_slideDirection = Vector3.Lerp( _slideDirection, steerTarget, Time.Delta * SlideSteerAcceleration ).Normal;

			var steerAccel = SlideSteerAcceleration * wishSpeed * Time.Delta;
			velocity += _slideDirection * steerAccel;
		}
	}

	void ApplySlopeForces( ref Vector3 velocity )
	{
		if ( !TryGetGroundNormal( out var normal ) )
			return;

		float steepness = (1.0f - normal.Dot( Vector3.Up )).Clamp( 0.0f, 1.0f );
		if ( steepness <= 0.001f )
			return;

		var downhill = Vector3.Down - normal * Vector3.Down.Dot( normal );
		var downhillLength = downhill.Length;
		if ( downhillLength <= 0.001f )
			return;

		downhill /= downhillLength;

		var slopeImpulse = SlopeGravity * steepness * Time.Delta;
		if ( _isSliding )
		{
			slopeImpulse *= 1.35f;
		}

		velocity += downhill * slopeImpulse;

		if ( !Controller.IsDucking && Controller.TimeSinceGrounded < 0.05f && Controller.Velocity.z > 100 )
		{
			velocity += downhill * (slopeImpulse * SlopeJumpCarry);
		}
	}

	bool TryGetGroundNormal( out Vector3 normal )
	{
		normal = Vector3.Up;
		if ( !Controller.IsOnGround )
			return false;

		var from = Controller.WorldPosition + Vector3.Up * 3.0f;
		var to = Controller.WorldPosition + Vector3.Down * (StepDownHeight + 6.0f);
		var tr = Controller.TraceBody( from, to, 0.95f, 0.5f );
		if ( !tr.Hit )
			return false;

		normal = tr.Normal;
		return true;
	}
}
