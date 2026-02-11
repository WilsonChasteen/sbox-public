namespace Sandbox;

using Editor;
using Facepunch.ActionGraphs;
using Sandbox.Rendering;
using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// Provides indirect lighting using RTXGI-DDGI.
/// Probes store irradiance and distance data in volume textures that can be sampled by shaders.
/// </summary>
[Expose]
[Title( "Indirect Light Volume" )]
[Category( "Rendering" )]
[Icon( "grid_view" )]
[EditorHandle( "materials/gizmo/lpv.png" )]
[Alias( "DDGIVolume" )]
public sealed partial class IndirectLightVolume : Component, Component.ExecuteInEditor, Component.DontExecuteOnServer, Component.IRenderThread
{
	/// <summary>
	/// The Global Illumination method to use for this volume.
	/// </summary>
	public enum GIMethod
	{
		/// <summary>
		/// Dynamic Diffuse Global Illumination. High quality, stable, but expensive to bake.
		/// </summary>
		[Icon( "grid_view" )]
		DDGI,

		/// <summary>
		/// Lux Global Illumination. High performance, real-time dynamic.
		/// </summary>
		[Icon( "bolt" )]
		Lux
	}

	/// <summary>
	/// CPU-side probe data indexed by flattened probe index.
	/// </summary>
	public sealed class Probe
	{
		public Vector3 Offset { get; set; }
		public bool Active { get; set; } = true;
	}

	/// <summary>
	/// CPU-side probe data indexed by flattened probe index.
	/// </summary>
	internal Probe[] Probes { get; set; }

	//
	// Properties
	//

	/// <summary>
	/// The Global Illumination method to use. Both now use RTXGI-DDGI backend.
	/// </summary>
	[Property, MakeDirty]
	public GIMethod Method { get; set; } = GIMethod.DDGI;

	/// <summary>
	/// If enabled, the volume will update in real-time using RTXGI.
	/// </summary>
	[Property, MakeDirty]
	public bool Realtime { get; set; } = false;

	/// <summary>
	/// World-space bounding box that defines the volume coverage area.
	/// </summary>
	[Property, MakeDirty]
	public BBox Bounds { get; set; } = BBox.FromPositionAndSize( Vector3.Zero, new Vector3( 512.0f ) );

	/// <summary>
	/// Number of probes per 1024 world units. Higher values increase probe resolution.
	/// </summary>
	[Property, Range( 1, 15 ), MakeDirty]
	public int ProbeDensity { get; set; } = 8;

	/// <summary>
	/// Bias applied along surface normals to prevent self-occlusion artifacts.
	/// </summary>
	[Group( "Advanced Settings" )]
	[Property, Range( -0.0f, 50.0f ), MakeDirty]
	public float NormalBias { get; set; } = 5.0f;

	/// <summary>
	/// Controls how much less energy to conserve during probe integration.
	/// Higher values give a harsher, more contrasty look.
	/// </summary>
	[Property, Range( 1.0f, 2.0f ), MakeDirty]
	[Group( "Advanced Settings" )]
	public float Contrast { get; set; } = 1.0f;

	/// <summary>
	/// Calculated probe count along each axis based on bounds and density.
	/// </summary>
	public Vector3Int ProbeCounts => ComputeProbeCounts();

	/// <summary>
	/// Volume texture storing probe irradiance data (color).
	/// </summary>
	[Property, Hide]
	public Texture IrradianceTexture { get; set; }

	/// <summary>
	/// Volume texture storing probe distance/visibility data.
	/// </summary>
	[Property, Hide]
	public Texture DistanceTexture { get; set; }

	/// <summary>
	/// Volume texture storing probe data (offsets + classification).
	/// </summary>
	[Property, Hide]
	public Texture RelocationTexture { get; set; }

	private RTXGIVolumeUpdater _rtxgiUpdater;

	/// <summary>
	/// Cancellation source for the current bake operation.
	/// </summary>
	private CancellationTokenSource _bakeCts;

	//
	// Component Lifecycle
	//

