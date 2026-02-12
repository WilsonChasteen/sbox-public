namespace Sandbox;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using Sandbox.Rendering;

[StructLayout( LayoutKind.Sequential )]
public struct DazzleSurfel
{
	public Vector3 Position;
	public Vector3 Normal;
	public Vector3 Albedo;
	public Vector3 Radiance;
	public float Radius;
	public uint LastUsedFrame;
	public Vector3 Padding;
}

[StructLayout( LayoutKind.Sequential )]
public struct DazzleReservoir
{
	public Vector3 Radiance;
	public Vector3 Direction;
	public float Weight;
	public uint M;
	public float W_sum;
	public Vector3 Normal;
	public uint Epoch;
	public Vector3 Padding;
}

/// <summary>
/// Real-time GI system implementing "Dazzle" (Radiance Cascades + Persistent Reservoirs).
/// </summary>
sealed class DazzleGISystem : GameObjectSystem<DazzleGISystem>
{
	internal struct DazzleVolumeResources : IDisposable
	{
		public Texture Cascades;
		public GpuBuffer<DazzleReservoir> ReservoirBuffer;
		public Texture SDF;

		public GpuBuffer<DazzleSurfel> SurfelBuffer;
		public GpuBuffer<uint> SurfelCountBuffer;
		public GpuBuffer<GpuBuffer.IndirectDispatchArguments> SurfelDispatchBuffer;
		public Texture SurfelHashGrid;

		public Texture VoxelGrid;
		public Texture JfaPing;
		public Texture JfaPong;

		public void Dispose()
		{
			Cascades?.Dispose();
			ReservoirBuffer?.Dispose();
			SDF?.Dispose();
			SurfelBuffer?.Dispose();
			SurfelCountBuffer?.Dispose();
			SurfelDispatchBuffer?.Dispose();
			SurfelHashGrid?.Dispose();
			VoxelGrid?.Dispose();
			JfaPing?.Dispose();
			JfaPong?.Dispose();
		}
	}

	private Dictionary<Guid, DazzleVolumeResources> _volumeResources = new();

	public DazzleGISystem( Scene scene ) : base( scene )
	{
		Listen( Stage.FinishUpdate, 10, UpdateDazzle, "UpdateDazzleGI" );
	}

	public bool GetResources( Guid volumeId, out DazzleVolumeResources resources )
	{
		return _volumeResources.TryGetValue( volumeId, out resources );
	}

	public override void Dispose()
	{
		foreach ( var resources in _volumeResources.Values )
		{
			resources.Dispose();
		}
		_volumeResources.Clear();

		base.Dispose();
	}

	private void UpdateDazzle()
	{
		if ( Application.IsHeadless )
			return;

		var volumes = Scene.GetAll<IndirectLightVolume>()
			.Where( x => x.Active && x.Mode == IndirectLightVolume.GIMode.Dazzle )
			.ToList();

		// Cleanup removed volumes
		var activeIds = volumes.Select( x => x.Id ).ToHashSet();
		var toRemove = _volumeResources.Keys.Where( id => !activeIds.Contains( id ) ).ToList();
		foreach ( var id in toRemove )
		{
			_volumeResources[id].Dispose();
			_volumeResources.Remove( id );
		}

		foreach ( var volume in volumes )
		{
			UpdateVolume( volume );
		}
	}

	private void UpdateVolume( IndirectLightVolume volume )
	{
		if ( !_volumeResources.TryGetValue( volume.Id, out var resources ) )
		{
			resources = CreateResources( volume );
			_volumeResources[volume.Id] = resources;
		}

		UpdateSDF( volume, resources );
		UpdateSurfels( volume, resources );
		UpdateCascades( volume, resources );
		UpdateReservoirs( volume, resources );
	}

	private static ComputeShader ClearShader = new( "common/Dazzle/dazzle_clear_cs" );

