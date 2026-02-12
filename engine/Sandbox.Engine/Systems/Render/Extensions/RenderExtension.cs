using NativeEngine;

namespace Sandbox.Rendering;

/// <summary>
/// Base class for render extensions.
/// </summary>
public abstract class RenderExtension : IRenderExtension
{
	/// <summary>
	/// Called when layers are being added to the view.
	/// </summary>
	public virtual void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
	}

	/// <summary>
	/// Called at the end of the render pipeline.
	/// </summary>
	public virtual void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport )
	{
	}
}
