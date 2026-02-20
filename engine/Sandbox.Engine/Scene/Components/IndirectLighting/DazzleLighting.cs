namespace Sandbox;

using System;

/// <summary>
/// Authoring component for the Dazzle direct+indirect lighting subsystem.
/// </summary>
[Expose]
[Title( "Dazzle Lighting" )]
[Category( "Rendering" )]
[Icon( "flare" )]
[Description( "Configures Dazzle quality, intensity, and fallback behavior for this scene." )]
public sealed class DazzleLighting : Component, Component.ExecuteInEditor, Component.DontExecuteOnServer
{
	public enum DazzleQuality
	{
		Off = 0,
		Performance = 1,
		Balanced = 2,
		Cinematic = 3
	}

	public enum DazzleGIDebugView
	{
		Off = 0,
		TraceState = 1,
		HistoryRadiance = 2,
		NearCascade = 3,
		FarCascade = 4
	}

	[Property, MakeDirty]
	public bool EnableDazzle { get; set; } = true;

	[Property, MakeDirty]
	public DazzleQuality Quality { get; set; } = DazzleQuality.Balanced;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	public float DirectIntensity { get; set; } = 1.0f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	public float IndirectIntensity { get; set; } = 1.0f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Stability" )]
	public float TemporalStability { get; set; } = 0.9f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Fallbacks" )]
	public float FallbackStrength { get; set; } = 0.8f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Indirect GI" )]
	public float DDGIBlend { get; set; } = 1.0f;

	[Property, MakeDirty]
	[Group( "Radiance Cascades" )]
	public bool EnableRadianceGI { get; set; } = true;

	[Property, Range( 0.25f, 1.0f ), MakeDirty]
	[Group( "Radiance Cascades" )]
	public float CascadeResolutionScale { get; set; } = 0.5f;

	[Property, Range( 0.25f, 1.0f ), MakeDirty]
	[Group( "Radiance Cascades" )]
	public float CascadeUpdateFraction { get; set; } = 1.0f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Radiance Cascades" )]
	public float CascadeTemporalBlend { get; set; } = 0.9f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	[Group( "Radiance Cascades" )]
	public float CascadeBounceStrength { get; set; } = 0.75f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float MultiBounceInfluence { get; set; } = 0.65f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float EmissiveBlend { get; set; } = 1.0f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float VolumetricBlend { get; set; } = 0.85f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float ScreenSpaceBlend { get; set; } = 0.8f;

