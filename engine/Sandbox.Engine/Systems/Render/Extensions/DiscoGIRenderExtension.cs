using System;
using NativeEngine;
using System.Collections.Generic;

namespace Sandbox.Rendering;

/// <summary>
/// Injects runtime Disco GI capability attributes for each rendered view and schedules the compute layer.
/// </summary>
internal sealed class DiscoGIRenderExtension : RenderExtension
{
	private sealed class ViewState
	{
		public DiscoGILayer Layer { get; } = new();
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

		// Keep Disco attribute keys initialized so all shaders read stable defaults.
		attrs.SetBoolValue( "DiscoGI_Enabled", attrs.GetBoolValue( "DiscoGI_Enabled", false ) );
		attrs.SetFloatValue( "DiscoGI_ResolutionScale", attrs.GetFloatValue( "DiscoGI_ResolutionScale", 0.5f ) );
		attrs.SetFloatValue( "DiscoGI_UpdateFraction", attrs.GetFloatValue( "DiscoGI_UpdateFraction", 1.0f ) );
		attrs.SetFloatValue( "DiscoGI_TemporalBlend", attrs.GetFloatValue( "DiscoGI_TemporalBlend", 0.9f ) );
		attrs.SetFloatValue( "DiscoGI_BounceStrength", attrs.GetFloatValue( "DiscoGI_BounceStrength", 0.75f ) );
		attrs.SetBoolValue( "DiscoGI_PipelineTrace", attrs.GetBoolValue( "DiscoGI_PipelineTrace", false ) );
		attrs.SetIntValue( "DiscoGI_DebugView", attrs.GetIntValue( "DiscoGI_DebugView", 0 ) );
		attrs.SetBoolValue( "DiscoGI_PipelineTraceLog", attrs.GetBoolValue( "DiscoGI_PipelineTraceLog", false ) );

		bool giEnabled = attrs.GetBoolValue( "DiscoGI_Enabled", false );

		if ( giEnabled )
		{
			var viewState = GetOrCreateViewState( GetStateKey( view ) );
			viewState.Layer.PublishForShading( view, true );

			if ( attrs.GetBoolValue( "DiscoGI_PipelineTrace", false ) )
			{
				Log.Info( $"[DiscoGI] GI active for view: {view.self.GetHashCode():X}" );
			}
		}
		else
		{
			attrs.SetIntValue( "DiscoGI_TextureIndex", 0 );
			attrs.SetBoolValue( "DiscoGI_Valid", false );
		}
	}

	public override void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		if ( !view.IsValid ) return;
		var attrs = view.GetRenderAttributesPtr();
		if ( !attrs.IsValid ) return;
		bool giEnabled = attrs.GetBoolValue( "DiscoGI_Enabled", false );
		if ( !giEnabled )
			return;

		var viewState = GetOrCreateViewState( GetStateKey( view ) );
		viewState.Layer.Setup( view, viewport );
		viewState.Layer.AddToView( view, viewport );
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
