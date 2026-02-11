using Sandbox.Rendering;
using System.Threading;
using System.Runtime.InteropServices;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Sandbox;

/// <summary>
/// RTXGI-DDGI volume updater.
/// Replaces the old DDGI and Lux GI backends.
/// </summary>
internal class RTXGIVolumeUpdater : IDisposable
{
	private readonly IndirectLightVolume _volume;

	// Shaders
	private static ComputeShader BlendIrradianceShader = new ComputeShader( "common/rtxgi/rtxgi_blend_irradiance" );
	private static ComputeShader BlendDistanceShader = new ComputeShader( "common/rtxgi/rtxgi_blend_distance" );
	private static ComputeShader RelocateShader = new ComputeShader( "common/rtxgi/rtxgi_relocate" );
	private static ComputeShader ClassifyShader = new ComputeShader( "common/rtxgi/rtxgi_classify" );
	private static ComputeShader FillRayDataShader = new ComputeShader( "common/rtxgi/rtxgi_fill_raydata" );
	private static ComputeShader DepthCopyShader = new ComputeShader( "common/rtxgi/rtxgi_depth_copy" );
	private static RayTracingShader ProbeTraceShader = new RayTracingShader( "common/rtxgi/rtxgi_probe_trace" );

	// Textures
	public Texture RayDataTexture { get; private set; }
	public Texture IrradianceTexture { get; private set; }
	public Texture DistanceTexture { get; private set; }
	public Texture ProbeDataTexture { get; private set; }
	public Texture VariabilityTexture { get; private set; }
	public Texture VariabilityAverageTexture { get; private set; }

	// Fallback resources
	private SceneCamera _captureCamera;
	private Texture _captureTexture;
	private Texture _captureDepth;
	private bool _isUsingFallback = false;
	private int _renderedFace = 0;
	private int _renderedIndex = -1;

	// Constant Buffers
	private GpuBuffer<DDGIVolumeDescGPUPacked> _descBuffer;

	private int _nextProbeToUpdate = 0;

	public RTXGIVolumeUpdater( IndirectLightVolume volume )
	{
		_volume = volume;
		EnsureResources();

		var accelerator = RenderExtensions.Get<VulkanRayTracingAccelerator>();
		if ( accelerator != null && accelerator.TopLevelAS != 0 )
		{
			_isUsingFallback = false;
			Log.Info( "RTXGI: Using hardware ray tracing for RayData." );
		}
		else
		{
			_isUsingFallback = true;
			Log.Info( "RTXGI: Using cubemap capture fallback for RayData." );
			InitializeFallback();
		}
	}

	public void SetIrradianceTexture( Texture tex ) => IrradianceTexture = tex;
	public void SetDistanceTexture( Texture tex ) => DistanceTexture = tex;
	public void SetProbeDataTexture( Texture tex ) => ProbeDataTexture = tex;

	private void EnsureResources()
	{
		var counts = _volume.ProbeCounts;
		int numRays = 256;

		int probesPerPlane = counts.x * counts.y;
		int numPlanes = counts.z;

		if ( RayDataTexture is null || RayDataTexture.Width != numRays || RayDataTexture.Height != probesPerPlane || RayDataTexture.Depth != numPlanes )
		{
			RayDataTexture?.Dispose();
			RayDataTexture = Texture.CreateVolume( numRays, probesPerPlane, numPlanes, ImageFormat.RGBA32323232F )
				.WithName( "RTXGI_RayData" )
				.WithUAVBinding()
				.Finish();
		}

		var irradianceSize = new Vector3Int( counts.x * 8, counts.y * 8, counts.z );
		if ( IrradianceTexture is null || IrradianceTexture.Size != irradianceSize )
		{
			IrradianceTexture?.Dispose();
			IrradianceTexture = Texture.CreateVolume( irradianceSize.x, irradianceSize.y, irradianceSize.z, ImageFormat.RGBA16161616F )
				.WithName( "RTXGI_Irradiance" )
				.WithUAVBinding()
				.Finish();
		}

		var distanceSize = new Vector3Int( counts.x * 16, counts.y * 16, counts.z );
		if ( DistanceTexture is null || DistanceTexture.Size != distanceSize )
		{
			DistanceTexture?.Dispose();
			DistanceTexture = Texture.CreateVolume( distanceSize.x, distanceSize.y, distanceSize.z, ImageFormat.RGBA32323232F )
				.WithName( "RTXGI_Distance" )
				.WithUAVBinding()
				.Finish();
		}

		if ( ProbeDataTexture is null || ProbeDataTexture.Size != counts )
		{
			ProbeDataTexture?.Dispose();
			ProbeDataTexture = Texture.CreateVolume( counts.x, counts.y, counts.z, ImageFormat.RGBA32323232F )
				.WithName( "RTXGI_ProbeData" )
				.WithUAVBinding()
				.Finish();
		}

		if ( _descBuffer is null )
		{
			_descBuffer = new GpuBuffer<DDGIVolumeDescGPUPacked>( 1, GpuBufferUsage.Constant, "RTXGI_DescBuffer" );
		}
	}