	[Property, Range( 0.1f, 4.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float ExposureCompensation { get; set; } = 1.0f;

	[Property, Range( 1.0f, 24.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float WhitePoint { get; set; } = 8.0f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	[Group( "Physical Accumulation" )]
	public float TonemapShoulder { get; set; } = 0.75f;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public bool EnableGIPipelineTrace { get; set; } = false;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public DazzleGIDebugView GIDebugView { get; set; } = DazzleGIDebugView.Off;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public bool GIPipelineTraceLog { get; set; } = false;

	[Property, Range( -100, 100 ), MakeDirty]
	[Group( "Advanced" )]
	public int Priority { get; set; } = 0;

	protected override void OnEnabled()
	{
		base.OnEnabled();
		MarkSystemDirty();
	}

	protected override void OnDisabled()
	{
		base.OnDisabled();
		MarkSystemDirty();
	}

	protected override void OnDirty()
	{
		base.OnDirty();
		MarkSystemDirty();
	}

	internal DazzleLightingRuntimeData BuildRuntimeData( bool hasHardwareRayTracing, bool isVulkan )
	{
		var quality = EnableDazzle ? Quality : DazzleQuality.Off;

		float fallbackStrength = Math.Clamp( FallbackStrength, 0.0f, 1.0f );
		if ( !hasHardwareRayTracing )
			fallbackStrength = MathF.Max( fallbackStrength, 0.65f );
		if ( !isVulkan )
			fallbackStrength = MathF.Max( fallbackStrength, 0.75f );

		float qualityScale = quality switch
		{
			DazzleQuality.Performance => 0.7f,
			DazzleQuality.Balanced => 0.85f,
			DazzleQuality.Cinematic => 1.0f,
			_ => 0.0f
		};

		float cascadeResolutionScale = Math.Clamp( CascadeResolutionScale, 0.25f, 1.0f );
		float cascadeUpdateFraction = Math.Clamp( CascadeUpdateFraction, 0.25f, 1.0f );
		float cascadeTemporalBlend = Math.Clamp( CascadeTemporalBlend, 0.0f, 1.0f );
		float cascadeBounceStrength = Math.Clamp( CascadeBounceStrength, 0.0f, 2.0f );

		// Trim GI budgets gracefully on lower-end GPUs.
		if ( !hasHardwareRayTracing )
		{
			cascadeResolutionScale = Math.Min( cascadeResolutionScale, 0.65f );
			cascadeUpdateFraction = Math.Min( cascadeUpdateFraction, 0.75f );
			cascadeTemporalBlend = Math.Max( cascadeTemporalBlend, 0.9f );
		}

		if ( !isVulkan )
		{
			cascadeResolutionScale = Math.Min( cascadeResolutionScale, 0.5f );
			cascadeUpdateFraction = Math.Min( cascadeUpdateFraction, 0.5f );
			cascadeTemporalBlend = Math.Max( cascadeTemporalBlend, 0.92f );
		}

		cascadeResolutionScale = Math.Max( 0.25f, cascadeResolutionScale * Math.Max( qualityScale, 0.5f ) );
		cascadeBounceStrength *= Math.Max( qualityScale, 0.5f );

		return new DazzleLightingRuntimeData
		{
			Enabled = quality != DazzleQuality.Off,
			Quality = (int)quality,
			DirectIntensity = Math.Clamp( DirectIntensity, 0.0f, 2.0f ),
			IndirectIntensity = Math.Clamp( IndirectIntensity, 0.0f, 2.0f ),
			Stability = Math.Clamp( TemporalStability, 0.0f, 1.0f ),
			FallbackStrength = fallbackStrength,
			DDGIBlend = Math.Clamp( DDGIBlend, 0.0f, 1.0f ),
			GIEnabled = EnableRadianceGI && quality != DazzleQuality.Off,
			GIResolutionScale = cascadeResolutionScale,
			GIUpdateFraction = cascadeUpdateFraction,
			GITemporalBlend = cascadeTemporalBlend,
			GIBounceStrength = cascadeBounceStrength,
			MultiBounceInfluence = Math.Clamp( MultiBounceInfluence, 0.0f, 1.0f ),
			EmissiveBlend = Math.Clamp( EmissiveBlend, 0.0f, 2.0f ),
			VolumetricBlend = Math.Clamp( VolumetricBlend, 0.0f, 2.0f ),
			ScreenSpaceBlend = Math.Clamp( ScreenSpaceBlend, 0.0f, 2.0f ),
			ExposureCompensation = Math.Clamp( ExposureCompensation, 0.1f, 4.0f ),
			WhitePoint = Math.Clamp( WhitePoint, 1.0f, 24.0f ),
			TonemapShoulder = Math.Clamp( TonemapShoulder, 0.0f, 1.0f ),
			GIPipelineTrace = EnableGIPipelineTrace,
			GIDebugView = (int)GIDebugView,
			GIPipelineTraceLog = GIPipelineTraceLog
		};
	}

	private void MarkSystemDirty()
	{
		Scene?.Get<DazzleLightingSystem>()?.MarkDirty();
	}
}

internal struct DazzleLightingRuntimeData
{
	public bool Enabled;
	public int Quality;
	public float DirectIntensity;
	public float IndirectIntensity;
	public float Stability;
	public float FallbackStrength;
	public float DDGIBlend;
	public bool GIEnabled;
	public float GIResolutionScale;
	public float GIUpdateFraction;
	public float GITemporalBlend;
	public float GIBounceStrength;
	public float MultiBounceInfluence;
	public float EmissiveBlend;
	public float VolumetricBlend;
	public float ScreenSpaceBlend;
	public float ExposureCompensation;
	public float WhitePoint;
	public float TonemapShoulder;
	public bool GIPipelineTrace;
	public int GIDebugView;
	public bool GIPipelineTraceLog;
}
