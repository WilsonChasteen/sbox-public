namespace Sandbox;

using NativeEngine;
using System.Linq;

/// <summary>
/// Writes per-scene Disco GI settings into render attributes.
/// </summary>
sealed class DiscoGISystem : GameObjectSystem<DiscoGISystem>
{
	private bool _dirty = true;

	private static bool _capabilitiesInitialized;
	private static bool _hasHardwareRayTracing;
	private static bool _isVulkan;

	public DiscoGISystem( Scene scene ) : base( scene )
	{
		Listen( Stage.FinishUpdate, 0, UpdateSettings, "UpdateDiscoGI" );
	}

	public override void Dispose()
	{
		ApplyDisabled( Scene?.RenderAttributes );
		base.Dispose();
	}

	internal void MarkDirty()
	{
		_dirty = true;
	}

	private void UpdateSettings()
	{
		if ( Application.IsHeadless || !_dirty )
			return;

		if ( Scene?.RenderAttributes is null )
			return;

		_dirty = false;
		EnsureCapabilities();

		var active = Scene
			.GetAll<DiscoGI>()
			.Where( x => x is { Active: true, Enable: true } )
			.OrderByDescending( x => x.Priority )
			.FirstOrDefault();

		if ( active is null )
		{
			ApplyDisabled( Scene.RenderAttributes );
			return;
		}

		if ( active.PipelineTraceLog && !_hasHardwareRayTracing && !Application.IsHeadless )
		{
			Log.Warning( "[DiscoGI] Hardware Raytracing is not supported or disabled. Using fallback software tracing." );
		}

		ApplyData( Scene.RenderAttributes, active.BuildRuntimeData( _hasHardwareRayTracing, _isVulkan ) );
	}

	private static void EnsureCapabilities()
	{
		if ( _capabilitiesInitialized )
			return;

		_capabilitiesInitialized = true;

		try
		{
			_hasHardwareRayTracing = g_pRenderDevice.IsRayTracingSupported();
			_isVulkan = g_pRenderDevice.GetRenderDeviceAPI() == RenderDeviceAPI_t.RENDER_DEVICE_API_VULKAN;
		}
		catch
		{
			_hasHardwareRayTracing = false;
			_isVulkan = false;
		}
	}

	private static void ApplyDisabled( RenderAttributes attributes )
	{
		if ( attributes is null )
			return;

		attributes.Set( "DiscoGI_Enabled", false );
		attributes.Set( "DiscoGI_ResolutionScale", 0.5f );
		attributes.Set( "DiscoGI_UpdateFraction", 1.0f );
		attributes.Set( "DiscoGI_TemporalBlend", 0.9f );
		attributes.Set( "DiscoGI_BounceStrength", 0.75f );
		attributes.Set( "DiscoGI_PipelineTrace", false );
		attributes.Set( "DiscoGI_DebugView", 0 );
		attributes.Set( "DiscoGI_PipelineTraceLog", false );
	}

	private static void ApplyData( RenderAttributes attributes, DiscoGIRuntimeData data )
	{
		attributes.Set( "DiscoGI_Enabled", data.Enabled );
		attributes.Set( "DiscoGI_ResolutionScale", data.ResolutionScale );
		attributes.Set( "DiscoGI_UpdateFraction", data.UpdateFraction );
		attributes.Set( "DiscoGI_TemporalBlend", data.TemporalBlend );
		attributes.Set( "DiscoGI_BounceStrength", data.BounceStrength );
		attributes.Set( "DiscoGI_PipelineTrace", data.PipelineTrace );
		attributes.Set( "DiscoGI_DebugView", data.DebugView );
		attributes.Set( "DiscoGI_PipelineTraceLog", data.PipelineTraceLog );
	}
}