	private void UpdateSDF( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var gridSize = resources.VoxelGrid.Width;
		var gridVec = new Vector3Int( gridSize );

		// 1. Voxelize (Clear first)
		var clearAttrs = RenderAttributes.Pool.Get();
		clearAttrs.Set( "TargetTex", resources.VoxelGrid );
		clearAttrs.Set( "GridSize", gridVec );
		ClearShader.DispatchWithAttributes( clearAttrs, gridSize, gridSize, gridSize );
		RenderAttributes.Pool.Return( clearAttrs );

		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		// TODO: Implement proper voxelization if needed, for now we assume it's done elsewhere or just skip
		// since MaterialOverride and OrthoWidth are missing from SceneCamera.

		// 2. JFA Seed
		var jfaAttrs = RenderAttributes.Pool.Get();
		jfaAttrs.Set( "VoxelGrid", resources.VoxelGrid );
		jfaAttrs.Set( "DestSDF", resources.JfaPing );
		jfaAttrs.Set( "GridSize", gridVec );
		JfaSeedShader.DispatchWithAttributes( jfaAttrs, gridSize, gridSize, gridSize );

		// 3. JFA Steps
		var currentSource = resources.JfaPing;
		var currentDest = resources.JfaPong;

		for ( int step = gridSize / 2; step >= 1; step /= 2 )
		{
			jfaAttrs.Set( "SourceSDF", currentSource );
			jfaAttrs.Set( "DestSDF", currentDest );
			jfaAttrs.Set( "StepSize", step );
			JfaStepShader.DispatchWithAttributes( jfaAttrs, gridSize, gridSize, gridSize );

			// Swap
			var temp = currentSource;
			currentSource = currentDest;
			currentDest = temp;
		}

		// 4. Finalize
		jfaAttrs.Set( "SourceSDF", currentSource );
		jfaAttrs.Set( "DestSDF", resources.SDF );
		jfaAttrs.Set( "VoxelSize", bounds.Size / (float)gridSize );
		JfaFinalizeShader.DispatchWithAttributes( jfaAttrs, gridSize, gridSize, gridSize );
		RenderAttributes.Pool.Return( jfaAttrs );
	}

