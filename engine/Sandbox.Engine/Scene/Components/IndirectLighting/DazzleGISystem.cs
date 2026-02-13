namespace Sandbox;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Sandbox.Rendering;

[StructLayout( LayoutKind.Sequential, Pack = 16 )]
public struct DazzleSurfel
{
	public Vector3 Position;
	public Vector3 Normal;
	public Vector3 Albedo;
	public Vector3 Radiance;
	public float Radius;
	public uint LastUsedFrame;
	public float Padding1;
	public float Padding2;
	public float Padding3;
	public float Padding4;
	public float Padding5;
	public float Padding6;
}

[StructLayout( LayoutKind.Sequential, Pack = 16 )]
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
	internal class DazzleVolumeResources : IDisposable
	{
		public Texture Cascades;
		public GpuBuffer<DazzleReservoir> ReservoirBuffer;
		public Texture SDF;
		public GpuBuffer<uint> DebugCounters;

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
			DebugCounters?.Dispose();
			SurfelBuffer?.Dispose();
			SurfelCountBuffer?.Dispose();
			SurfelDispatchBuffer?.Dispose();
			SurfelHashGrid?.Dispose();
			VoxelGrid?.Dispose();
			JfaPing?.Dispose();
			JfaPong?.Dispose();
		}
	}

	private enum DebugCounterIndex
	{
		SdfSeedVoxels = 0,
		SdfSeedActive = 1,
		SdfJfaVoxels = 2,
		SdfJfaUpdates = 3,
		SdfFinalizeVoxels = 4,
		SdfFinalizeValid = 5,
		SurfelManagePixels = 6,
		SurfelManageDepthHits = 7,
		SurfelManageSpawned = 8,
		SurfelLightingThreads = 9,
		SurfelLightingNonZero = 10,
		TraceRays = 11,
		TraceHits = 12,
		TraceMisses = 13,
		TraceSteps = 14,
		TraceNonZeroRadiance = 15,
		MergeDirs = 16,
		MergeSamples = 17,
		ReservoirCells = 18,
		ReservoirNonZeroCandidates = 19,
		ReservoirReplacements = 20,
		SurfelCount = 21,
		SurfelManageInVolume = 22,
	}

	private const int DebugCounterCount = 32;
	private static readonly uint[] DebugCounterZeroData = new uint[DebugCounterCount];
	private static readonly uint[] SurfelCountZeroData = new uint[1];

	private Dictionary<Guid, DazzleVolumeResources> _volumeResources = new();
	private Dictionary<Guid, float> _nextTraceLogTime = new();
	private Dictionary<Guid, int> _lastUpdateFrame = new();
	private int _frameCounter = 0;

	private readonly object _lock = new();
	private readonly uint[] _debugCounterBuffer = new uint[DebugCounterCount];

	public DazzleGISystem( Scene scene ) : base( scene )
	{
		Listen( Stage.FinishUpdate, 10, UpdateDazzle, "UpdateDazzleGI" );
	}

	public bool GetResources( Guid volumeId, out DazzleVolumeResources resources )
	{
		lock ( _lock )
		{
			return _volumeResources.TryGetValue( volumeId, out resources );
		}
	}

	public override void Dispose()
	{
		lock ( _lock )
		{
			foreach ( var resources in _volumeResources.Values )
			{
				resources.Dispose();
			}
			_volumeResources.Clear();
			_nextTraceLogTime.Clear();
			_lastUpdateFrame.Clear();
		}

		base.Dispose();
	}

	private void UpdateDazzle()
	{
		if ( Application.IsHeadless )
			return;

		var volumes = Scene.GetAll<IndirectLightVolume>()
			.Where( x => x.Active && x.Mode == IndirectLightVolume.GIMode.Dazzle )
			.ToList();

		var volumeBindingsChanged = false;

		lock ( _lock )
		{
			// Cleanup removed volumes
			var activeIds = volumes.Select( x => x.Id ).ToHashSet();
			var toRemove = _volumeResources.Keys.Where( id => !activeIds.Contains( id ) ).ToList();
			volumeBindingsChanged = toRemove.Count > 0;
			foreach ( var id in toRemove )
			{
				_volumeResources[id].Dispose();
				_volumeResources.Remove( id );
				_nextTraceLogTime.Remove( id );
				_lastUpdateFrame.Remove( id );
			}

			foreach ( var volume in volumes )
			{
				if ( !_volumeResources.TryGetValue( volume.Id, out var resources ) )
				{
					resources = CreateResources( volume );
					_volumeResources[volume.Id] = resources;
					volumeBindingsChanged = true;
				}
			}

			_frameCounter++;
		}

		if ( volumeBindingsChanged )
		{
			Scene.Get<DDGIVolumeSystem>()?.MarkDirty();
		}
	}

	/// <summary>
	/// Dispatches the Dazzle GI pipeline for a specific volume.
	/// Usually called from a render hook to ensure access to the current frame's G-buffer.
	/// </summary>
	public void Dispatch( IndirectLightVolume volume, SceneCamera camera )
	{
		DazzleVolumeResources resources;
		bool needsWorldUpdate;
		int frame;

		lock ( _lock )
		{
			if ( !_volumeResources.TryGetValue( volume.Id, out resources ) )
				return;

			frame = _frameCounter;
			needsWorldUpdate = !_lastUpdateFrame.TryGetValue( volume.Id, out var lastFrame ) || lastFrame != frame;
			_lastUpdateFrame[volume.Id] = frame;
		}

		if ( needsWorldUpdate )
		{
			resources.DebugCounters.SetData( DebugCounterZeroData.AsSpan() );
		}

		UpdateSurfels( volume, resources, camera );

		if ( needsWorldUpdate )
		{
			UpdateSDF( volume, resources );
			UpdateCascades( volume, resources );
			UpdateReservoirs( volume, resources );
			TracePipelineIfEnabled( volume, resources );
		}
	}

	private static ComputeShader ClearShader = new( "common/Dazzle/dazzle_clear_cs" );
	private static ComputeShader VoxelizeComputeShader = new( "common/Dazzle/dazzle_voxelize_cs" );

	private void UpdateSDF( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var gridSize = resources.VoxelGrid.Width;
		var gridVec = new Vector3Int( gridSize );

		// 1. Voxelize (Clear first)
		var clearAttrs = RenderAttributes.Pool.Get();
		clearAttrs.Set( "TargetTex", resources.VoxelGrid );
		clearAttrs.Set( "GridSize", gridVec );
		ClearShader.DispatchWithAttributes( clearAttrs, gridSize, gridSize, gridSize );

		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		// 2. Compute-based voxelization
		clearAttrs.Set( "VoxelGrid", resources.VoxelGrid );
		clearAttrs.Set( "VolumeMin", bounds.Mins );
		clearAttrs.Set( "VolumeMax", bounds.Maxs );
		clearAttrs.Set( "GridSize", gridVec );
		clearAttrs.Set( "DazzleDebugCounters", resources.DebugCounters );
		VoxelizeComputeShader.DispatchWithAttributes( clearAttrs, gridSize, gridSize, gridSize );
		RenderAttributes.Pool.Return( clearAttrs );

		// 3. JFA Seed
		var jfaAttrs = RenderAttributes.Pool.Get();
		jfaAttrs.Set( "VoxelGrid", resources.VoxelGrid );
		jfaAttrs.Set( "SurfelHashGrid", resources.SurfelHashGrid );
		jfaAttrs.Set( "DestSDF", resources.JfaPing );
		jfaAttrs.Set( "DazzleDebugCounters", resources.DebugCounters );
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

	private void UpdateSurfels( IndirectLightVolume volume, DazzleVolumeResources resources, SceneCamera camera )
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

		resources.SurfelCountBuffer.SetData( SurfelCountZeroData.AsSpan() );

		var bounds = volume.Bounds.Transform( volume.WorldTransform );

		var attrs = RenderAttributes.Pool.Get();

		// Merge existing render attributes (contains G-buffer textures like "Color" and "DepthChainDownsample")
		if ( Graphics.Attributes is not null )
		{
			Graphics.Attributes.MergeTo( attrs );
		}

		attrs.Set( "SurfelBuffer", resources.SurfelBuffer );
		attrs.Set( "SurfelCountBuffer", resources.SurfelCountBuffer );
		attrs.Set( "SurfelHashGrid", resources.SurfelHashGrid );
		attrs.Set( "DazzleDebugCounters", resources.DebugCounters );
		attrs.Set( "MaxSurfels", (uint)resources.SurfelBuffer.ElementCount );
		attrs.Set( "SurfelRadius", volume.ReservoirCellSize * volume.SurfelDensity );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "HashGridSize", gridVec );

		var width = (int)camera.Size.x;
		var height = (int)camera.Size.y;
		attrs.Set( "ScreenSize", new Vector2Int( width, height ) );

		if ( width < 1 || height < 1 )
		{
			RenderAttributes.Pool.Return( attrs );
			return;
		}

		// 1. Manage (Spawn)
		var dispatchX = (width + 7) / 8;
		var dispatchY = (height + 7) / 8;
		SurfelManageShader.DispatchWithAttributes( attrs, dispatchX, dispatchY, 1 );

		// 2. Fixup dispatch dimensions from the current surfel count
		attrs.Set( "CountBuffer", resources.SurfelCountBuffer );
		attrs.Set( "DispatchBuffer", resources.SurfelDispatchBuffer );
		SurfelFixupShader.DispatchWithAttributes( attrs, 1, 1, 1 );

		// 3. Lighting
		SurfelLightingShader.DispatchIndirectWithAttributes( attrs, resources.SurfelDispatchBuffer );
		RenderAttributes.Pool.Return( attrs );
	}

	private static ComputeShader JfaSeedShader = new( "common/Dazzle/dazzle_sdf_seed" );
	private static ComputeShader JfaStepShader = new( "common/Dazzle/dazzle_sdf_jfa" );
	private static ComputeShader JfaFinalizeShader = new( "common/Dazzle/dazzle_sdf_finalize" );

	private void UpdateCascades( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		var bounds = volume.Bounds.Transform( volume.WorldTransform );
		var totalLevels = Math.Clamp( volume.CascadeLevels, 1, 8 );

		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "CascadeAtlas", resources.Cascades );
		attrs.Set( "SDF", resources.SDF );
		attrs.Set( "SurfelBuffer", resources.SurfelBuffer );
		attrs.Set( "SurfelHashGrid", resources.SurfelHashGrid );
		attrs.Set( "DazzleDebugCounters", resources.DebugCounters );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "HashGridSize", new Vector3Int( resources.SurfelHashGrid.Width, resources.SurfelHashGrid.Height, resources.SurfelHashGrid.Depth ) );
		attrs.Set( "MaxSurfels", (uint)resources.SurfelBuffer.ElementCount );
		attrs.Set( "TotalLevels", totalLevels );
		attrs.Set( "BaseDirections", volume.BaseDirections );
		attrs.Set( "UseRT", volume.UseHardwareRT );

		// 1. Trace all levels (atlas writes are level-packed in shader).
		for ( int l = 0; l < totalLevels; l++ )
		{
			attrs.Set( "CascadeLevel", l );
			var probeDim = Math.Max( 1, 16 >> l );
			CascadeTraceShader.DispatchWithAttributes( attrs, probeDim, probeDim, probeDim );
		}

		// 2. Merge from coarsest traced level down to level 0.
		for ( int l = totalLevels - 2; l >= 0; l-- )
		{
			attrs.Set( "CascadeLevel", l );
			var probeDim = Math.Max( 1, 16 >> l );
			CascadeMergeShader.DispatchWithAttributes( attrs, probeDim, probeDim, probeDim );
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
		attrs.Set( "DazzleDebugCounters", resources.DebugCounters );
		attrs.Set( "VolumeMin", bounds.Mins );
		attrs.Set( "VolumeMax", bounds.Maxs );
		attrs.Set( "ReservoirCellSize", volume.ReservoirCellSize );
		attrs.Set( "MaxReservoirs", (uint)resources.ReservoirBuffer.ElementCount );
		attrs.Set( "CurrentEpoch", (uint)Time.Now ); // Simple epoch
		attrs.Set( "BaseDirections", Math.Max( volume.BaseDirections, 1 ) );

		ReservoirUpdateShader.DispatchWithAttributes( attrs, 16, 16, 16 );
		RenderAttributes.Pool.Return( attrs );
	}

	private static ComputeShader ReservoirUpdateShader = new( "common/Dazzle/dazzle_reservoir_update_cs" );

	private void TracePipelineIfEnabled( IndirectLightVolume volume, DazzleVolumeResources resources )
	{
		if ( !volume.EnablePipelineTrace ) return;

		var now = (float)Time.Now;
		var interval = MathF.Max( 0.1f, volume.PipelineTraceInterval );

		lock ( _lock )
		{
			if ( _nextTraceLogTime.TryGetValue( volume.Id, out var nextLogAt ) && now < nextLogAt )
				return;

			_nextTraceLogTime[volume.Id] = now + interval;
			resources.DebugCounters.GetData( _debugCounterBuffer.AsSpan() );
		}

		LogPipelineTrace( volume, _debugCounterBuffer );
	}

	private void LogPipelineTrace( IndirectLightVolume volume, uint[] counters )
	{
		var vA = Counter( counters, DebugCounterIndex.SdfSeedActive );
		var vT = Counter( counters, DebugCounterIndex.SdfSeedVoxels );
		var fV = Counter( counters, DebugCounterIndex.SdfFinalizeValid );
		var fT = Counter( counters, DebugCounterIndex.SdfFinalizeVoxels );
		var jU = Counter( counters, DebugCounterIndex.SdfJfaUpdates );

		var sH = Counter( counters, DebugCounterIndex.SurfelManageDepthHits );
		var sP = Counter( counters, DebugCounterIndex.SurfelManagePixels );
		var sV = Counter( counters, DebugCounterIndex.SurfelManageInVolume );
		var sS = Counter( counters, DebugCounterIndex.SurfelManageSpawned );
		var sC = Counter( counters, DebugCounterIndex.SurfelCount );
		var sL = Counter( counters, DebugCounterIndex.SurfelLightingNonZero );
		var sT = Counter( counters, DebugCounterIndex.SurfelLightingThreads );

		var tR = Counter( counters, DebugCounterIndex.TraceRays );
		var tH = Counter( counters, DebugCounterIndex.TraceHits );
		var tM = Counter( counters, DebugCounterIndex.TraceMisses );
		var tS = Counter( counters, DebugCounterIndex.TraceSteps );
		var tN = Counter( counters, DebugCounterIndex.TraceNonZeroRadiance );

		var mS = Counter( counters, DebugCounterIndex.MergeSamples );
		var mD = Counter( counters, DebugCounterIndex.MergeDirs );
		var rC = Counter( counters, DebugCounterIndex.ReservoirCells );
		var rN = Counter( counters, DebugCounterIndex.ReservoirNonZeroCandidates );
		var rR = Counter( counters, DebugCounterIndex.ReservoirReplacements );

		var volumeName = volume.GameObject?.Name ?? volume.Id.ToString();
		Log.Info(
			$"Dazzle Trace [{volumeName}] " +
			$"SDF active={vA}/{vT} ({RatioPercent( vA, vT ):0.0}%) " +
			$"finalValid={fV}/{fT} ({RatioPercent( fV, fT ):0.0}%) " +
			$"jfaUpdates={jU}; " +
			$"Surfels depthHits={sH}/{sP} inVolume={sV} spawned={sS} live={sC} lit={sL}/{sT}; " +
			$"Trace rays={tR} hits={tH} misses={tM} nonZero={tN} stepsPerRay={Ratio( tS, tR ):0.00}; " +
			$"Merge samples={mS}/{mD}; " +
			$"Reservoir cells={rC} nonZeroCandidates={rN} replacements={rR}."
		);

		var hints = new List<string>();
		if ( vA == 0 ) hints.Add( "voxelization produced no occupied cells" );
		if ( sC == 0 ) hints.Add( "no surfels alive after manage/fixup" );
		if ( tR > 0 && tH == 0 ) hints.Add( "cascade rays miss all occupancy" );
		if ( tH > 0 && tN == 0 ) hints.Add( "ray hits found but radiance stayed black" );
		if ( rC > 0 && rN == 0 ) hints.Add( "reservoir candidates are all zero energy" );

		if ( hints.Count > 0 )
		{
			Log.Warning( $"Dazzle Trace [{volumeName}] Likely bottlenecks: {string.Join( "; ", hints )}." );
		}
	}

	private static uint Counter( uint[] counters, DebugCounterIndex index )
	{
		var i = (int)index;
		return i >= 0 && i < counters.Length ? counters[i] : 0u;
	}

	private static float Ratio( uint numerator, uint denominator )
	{
		return denominator > 0u ? numerator / (float)denominator : 0.0f;
	}

	private static float RatioPercent( uint numerator, uint denominator )
	{
		return 100.0f * Ratio( numerator, denominator );
	}

	private DazzleVolumeResources CreateResources( IndirectLightVolume volume )
	{
		var gridSize = 128;
		var maxSurfels = 65536;
		var maxReservoirs = 16 * 16 * 16;

		return new DazzleVolumeResources
		{
			Cascades = Texture.Create( 1024, 1024 ).WithUAVBinding().WithFormat( ImageFormat.RGBA16161616F ).Finish(),
			ReservoirBuffer = new GpuBuffer<DazzleReservoir>( maxReservoirs ),
			DebugCounters = new GpuBuffer<uint>( DebugCounterCount ),

			SurfelBuffer = new GpuBuffer<DazzleSurfel>( maxSurfels ),
			SurfelCountBuffer = new GpuBuffer<uint>( 1 ),
			SurfelDispatchBuffer = new GpuBuffer<GpuBuffer.IndirectDispatchArguments>( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.ByteAddress ),
			SurfelHashGrid = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R32_UINT ).Finish(),

			VoxelGrid = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R16F ).Finish(),
			JfaPing = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.RGBA32323232F ).Finish(),
			JfaPong = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.RGBA32323232F ).Finish(),
			SDF = Texture.CreateVolume( gridSize, gridSize, gridSize ).WithUAVBinding().WithFormat( ImageFormat.R16F ).Finish(),
		};
	}
}
