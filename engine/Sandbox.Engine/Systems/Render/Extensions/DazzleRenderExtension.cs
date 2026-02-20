using System;
using NativeEngine;
using System.Collections.Generic;

namespace Sandbox.Rendering;

/// <summary>
/// Injects runtime Dazzle capability attributes for each rendered view.
/// Scene and camera authored settings still control the final quality level.
/// </summary>
internal sealed class DazzleRenderExtension : RenderExtension
{
	private sealed class ViewState
	{
		public DazzleRadianceCascadeLayer CascadeLayer { get; } = new();
	}

	private static bool _capabilitiesInitialized;
	private static bool _hasHardwareRayTracing;
	private static bool _isVulkan;
	private readonly Dictionary<int, ViewState> _viewStates = new();

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

	public override void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		if ( !view.IsValid ) return;
		EnsureCapabilities();

		var attrs = view.GetRenderAttributesPtr();
		if ( !attrs.IsValid ) return;

		attrs.SetBoolValue( "Dazzle_HasHardwareRT", _hasHardwareRayTracing );
		attrs.SetBoolValue( "Dazzle_IsVulkan", _isVulkan );

		// Keep Dazzle attribute keys initialized so all shaders read stable defaults.
		attrs.SetBoolValue( "Dazzle_Enabled", attrs.GetBoolValue( "Dazzle_Enabled", false ) );
		attrs.SetIntValue( "Dazzle_Quality", attrs.GetIntValue( "Dazzle_Quality", 2 ) );
		attrs.SetFloatValue( "Dazzle_DirectIntensity", attrs.GetFloatValue( "Dazzle_DirectIntensity", 1.0f ) );
		attrs.SetFloatValue( "Dazzle_IndirectIntensity", attrs.GetFloatValue( "Dazzle_IndirectIntensity", 1.0f ) );
		attrs.SetFloatValue( "Dazzle_Stability", attrs.GetFloatValue( "Dazzle_Stability", 0.9f ) );
		attrs.SetFloatValue( "Dazzle_FallbackStrength", attrs.GetFloatValue( "Dazzle_FallbackStrength", 0.8f ) );
		attrs.SetFloatValue( "Dazzle_DDGIBlend", attrs.GetFloatValue( "Dazzle_DDGIBlend", 1.0f ) );
		attrs.SetBoolValue( "Dazzle_GIEnable", attrs.GetBoolValue( "Dazzle_GIEnable", true ) );
		attrs.SetFloatValue( "Dazzle_GIResolutionScale", attrs.GetFloatValue( "Dazzle_GIResolutionScale", 0.5f ) );
		attrs.SetFloatValue( "Dazzle_GIUpdateFraction", attrs.GetFloatValue( "Dazzle_GIUpdateFraction", 1.0f ) );
		attrs.SetFloatValue( "Dazzle_GITemporalBlend", attrs.GetFloatValue( "Dazzle_GITemporalBlend", 0.9f ) );
		attrs.SetFloatValue( "Dazzle_GIBounceStrength", attrs.GetFloatValue( "Dazzle_GIBounceStrength", 0.75f ) );
		attrs.SetFloatValue( "Dazzle_MultiBounceInfluence", attrs.GetFloatValue( "Dazzle_MultiBounceInfluence", 0.65f ) );
		attrs.SetFloatValue( "Dazzle_EmissiveBlend", attrs.GetFloatValue( "Dazzle_EmissiveBlend", 1.0f ) );
		attrs.SetFloatValue( "Dazzle_VolumetricBlend", attrs.GetFloatValue( "Dazzle_VolumetricBlend", 0.85f ) );
		attrs.SetFloatValue( "Dazzle_ScreenSpaceBlend", attrs.GetFloatValue( "Dazzle_ScreenSpaceBlend", 0.8f ) );
		attrs.SetFloatValue( "Dazzle_ExposureCompensation", attrs.GetFloatValue( "Dazzle_ExposureCompensation", 1.0f ) );
		attrs.SetFloatValue( "Dazzle_WhitePoint", attrs.GetFloatValue( "Dazzle_WhitePoint", 8.0f ) );
		attrs.SetFloatValue( "Dazzle_TonemapShoulder", attrs.GetFloatValue( "Dazzle_TonemapShoulder", 0.75f ) );
		attrs.SetBoolValue( "Dazzle_GIPipelineTrace", attrs.GetBoolValue( "Dazzle_GIPipelineTrace", false ) );
		attrs.SetIntValue( "Dazzle_GIDebugView", attrs.GetIntValue( "Dazzle_GIDebugView", 0 ) );
		attrs.SetBoolValue( "Dazzle_GIPipelineTraceLog", attrs.GetBoolValue( "Dazzle_GIPipelineTraceLog", false ) );
		attrs.SetIntValue( "Dazzle_GITraceFlags", attrs.GetIntValue( "Dazzle_GITraceFlags", 0 ) );
		attrs.SetIntValue( "Dazzle_GITraceFrame", attrs.GetIntValue( "Dazzle_GITraceFrame", 0 ) );
		attrs.SetIntValue( "Dazzle_GITraceNearIndex", attrs.GetIntValue( "Dazzle_GITraceNearIndex", 0 ) );
		attrs.SetIntValue( "Dazzle_GITraceFarIndex", attrs.GetIntValue( "Dazzle_GITraceFarIndex", 0 ) );
		attrs.SetIntValue( "Dazzle_GITraceHistoryIndex", attrs.GetIntValue( "Dazzle_GITraceHistoryIndex", 0 ) );

		bool dazzleEnabled = attrs.GetBoolValue( "Dazzle_Enabled", false );
		bool giEnabled = dazzleEnabled && attrs.GetBoolValue( "Dazzle_GIEnable", true );

		if ( giEnabled )
		{
			var viewState = GetOrCreateViewState( GetStateKey( view ) );
			viewState.CascadeLayer.PublishForShading( view, true );

			if ( attrs.GetBoolValue( "Dazzle_GIPipelineTrace", false ) )
			{
				Log.Info( $"[DazzleGI] GI active for view: {view.self.GetHashCode():X}" );
			}
		}
		else
		{
			attrs.SetIntValue( "Dazzle_GITextureIndex", 0 );
			attrs.SetBoolValue( "Dazzle_GIValid", false );
		}
	}

	public override void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		if ( !view.IsValid ) return;
		var attrs = view.GetRenderAttributesPtr();
		if ( !attrs.IsValid ) return;
		bool dazzleEnabled = attrs.GetBoolValue( "Dazzle_Enabled", false );
		bool giEnabled = dazzleEnabled && attrs.GetBoolValue( "Dazzle_GIEnable", true );
		if ( !giEnabled )
			return;

		var viewState = GetOrCreateViewState( GetStateKey( view ) );
		viewState.CascadeLayer.Setup( view, viewport );
		viewState.CascadeLayer.AddToView( view, viewport );
	}

	private static int GetStateKey( ISceneView view )
	{
		// Camera ID is stable across frames; fall back to pointer hash for non-camera views.
		int cameraId = view.m_ManagedCameraId;
		return cameraId != 0 ? cameraId : view.self.GetHashCode();
	}

	private ViewState GetOrCreateViewState( int key )
	{
		if ( !_viewStates.TryGetValue( key, out var state ) )
		{
			state = new ViewState();
			_viewStates.Add( key, state );
		}

		return state;
	}
}
