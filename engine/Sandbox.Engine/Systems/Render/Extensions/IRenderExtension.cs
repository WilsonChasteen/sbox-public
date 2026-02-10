using NativeEngine;

namespace Sandbox.Rendering;

/// <summary>
/// A render extension that can inject layers into the render pipeline.
/// </summary>
internal interface IRenderExtension
{
	/// <summary>
	/// Called when layers are being added to the view.
	/// </summary>
	void AddLayersToView( RenderPipeline pipeline, ISceneView view, RenderViewport viewport );

	/// <summary>
	/// Called at the end of the render pipeline.
	/// </summary>
	void PipelineEnd( RenderPipeline pipeline, ISceneView view, RenderViewport viewport );
}
