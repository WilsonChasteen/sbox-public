namespace Sandbox;

using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Maintains GPU data for all <see cref="IndirectLightVolume"/> instances in a scene using RTXGI.
/// Collects, sorts, and uploads volume parameters to the renderer.
/// </summary>
sealed class DDGIVolumeSystem : GameObjectSystem<DDGIVolumeSystem>
{
	private GpuBuffer<RTXGIVolumeUpdater.DDGIVolumeDescGPUPacked> GpuBuffer;
	private bool _dirty = true;

	public DDGIVolumeSystem( Scene scene ) : base( scene )
	{
		Listen( Stage.FinishUpdate, 0, UpdateVolumes, "UpdateDDGIVolumes" );
	}

	public override void Dispose()
	{
		ReleaseBuffer();

		Scene?.RenderAttributes?.Set( "DDGI_VolumeCount", 0 );
		base.Dispose();
	}

	internal void MarkDirty()
	{
		_dirty = true;
	}

	private void UpdateVolumes()
	{
		if ( Application.IsHeadless || !_dirty )
			return;

		if ( Scene?.RenderAttributes is null )
			return;

		_dirty = false;

		var orderedVolumes = Scene
			.GetAll<IndirectLightVolume>()
			.Where( volume => volume is { Active: true } )
			.OrderBy( volume => volume.Bounds.Volume );

		var volumeData = new List<RTXGIVolumeUpdater.DDGIVolumeDescGPUPacked>();
		foreach ( var volume in orderedVolumes )
		{
			if ( volume.Enabled && volume.BuildData( out var data ) )
			{
				volumeData.Add( data );
			}
		}

		if ( volumeData.Count > 0 )
		{
			EnsureBufferCapacity( volumeData.Count );
			GpuBuffer.SetData( volumeData );
			Scene.RenderAttributes.Set( "DDGI_VolumeCount", volumeData.Count );
			Scene.RenderAttributes.Set( "DDGI_Volumes", GpuBuffer );
			return;
		}

		ReleaseBuffer();
		Scene.RenderAttributes.Set( "DDGI_VolumeCount", 0 );
	}

	private void EnsureBufferCapacity( int count )
	{
		if ( GpuBuffer is not null && GpuBuffer.ElementCount >= count )
			return;

		ReleaseBuffer();
		GpuBuffer = new GpuBuffer<RTXGIVolumeUpdater.DDGIVolumeDescGPUPacked>( Math.Max( count, 1 ), debugName: "DDGI_Volumes" );
	}

	private void ReleaseBuffer()
	{
		GpuBuffer?.Dispose();
		GpuBuffer = null;
	}
}
