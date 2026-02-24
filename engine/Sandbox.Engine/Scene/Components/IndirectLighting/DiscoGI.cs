namespace Sandbox;

using System;

/// <summary>
/// Authoring component for the Disco Global Illumination subsystem.
/// </summary>
[Expose]
[Title( "Disco GI" )]
[Category( "Rendering" )]
[Icon( "lightbulb" )]
[Description( "Configures Disco Global Illumination quality and tracing." )]
public sealed class DiscoGI : Component, Component.ExecuteInEditor, Component.DontExecuteOnServer
{
	public enum DiscoGIDebugView
	{
		Off = 0,
		TraceState = 1,
		HistoryRadiance = 2,
		NearCascade = 3,
		FarCascade = 4
	}

	[Property, MakeDirty]
	public bool Enable { get; set; } = true;

	[Property, Range( 0.25f, 1.0f ), MakeDirty]
	public float ResolutionScale { get; set; } = 0.5f;

	[Property, Range( 0.25f, 1.0f ), MakeDirty]
	public float UpdateFraction { get; set; } = 1.0f;

	[Property, Range( 0.0f, 1.0f ), MakeDirty]
	public float TemporalBlend { get; set; } = 0.9f;

	[Property, Range( 0.0f, 2.0f ), MakeDirty]
	public float BounceStrength { get; set; } = 0.75f;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public bool EnablePipelineTrace { get; set; } = false;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public DiscoGIDebugView DebugView { get; set; } = DiscoGIDebugView.Off;

	[Property, MakeDirty]
	[Group( "Debug" )]
	public bool PipelineTraceLog { get; set; } = false;

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

	internal DiscoGIRuntimeData BuildRuntimeData( bool hasHardwareRayTracing, bool isVulkan )
	{
		float resolutionScale = Math.Clamp( ResolutionScale, 0.25f, 1.0f );
		float updateFraction = Math.Clamp( UpdateFraction, 0.25f, 1.0f );
		float temporalBlend = Math.Clamp( TemporalBlend, 0.0f, 1.0f );
		float bounceStrength = Math.Clamp( BounceStrength, 0.0f, 2.0f );

		if ( !hasHardwareRayTracing )
		{
			resolutionScale = Math.Min( resolutionScale, 0.65f );
			updateFraction = Math.Min( updateFraction, 0.75f );
			temporalBlend = Math.Max( temporalBlend, 0.9f );
		}

		if ( !isVulkan )
		{
			resolutionScale = Math.Min( resolutionScale, 0.5f );
			updateFraction = Math.Min( updateFraction, 0.5f );
			temporalBlend = Math.Max( temporalBlend, 0.92f );
		}

		return new DiscoGIRuntimeData
		{
			Enabled = Enable,
			ResolutionScale = resolutionScale,
			UpdateFraction = updateFraction,
			TemporalBlend = temporalBlend,
			BounceStrength = bounceStrength,
			PipelineTrace = EnablePipelineTrace,
			DebugView = (int)DebugView,
			PipelineTraceLog = PipelineTraceLog
		};
	}

	private void MarkSystemDirty()
	{
		Scene?.Get<DiscoGISystem>()?.MarkDirty();
	}
}

internal struct DiscoGIRuntimeData
{
	public bool Enabled;
	public float ResolutionScale;
	public float UpdateFraction;
	public float TemporalBlend;
	public float BounceStrength;
	public bool PipelineTrace;
	public int DebugView;
	public bool PipelineTraceLog;
}
