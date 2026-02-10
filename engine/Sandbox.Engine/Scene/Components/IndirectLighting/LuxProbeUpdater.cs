using Sandbox.Rendering;
using System.Threading;

namespace Sandbox;

/// <summary>
/// Lux Global Illumination updater.
/// Uses screen-space raytracing for high-performance real-time indirect lighting.
/// </summary>
internal class LuxProbeUpdater : IDisposable
{
	private readonly IndirectLightVolume _volume;
	private static ComputeShader LuxUpdateShader = new ComputeShader( "common/DDGI/lux_update_cs" );
	private static Texture BlueNoise = Texture.Load( "textures/dev/blue_noise_256.vtex" );

	private static float lastGrabTime = -1;
	private static RenderTarget grabbedColor;
	private static RenderTarget grabbedDepth;

	public LuxProbeUpdater( IndirectLightVolume volume )
	{
		_volume = volume;
	}

	public void Update()
	{
		if ( _volume.IrradianceTexture is null || _volume.DistanceTexture is null || _volume.RelocationTexture is null )
			return;

		if ( !Graphics.IsActive )
			return;

		var attrs = RenderAttributes.Pool.Get();

		// Set volume parameters
		attrs.Set( "ProbeCounts", _volume.ProbeCounts );
		attrs.Set( "ProbeSpacing", _volume.ComputeSpacing( _volume.ProbeCounts ) );
		attrs.Set( "BBoxMin", _volume.Bounds.Mins );
		attrs.Set( "BBoxMax", _volume.Bounds.Maxs );
		attrs.Set( "WorldTransform", Matrix.FromTransform( _volume.WorldTransform ) );
		attrs.Set( "NormalBias", _volume.NormalBias );
		attrs.Set( "EnergyLoss", _volume.Contrast );

		// Set textures
		attrs.Set( "IrradianceVolume", _volume.IrradianceTexture );
		attrs.Set( "DistanceVolume", _volume.DistanceTexture );
		attrs.Set( "RelocationTexture", _volume.RelocationTexture );

		// Grab textures once per frame. 
		var time = RealTime.Now;
		if ( lastGrabTime != time )
		{
			lastGrabTime = time;
			try 
			{
				grabbedColor = Graphics.GrabFrameTexture( "LuxColorBuffer" );
				grabbedDepth = Graphics.GrabDepthTexture( "LuxDepthBuffer" );
			}
			catch ( System.Exception )
			{
				grabbedColor = null;
				grabbedDepth = null;
			}
		}

		if ( grabbedColor is not null && grabbedColor.ColorTarget.IsValid() ) 
			attrs.Set( "ColorBuffer", grabbedColor.ColorTarget );
		
		if ( grabbedDepth is not null && grabbedDepth.DepthTarget.IsValid() )
		{
			attrs.Set( "DepthBuffer", grabbedDepth.DepthTarget );
			attrs.Set( "DepthChainDownsample", grabbedDepth.DepthTarget );
		}

		attrs.Set( "BlueNoiseIndex", BlueNoise.Index );

		// Random seed for ray directions
		attrs.Set( "RandomSeed", Random.Shared.NextSingle() );
		attrs.Set( "Time", (float)RealTime.Now );

		// Dispatch
		var counts = _volume.ProbeCounts;
		 LuxUpdateShader.DispatchWithAttributes( attrs, counts.x, counts.y, counts.z );

		RenderAttributes.Pool.Return( attrs );
	}

	public void Dispose()
	{
	}
}