	protected override void OnEnabled()
	{
		base.OnEnabled();
		Transform.OnTransformChanged += OnDirty;

		_rtxgiUpdater = new RTXGIVolumeUpdater( this );

		// Restore textures from properties if they were loaded from disk
		if ( IrradianceTexture.IsValid() ) _rtxgiUpdater.SetIrradianceTexture( IrradianceTexture );
		if ( DistanceTexture.IsValid() ) _rtxgiUpdater.SetDistanceTexture( DistanceTexture );
		if ( RelocationTexture.IsValid() ) _rtxgiUpdater.SetProbeDataTexture( RelocationTexture );

		OnDirty();
	}

	protected override void OnDisabled()
	{
		base.OnDisabled();
		Transform.OnTransformChanged -= OnDirty;

		_bakeCts?.Cancel();
		_bakeCts?.Dispose();
		_bakeCts = null;

		_rtxgiUpdater?.Dispose();
		_rtxgiUpdater = null;

		Scene.Get<DDGIVolumeSystem>()?.MarkDirty();
	}

	void Component.IRenderThread.OnRenderStage( CameraComponent camera, Stage stage )
	{
		if ( stage != Stage.AfterOpaque )
			return;

		if ( _rtxgiUpdater is null )
			_rtxgiUpdater = new RTXGIVolumeUpdater( this );

		_rtxgiUpdater.Update();
	}

	protected override void OnDirty()
	{
		base.OnDirty();
		Scene.Get<DDGIVolumeSystem>()?.MarkDirty();
	}

	//
	// Editor Actions
	//

	/// <summary>
	/// Starts the probe baking process to capture lighting into the volume textures using RTXGI.
	/// </summary>
	[Button( "Bake", "lightbulb" )]
	public async Task BakeProbes( CancellationToken ct = default )
	{
		if ( Scene?.SceneWorld is null )
			return;

		_bakeCts?.Cancel();
		_bakeCts?.Dispose();
		_bakeCts = new CancellationTokenSource();

		if ( _rtxgiUpdater is null )
			_rtxgiUpdater = new RTXGIVolumeUpdater( this );

		using var linkedCt = CancellationTokenSource.CreateLinkedTokenSource( ct, _bakeCts.Token, GameObject.EnabledToken );

		await _rtxgiUpdater.Bake( linkedCt.Token );

		// Save textures to disk for persistence
		if ( Application.IsEditor )
		{
			Graphics.FlushGPU();
			IrradianceTexture = SaveTexture( _rtxgiUpdater.IrradianceTexture, "Irradiance" );
			DistanceTexture = SaveTexture( _rtxgiUpdater.DistanceTexture, "Distance", ImageFormat.RGBA32323232F );
			RelocationTexture = SaveTexture( _rtxgiUpdater.ProbeDataTexture, "Relocation", ImageFormat.RGBA32323232F );
		}

		Scene.Get<DDGIVolumeSystem>()?.MarkDirty();
	}

	private Texture SaveTexture( Texture source, string suffix, ImageFormat? format = null )
	{
		if ( source is null || source.IsError ) return source;
		if ( Scene.Editor is null ) return source;

		var sceneFolder = Scene.Editor.GetSceneFolder();
		var safeName = (GameObject?.Name ?? "RTXGIVolume").Replace( " ", "_" ).ToLower();
		var filename = $"/ddgi/{safeName}_{suffix}_{Id}.vtex_c";

		var vtexBytes = source.SaveToVtex( format );
		var path = sceneFolder.WriteFile( filename, vtexBytes );

		var saved = Texture.Load( path );
		if ( saved is not null && !saved.IsError )
		{
			return saved;
		}
		return source;
	}

	[Button( "Fit to Scene Bounds", "fullscreen" )]
	public void ExtendToSceneBounds()
	{
		if ( Scene is null ) return;
		WorldScale = 1;
		WorldRotation = Rotation.Identity;
		var sceneBounds = BBox.FromPositionAndSize( WorldPosition );

		foreach ( var renderer in Scene.GetAll<Renderer>() )
		{
			if ( renderer is not IHasBounds bounds ) continue;
			sceneBounds = sceneBounds.AddBBox( bounds.LocalBounds.Transform( renderer.WorldTransform ) );
		}
		sceneBounds = sceneBounds.Translate( -WorldPosition ).Grow( 16 );
		Bounds = sceneBounds;
	}

