using Sandbox;
using Sandbox.Rendering;
using System;

namespace Sandbox.Prism;

/// <summary>
/// The Prism Framework Orchestrator.
/// Intercepts the render pipeline to inject custom lighting and effects.
/// </summary>
public sealed class PrismSystem : GameObjectSystem<PrismSystem>, Component.IRenderThread
{
	// Global Prism VFS instance
	private static PrismFileSystem _prismVfs;
	private static int _refCount = 0;

	public PrismSystem( Scene scene ) : base( scene )
	{
		// Initialize Prism
		Log.Info( "Prism Framework Initialized for Scene: " + scene.Name );

		// Manage VFS mounting
		if ( _prismVfs == null )
		{
			_prismVfs = new PrismFileSystem();
			FileSystem.Mounted.Mount( _prismVfs );
			Log.Info( "Prism VFS Mounted" );
		}
		_refCount++;
	}

	~PrismSystem()
	{
		_refCount--;
		if ( _refCount <= 0 && _prismVfs != null )
		{
			// Optional: Unmount if no scenes utilize Prism?
			// For stability, we might keep it mounted, or unmount carefully.
			// FileSystem.Mounted.UnMount( _prismVfs );
			// _prismVfs = null;
		}
	}

	/// <summary>
	/// Called whenever a camera is rendering a specific stage. This is called on the render thread.
	/// </summary>
	void Component.IRenderThread.OnRenderStage( CameraComponent camera, Sandbox.Rendering.Stage stage )
	{
		// Basic hook verification
		if ( stage == Sandbox.Rendering.Stage.AfterOpaque )
		{
			// This is where we will inject the custom lighting pass
			// For now, we just ensure the hook is running
		}
	}
}
