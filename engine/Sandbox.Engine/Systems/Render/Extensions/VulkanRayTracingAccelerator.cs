using NativeEngine;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Sandbox.Rendering;

/// <summary>
/// A hardware ray tracing accelerator that communicates directly with the Vulkan API.
/// This bypasses any existing engine ray tracing code to provide a clean, high-performance implementation.
/// </summary>
internal class VulkanRayTracingAccelerator : RenderExtension
{
#if VULKAN_SUPPORTED
	#region Vulkan Interop
	// ... (content)
	#endregion
#endif

	public override void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
		// Disabled due to missing Graphics.VulkanDevice
	}

	public override void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport ) {}
}