	private void InitializeFallback()
	{
		_captureCamera = new SceneCamera
		{
			World = _volume.Scene.SceneWorld,
			Rotation = Rotation.Identity,
			ClearFlags = ClearFlags.All,
			BackgroundColor = Color.Black,
			AmbientLightColor = Color.Black,
		};

		_captureCamera.OnRenderStageHook += ( stage, camera ) =>
		{
			if ( stage != Stage.AfterTransparent )
				return;

			var depth = Texture.FromNative( Graphics.SceneLayer.GetDepthTarget() );
			CopyDepthToColor( depth, _captureDepth, _renderedFace );
			depth.Dispose();

			_renderedFace++;
			if ( _renderedFace == 6 )
			{
				FinishProbeCapture( _renderedIndex );
			}
		};

		const int cubemapSize = 64;
		_captureTexture = Texture.CreateCube( cubemapSize, cubemapSize )
								.WithUAVBinding()
								.WithFormat( ImageFormat.RGBA16161616F )
								.Finish();

		_captureDepth = Texture.CreateCube( cubemapSize, cubemapSize )
								.WithUAVBinding()
								.WithFormat( ImageFormat.R32F )
								.Finish();
	}

	private void CopyDepthToColor( Texture srcDepth, Texture dstColor, int dstArraySlice )
	{
		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "SourceDepth", srcDepth );
		attrs.Set( "DestTextureArray", dstColor );
		attrs.Set( "TextureSize", new Vector2Int( srcDepth.Width, srcDepth.Height ) );
		attrs.Set( "DestArraySlice", dstArraySlice );

