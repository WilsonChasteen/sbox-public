using NativeEngine;
using System.Collections.Generic;
using System.Linq;

namespace Sandbox.Rendering;

/// <summary>
/// Manager for render extensions.
/// </summary>
internal static class RenderExtensions
{
	private static List<IRenderExtension> _extensions = new();

	static RenderExtensions()
	{
		// Auto-register the hardware ray tracing accelerator if we're on Vulkan
		if ( g_pRenderDevice.GetRenderDeviceAPI() == RenderDeviceAPI_t.RENDER_DEVICE_API_VULKAN )
		{
			Register( new VulkanRayTracingAccelerator() );
		}
	}

	/// <summary>
	/// Register a new render extension.
	/// </summary>
	public static void Register( IRenderExtension extension )
	{
		lock ( _extensions )
		{
			// Avoid double registration of the same type (common during hotload)
			if ( !_extensions.Any( x => x.GetType() == extension.GetType() ) )
			{
				_extensions.Add( extension );
			}
		}
	}

	/// <summary>
	/// Unregister a render extension.
	/// </summary>
	public static void Unregister( IRenderExtension extension )
	{
		lock ( _extensions )
		{
			_extensions.Remove( extension );
		}
	}

	/// <summary>
	/// Called by the RenderPipeline to add extension layers to the view.
	/// </summary>
	internal static void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		IRenderExtension[] extensions;
		lock ( _extensions )
		{
			if ( _extensions.Count == 0 ) return;
			extensions = _extensions.ToArray();
		}

		foreach ( var extension in extensions )
		{
			extension.AddLayersToView( pipeline, view, viewport );
		}
	}

	/// <summary>
	/// Called by the RenderPipeline at the end of the pipeline.
	/// </summary>
	internal static void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		IRenderExtension[] extensions;
		lock ( _extensions )
		{
			if ( _extensions.Count == 0 ) return;
			extensions = _extensions.ToArray();
		}

		foreach ( var extension in extensions )
		{
			extension.PipelineEnd( pipeline, view, viewport );
		}
	}
}
