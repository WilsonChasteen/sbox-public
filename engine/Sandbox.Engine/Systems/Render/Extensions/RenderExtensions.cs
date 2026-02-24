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
		Register( new VulkanRayTracingAccelerator() );
		Register( new DazzleRenderExtension() );
		Register( new DiscoGIRenderExtension() );
	}

	/// <summary>
	/// Register a new render extension.
	/// </summary>
	public static void Register( IRenderExtension extension )
	{
		lock ( _extensions )
		{
			if ( !_extensions.Contains( extension ) )
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