		DepthCopyShader.DispatchWithAttributes( attrs, (srcDepth.Width + 7) / 8, (srcDepth.Height + 7) / 8, 1 );
		RenderAttributes.Pool.Return( attrs );
	}

	public void Update()
	{
		if ( !Graphics.IsActive ) return;

		UpdateConstants();

		if ( _volume.Realtime )
		{
			if ( _isUsingFallback )
			{
				for ( int i = 0; i < 2; i++ )
				{
					UpdateProbeFallback( _nextProbeToUpdate );
					_nextProbeToUpdate = ( _nextProbeToUpdate + 1 ) % ( _volume.ProbeCounts.x * _volume.ProbeCounts.y * _volume.ProbeCounts.z );
				}
			}
			else
			{
				UpdateProbeHardwareRT();
			}
		}

		DispatchBlending();

		if ( _volume.Realtime )
		{
			DispatchRelocation();
			DispatchClassification();
		}
	}

	private void UpdateProbeHardwareRT()
	{
		var accelerator = RenderExtensions.Get<VulkanRayTracingAccelerator>();
		if ( accelerator == null || accelerator.TopLevelAS == 0 ) return;

		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "DDGIVolumes", _descBuffer );
		attrs.Set( "RayData", RayDataTexture );
		attrs.Set( "ProbeData", ProbeDataTexture );
		attrs.Set( "IrradianceTexture", IrradianceTexture );
		attrs.Set( "DistanceTexture", DistanceTexture );

		// Wrap the TLAS handle
		var tlas = new RayTracingAccelerationStructure( accelerator.TopLevelAS );
		attrs.Set( "SceneTLAS", tlas );

		var counts = _volume.ProbeCounts;
		ProbeTraceShader.DispatchRaysWithAttributes( attrs, 256, counts.x * counts.y, counts.z );

		RenderAttributes.Pool.Return( attrs );
	}

	private void UpdateProbeFallback( int probeIndex )
	{
		var counts = _volume.ProbeCounts;
		var z = probeIndex / (counts.x * counts.y);
		var rem = probeIndex % (counts.x * counts.y);
		var y = rem / counts.x;
		var x = rem % counts.x;
		var probeCoord = new Vector3Int( x, y, z );

		_renderedFace = 0;
		_renderedIndex = probeIndex;
		_captureCamera.Position = _volume.GetRelocatedProbeWorldPosition( probeCoord );
		_captureCamera.RenderToCubeTexture( _captureTexture );
	}

	private void FinishProbeCapture( int probeIndex )
	{
		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "SourceProbe", _captureTexture );
		attrs.Set( "SourceDepth", _captureDepth );
		attrs.Set( "RayData", RayDataTexture );
		attrs.Set( "ProbeIndex", probeIndex );
		attrs.Set( "ProbeCounts", _volume.ProbeCounts );
		attrs.Set( "NumRays", 256 );

		FillRayDataShader.DispatchWithAttributes( attrs, (256 + 63) / 64, 1, 1 );
		RenderAttributes.Pool.Return( attrs );
	}

	public async Task Bake( CancellationToken ct )
	{
		int numProbes = _volume.ProbeCounts.x * _volume.ProbeCounts.y * _volume.ProbeCounts.z;
		if ( _isUsingFallback )
		{
			for ( int i = 0; i < numProbes; i++ )
			{
				if ( ct.IsCancellationRequested ) return;
				UpdateProbeFallback( i );
				while ( _renderedFace < 6 ) await Task.Delay( 1 );
				if ( i % 10 == 0 ) await Task.Yield();
			}
		}
		else
		{
			UpdateProbeHardwareRT();
			Graphics.FlushGPU();
		}

		for ( int i = 0; i < 64; i++ )
		{
			DispatchBlending();
			Graphics.FlushGPU();
		}
	}

	private void UpdateConstants()
	{
		var desc = new DDGIVolumeDescGPUPacked();

		var gpuDesc = new DDGIVolumeDescGPU();
		gpuDesc.origin = _volume.WorldPosition;
		gpuDesc.probeMaxRayDistance = 10000.0f;
		gpuDesc.rotation = _volume.WorldRotation;
		gpuDesc.probeSpacing = _volume.ComputeSpacing( _volume.ProbeCounts );
		gpuDesc.probeCounts = _volume.ProbeCounts;
		gpuDesc.probeNumRays = 256;
		gpuDesc.probeNumIrradianceTexels = 8;
		gpuDesc.probeNumDistanceTexels = 16;
		gpuDesc.probeHysteresis = 0.97f;
		gpuDesc.probeNormalBias = _volume.NormalBias;
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

		desc.Pack( gpuDesc );
		_descBuffer.SetData( new[] { desc } );
	}

	private void DispatchBlending()
	{
		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "DDGIVolumes", _descBuffer );
		attrs.Set( "RayData", RayDataTexture );
		attrs.Set( "ProbeData", ProbeDataTexture );

		var counts = _volume.ProbeCounts;

		attrs.Set( "Output", IrradianceTexture );
		BlendIrradianceShader.DispatchWithAttributes( attrs, counts.x, counts.y, counts.z );

		attrs.Set( "Output", DistanceTexture );
		BlendDistanceShader.DispatchWithAttributes( attrs, counts.x, counts.y, counts.z );

		RenderAttributes.Pool.Return( attrs );
	}

	private void DispatchRelocation()
	{
		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "DDGIVolumes", _descBuffer );
		attrs.Set( "RayData", RayDataTexture );
		attrs.Set( "ProbeData", ProbeDataTexture );

		int numProbes = _volume.ProbeCounts.x * _volume.ProbeCounts.y * _volume.ProbeCounts.z;
		RelocateShader.DispatchWithAttributes( attrs, (numProbes + 31) / 32, 1, 1 );

		RenderAttributes.Pool.Return( attrs );
	}

	private void DispatchClassification()
	{
		var attrs = RenderAttributes.Pool.Get();
		attrs.Set( "DDGIVolumes", _descBuffer );
		attrs.Set( "RayData", RayDataTexture );
		attrs.Set( "ProbeData", ProbeDataTexture );

		int numProbes = _volume.ProbeCounts.x * _volume.ProbeCounts.y * _volume.ProbeCounts.z;
		ClassifyShader.DispatchWithAttributes( attrs, (numProbes + 31) / 32, 1, 1 );

		RenderAttributes.Pool.Return( attrs );
	}

	public void Dispose()
	{
		RayDataTexture?.Dispose();
		IrradianceTexture?.Dispose();
		DistanceTexture?.Dispose();
		ProbeDataTexture?.Dispose();
		VariabilityTexture?.Dispose();
		VariabilityAverageTexture?.Dispose();
		_descBuffer?.Dispose();
		_captureCamera?.Dispose();
		_captureTexture?.Dispose();
		_captureDepth?.Dispose();
	}

	[StructLayout( LayoutKind.Sequential )]
	public struct DDGIVolumeDescGPUPacked
	{
		public Vector4 data0;
		public Vector4 data1;
		public Vector4 data2;
		public Vector4 data3;
		public Vector4 data4;
		public Vector4 data5;
		public Vector4 data6;
		public Vector4 data7;
		public Vector4 data8;
		public Vector4 data9;
		public Vector4 data10;
		public Vector4 data11;
		public Vector4 data12;
		public Vector4 data13;
		public Vector4 data14;
		public Vector4 data15;

		public void Pack( DDGIVolumeDescGPU v )
		{
			data0 = new Vector4( v.origin, v.probeMaxRayDistance );
			data1 = new Vector4( v.rotation.x, v.rotation.y, v.rotation.z, v.rotation.w );
			data2 = new Vector4( v.probeSpacing, v.probeHysteresis );
			data3 = new Vector4( BitConverter.Int32BitsToSingle( v.probeCounts.x ), BitConverter.Int32BitsToSingle( v.probeCounts.y ), BitConverter.Int32BitsToSingle( v.probeCounts.z ), v.probeNormalBias );
			data4 = new Vector4( v.probeViewBias, BitConverter.Int32BitsToSingle( v.probeNumRays ), BitConverter.Int32BitsToSingle( v.probeNumIrradianceTexels ), BitConverter.Int32BitsToSingle( v.probeNumDistanceTexels ) );
			data5 = new Vector4( v.probeIrradianceEncodingGamma, v.probeIrradianceThreshold, v.probeBrightnessThreshold, v.probeRandomRayBackfaceThreshold );
			data6 = new Vector4( v.probeDistanceExponent, BitConverter.Int32BitsToSingle( v.probeIrradianceFormat ), BitConverter.Int32BitsToSingle( v.probeRayDataFormat ), BitConverter.Int32BitsToSingle( v.probeRelocationEnabled ? 1 : 0 ) );
			data7 = new Vector4( BitConverter.Int32BitsToSingle( v.probeClassificationEnabled ? 1 : 0 ), BitConverter.Int32BitsToSingle( v.probeVariabilityEnabled ? 1 : 0 ), 0, 0 );
			data8 = new Vector4( v.probeScrollOffsets, 0 );
			data9 = new Vector4( BitConverter.Int32BitsToSingle( v.probeScrollDirections.x ), BitConverter.Int32BitsToSingle( v.probeScrollDirections.y ), BitConverter.Int32BitsToSingle( v.probeScrollDirections.z ), 0 );
			data10 = new Vector4( BitConverter.Int32BitsToSingle( v.probeScrollClear.x ), BitConverter.Int32BitsToSingle( v.probeScrollClear.y ), BitConverter.Int32BitsToSingle( v.probeScrollClear.z ), 0 );
			data11 = new Vector4( v.probeBackfaceThreshold, v.probeMinFrontfaceDistance, 0, 0 );
		}
	}

	public struct DDGIVolumeDescGPU
	{
		public Vector3 origin;
		public float probeMaxRayDistance;
		public Rotation rotation;
		public Vector3 probeSpacing;
		public float probeHysteresis;
		public Vector3Int probeCounts;
		public float probeNormalBias;
		public float probeViewBias;
		public int probeNumRays;
		public int probeNumIrradianceTexels;
		public int probeNumDistanceTexels;
		public float probeIrradianceEncodingGamma;
		public float probeIrradianceThreshold;
		public float probeBrightnessThreshold;
		public float probeRandomRayBackfaceThreshold;
		public float probeDistanceExponent;
		public int probeIrradianceFormat;
		public int probeRayDataFormat;
		public bool probeRelocationEnabled;
		public bool probeClassificationEnabled;
		public bool probeVariabilityEnabled;
		public Vector3 probeScrollOffsets;
		public Vector3Int probeScrollDirections;
		public Vector3Int probeScrollClear;
		public float probeBackfaceThreshold;
		public float probeMinFrontfaceDistance;
	}
}