	private void UpdateSurfels( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var gridSize = resources.SurfelHashGrid.Width;
		var gridVec = new Vector3Int( gridSize );

		// Clear hash grid
		var clearAttrs = RenderAttributes.Pool.Get();
		clearAttrs.Set( "TargetTexU", resources.SurfelHashGrid );
		clearAttrs.Set( "GridSize", gridVec );
		clearAttrs.SetCombo( "D_UINT", 1 );
		ClearShader.DispatchWithAttributes( clearAttrs, gridSize, gridSize, gridSize );
		RenderAttributes.Pool.Return( clearAttrs );

		resources.SurfelCountBuffer.SetCounterValue( 0 );

		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "SurfelBuffer", resources.SurfelBuffer );
		attrs.Set( "SurfelCountBuffer", resources.SurfelCountBuffer );
		attrs.Set( "SurfelHashGrid", resources.SurfelHashGrid );
		attrs.Set( "MaxSurfels", (uint)resources.SurfelBuffer.ElementCount );
		attrs.Set( "SurfelRadius", volume.ReservoirCellSize * volume.SurfelDensity );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "HashGridSize", gridVec );

		// 1. Manage (Spawn)
		SurfelManageShader.DispatchWithAttributes( attrs, (int)Screen.Width, (int)Screen.Height, 1 );

		// 2. Copy count and fixup dispatch
		var countCopy = new GpuBuffer<uint>( 1, GpuBuffer.UsageFlags.ByteAddress );
		resources.SurfelCountBuffer.CopyStructureCount( countCopy );

		attrs.Set( "CountBuffer", countCopy );
		attrs.Set( "DispatchBuffer", resources.SurfelDispatchBuffer );
		SurfelFixupShader.DispatchWithAttributes( attrs, 1, 1, 1 );
		countCopy.Dispose();

		// 3. Lighting
		SurfelLightingShader.DispatchIndirectWithAttributes( attrs, resources.SurfelDispatchBuffer );
		RenderAttributes.Pool.Return( attrs );
	}

	private static ComputeShader JfaSeedShader = new( "common/Dazzle/dazzle_sdf_seed" );
	private static ComputeShader JfaStepShader = new( "common/Dazzle/dazzle_sdf_jfa" );
	private static ComputeShader JfaFinalizeShader = new( "common/Dazzle/dazzle_sdf_finalize" );
	private static Material VoxelizeMaterial = Material.FromShader( "common/Dazzle/dazzle_voxelize" );

	private void UpdateCascades( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "CascadeAtlas", resources.Cascades );
		attrs.Set( "SDF", resources.SDF );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "TotalLevels", volume.CascadeLevels );
		attrs.Set( "BaseDirections", volume.BaseDirections );

		// 1. Trace all levels
		for ( int l = 0; l < volume.CascadeLevels; l++ )
		{
			attrs.Set( "CascadeLevel", l );
			var shift = l;
			Vector3Int probeCounts = new Vector3Int( 16 >> shift, 16 >> shift, 16 >> shift );
			CascadeTraceShader.DispatchWithAttributes( attrs, probeCounts.x, probeCounts.y, probeCounts.z );
		}

		// 2. Merge levels
		for ( int l = volume.CascadeLevels - 2; l >= 0; l-- )
		{
			attrs.Set( "CascadeLevel", l );
			var shift = l;
			Vector3Int probeCounts = new Vector3Int( 16 >> shift, 16 >> shift, 16 >> shift );
			CascadeMergeShader.DispatchWithAttributes( attrs, probeCounts.x, probeCounts.y, probeCounts.z );
		}
		RenderAttributes.Pool.Return( attrs );
	}

	private static ComputeShader SurfelManageShader = new( "common/Dazzle/dazzle_surfel_manage_cs" );
	private static ComputeShader SurfelLightingShader = new( "common/Dazzle/dazzle_surfel_lighting_cs" );
	private static ComputeShader SurfelFixupShader = new( "common/Dazzle/dazzle_surfel_fixup_cs" );

	private static ComputeShader CascadeTraceShader = new( "common/Dazzle/dazzle_cascades_trace_cs" );
	private static ComputeShader CascadeMergeShader = new( "common/Dazzle/dazzle_cascades_merge_cs" );

	private void UpdateReservoirs( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "ReservoirBuffer", resources.ReservoirBuffer );
		attrs.Set( "CascadeAtlas", resources.Cascades );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "ReservoirCellSize", volume.ReservoirCellSize );
		attrs.Set( "MaxReservoirs", (uint)resources.ReservoirBuffer.ElementCount );
		attrs.Set( "CurrentEpoch", (uint)Time.Now ); // Simple epoch

		ReservoirUpdateShader.DispatchWithAttributes( attrs, 16, 16, 16 );
		RenderAttributes.Pool.Return( attrs );
	}

	private static ComputeShader ReservoirUpdateShader = new( "common/Dazzle/dazzle_reservoir_update_cs" );

	private DazzleVolumeResources CreateResources( IndirectLightVolume volume )
	{
		var gridSize = 128;
		var maxSurfels = 65536;
		var maxReservoirs = 16 * 16 * 16;

		return new DazzleVolumeResources
		{
			Cascades = Texture.Create( 1024, 1024 ).WithUAVBinding().WithFormat( ImageFormat.RGBA16161616F ).Finish(),
			ReservoirBuffer = new GpuBuffer<DazzleReservoir>( maxReservoirs ),

			SurfelBuffer = new GpuBuffer<DazzleSurfel>( maxSurfels ),
			SurfelCountBuffer = new GpuBuffer<uint>( 1, GpuBuffer.UsageFlags.Append ),
			SurfelDispatchBuffer = new GpuBuffer<GpuBuffer.IndirectDispatchArguments>( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.ByteAddress ),
			SurfelHashGrid = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R32_UINT ).Finish(),

			VoxelGrid = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R16F ).Finish(),
			JfaPing = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.RGBA32323232F ).Finish(),
			JfaPong = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.RGBA32323232F ).Finish(),
			SDF = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R16F ).Finish(),
		};
	}
}
