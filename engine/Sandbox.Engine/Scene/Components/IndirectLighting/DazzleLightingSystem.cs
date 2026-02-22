namespace Sandbox;

using NativeEngine;
using System.Linq;

/// <summary>
/// Writes per-scene Dazzle lighting settings into render attributes.
/// </summary>
sealed class DazzleLightingSystem : GameObjectSystem<DazzleLightingSystem>
{
	private bool _dirty = true;

	private static bool _capabilitiesInitialized;
	private static bool _hasHardwareRayTracing;
	private static bool _isVulkan;

	public DazzleLightingSystem( Scene scene ) : base( scene )
	{
		Listen( Stage.FinishUpdate, 0, UpdateSettings, "UpdateDazzleLighting" );
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
			.GetAll<DazzleLighting>()
			.Where( x => x is { Active: true, EnableDazzle: true } )
			.OrderByDescending( x => x.Priority )
			.FirstOrDefault();

		if ( active is null )
		{
			ApplyDisabled( Scene.RenderAttributes );
			return;
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

		attributes.Set( "Dazzle_Enabled", false );
		attributes.Set( "Dazzle_Quality", 0 );
		attributes.Set( "Dazzle_DirectIntensity", 1.0f );
		attributes.Set( "Dazzle_IndirectIntensity", 1.0f );
		attributes.Set( "Dazzle_Stability", 0.9f );
		attributes.Set( "Dazzle_FallbackStrength", 1.0f );
		attributes.Set( "Dazzle_DDGIBlend", 1.0f );
		attributes.Set( "Dazzle_GIEnable", false );
		attributes.Set( "Dazzle_GIResolutionScale", 0.5f );
		attributes.Set( "Dazzle_GIUpdateFraction", 1.0f );
		attributes.Set( "Dazzle_GITemporalBlend", 0.9f );
		attributes.Set( "Dazzle_GIBounceStrength", 0.75f );
		attributes.Set( "Dazzle_GIVoxelFeedback", 0.9f );
		attributes.Set( "Dazzle_GIDirectionalCache", 0.7f );
		attributes.Set( "Dazzle_MultiBounceInfluence", 0.65f );
		attributes.Set( "Dazzle_EmissiveBlend", 1.0f );
		attributes.Set( "Dazzle_VolumetricBlend", 0.85f );
		attributes.Set( "Dazzle_ScreenSpaceBlend", 0.8f );
		attributes.Set( "Dazzle_ExposureCompensation", 1.0f );
		attributes.Set( "Dazzle_WhitePoint", 8.0f );
		attributes.Set( "Dazzle_TonemapShoulder", 0.75f );
		attributes.Set( "Dazzle_GIPipelineTrace", false );
		attributes.Set( "Dazzle_GIDebugView", 0 );
		attributes.Set( "Dazzle_GIPipelineTraceLog", false );
	}

	private static void ApplyData( RenderAttributes attributes, DazzleLightingRuntimeData data )
	{
		attributes.Set( "Dazzle_Enabled", data.Enabled );
		attributes.Set( "Dazzle_Quality", data.Quality );
		attributes.Set( "Dazzle_DirectIntensity", data.DirectIntensity );
		attributes.Set( "Dazzle_IndirectIntensity", data.IndirectIntensity );
		attributes.Set( "Dazzle_Stability", data.Stability );
		attributes.Set( "Dazzle_FallbackStrength", data.FallbackStrength );
		attributes.Set( "Dazzle_DDGIBlend", data.DDGIBlend );
		attributes.Set( "Dazzle_GIEnable", data.GIEnabled );
		attributes.Set( "Dazzle_GIResolutionScale", data.GIResolutionScale );
		attributes.Set( "Dazzle_GIUpdateFraction", data.GIUpdateFraction );
		attributes.Set( "Dazzle_GITemporalBlend", data.GITemporalBlend );
		attributes.Set( "Dazzle_GIBounceStrength", data.GIBounceStrength );
		attributes.Set( "Dazzle_GIVoxelFeedback", data.GIVoxelFeedback );
		attributes.Set( "Dazzle_GIDirectionalCache", data.GIDirectionalCache );
		attributes.Set( "Dazzle_MultiBounceInfluence", data.MultiBounceInfluence );
		attributes.Set( "Dazzle_EmissiveBlend", data.EmissiveBlend );
		attributes.Set( "Dazzle_VolumetricBlend", data.VolumetricBlend );
		attributes.Set( "Dazzle_ScreenSpaceBlend", data.ScreenSpaceBlend );
		attributes.Set( "Dazzle_ExposureCompensation", data.ExposureCompensation );
		attributes.Set( "Dazzle_WhitePoint", data.WhitePoint );
		attributes.Set( "Dazzle_TonemapShoulder", data.TonemapShoulder );
		attributes.Set( "Dazzle_GIPipelineTrace", data.GIPipelineTrace );
		attributes.Set( "Dazzle_GIDebugView", data.GIDebugView );
		attributes.Set( "Dazzle_GIPipelineTraceLog", data.GIPipelineTraceLog );
	}
}