	protected override void DrawGizmos()
	{
		if ( !Gizmo.IsSelected ) return;
		var bounds = Bounds;
		Gizmo.Control.BoundingBox( "Bounds", bounds, out bounds );
		Gizmo.Draw.LineBBox( bounds );
		Bounds = bounds;

		var debugGrid = Gizmo.Active.FindOrCreate<LPVDebugGridObject>( "lpv-grid", () => new( Gizmo.World ) );
		debugGrid.UpdateGrid( WorldTransform, Bounds, ProbeCounts, 10, Probes );
	}

	internal bool BuildData( out RTXGIVolumeUpdater.DDGIVolumeDescGPUPacked data )
	{
		data = default;
		var irr = IrradianceTexture ?? _rtxgiUpdater?.IrradianceTexture;
		if ( irr is null || !irr.IsValid() ) return false;

		var gpuDesc = new RTXGIVolumeUpdater.DDGIVolumeDescGPU();
		gpuDesc.origin = WorldPosition;
		gpuDesc.probeMaxRayDistance = 10000.0f;
		gpuDesc.rotation = WorldRotation;
		gpuDesc.probeSpacing = ComputeSpacing( ProbeCounts );
		gpuDesc.probeCounts = ProbeCounts;
		gpuDesc.probeNumRays = 256;
		gpuDesc.probeNumIrradianceTexels = 8;
		gpuDesc.probeNumDistanceTexels = 16;
		gpuDesc.probeHysteresis = 0.97f;
		gpuDesc.probeNormalBias = NormalBias;
		gpuDesc.probeViewBias = 0.1f;
		gpuDesc.probeIrradianceEncodingGamma = 5.0f;
		gpuDesc.probeIrradianceThreshold = 0.25f;
		gpuDesc.probeBrightnessThreshold = 2.0f;
		gpuDesc.probeRandomRayBackfaceThreshold = 0.1f;
		gpuDesc.probeDistanceExponent = 7.0f;
		gpuDesc.probeRelocationEnabled = true;
		gpuDesc.probeClassificationEnabled = true;
		gpuDesc.probeMinFrontfaceDistance = 1.0f;
		gpuDesc.probeBackfaceThreshold = 0.1f;

		data.Pack( gpuDesc );

		var dist = DistanceTexture ?? _rtxgiUpdater?.DistanceTexture;
		var dataTex = RelocationTexture ?? _rtxgiUpdater?.ProbeDataTexture;

		data.data12 = new Vector4( irr.Index, dist?.Index ?? -1, dataTex?.Index ?? -1, (int)Method );

		return true;
	}

	private Vector3Int ComputeProbeCounts()
	{
		const float densityScale = 1.0f / 1024.0f;
		const int minProbes = 4;
		const int maxProbes = 40;
		var size = Bounds.Size;
		var density = ProbeDensity * densityScale;
		return new Vector3Int(
			Math.Clamp( (int)MathF.Ceiling( size.x * density ) + 1, minProbes, maxProbes ),
			Math.Clamp( (int)MathF.Ceiling( size.y * density ) + 1, minProbes, maxProbes ),
			Math.Clamp( (int)MathF.Ceiling( size.z * density ) + 1, minProbes, maxProbes )
		);
	}

	internal Vector3 ComputeSpacing( Vector3Int counts )
	{
		var size = Bounds.Size;
		return new Vector3(
			counts.x > 1 ? size.x / (counts.x - 1) : 0.0f,
			counts.y > 1 ? size.y / (counts.y - 1) : 0.0f,
			counts.z > 1 ? size.z / (counts.z - 1) : 0.0f
		);
	}

	internal Vector3 GetProbeLocalPosition( Vector3Int index )
	{
		var spacing = ComputeSpacing( ProbeCounts );
		return Bounds.Mins + index * spacing;
	}

	internal Vector3 GetProbeWorldPosition( Vector3Int index )
	{
		return WorldTransform.PointToWorld( GetProbeLocalPosition( index ) );
	}

	internal Vector3 GetRelocatedProbeWorldPosition( Vector3Int index )
	{
		return GetProbeWorldPosition( index );
	}

	[Menu( "Editor", "Scene/Bake Indirect Light Volumes", "snowing", Priority = 1100 )]
	public static async Task BakeAll()
	{
		if ( Application.Editor is null ) return;
		var components = Application.Editor.Scene.GetAll<IndirectLightVolume>().ToArray();
		await Application.Editor.ForEachAsync( components, "Baking Indirect Light Volumes in Scene", ( x, ct ) => x.BakeProbes( ct ) );
	}
}
