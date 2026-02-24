//---------------------------------------------------------------------------------------------------------------------
HEADER
{
	DevShader = true;
	Description = "DISCO GI compute passes for radiance propagation and temporal accumulation";
}

//---------------------------------------------------------------------------------------------------------------------
MODES
{
	Default();
}

//---------------------------------------------------------------------------------------------------------------------
FEATURES
{
}

//---------------------------------------------------------------------------------------------------------------------
COMMON
{
	#include "system.fxc"
	#include "common.fxc"
	#include "math_general.fxc"
	#include "common/classes/Bindless.hlsl"
	#include "common/classes/Depth.hlsl"
	#include "common/classes/Normals.hlsl"
	#include "common/classes/ScreenSpaceAmbientOcclusion.hlsl"

	Texture2D DiscoGI_InputColor < Attribute( "DiscoGI_InputColor" ); SrgbRead( false ); >;
	Texture2D DiscoGI_RadianceAccumulation < Attribute( "DiscoGI_RadianceAccumulation" ); >;
	Texture2D DiscoGI_SpatialCache < Attribute( "DiscoGI_SpatialCache" ); >;
	Texture2D DiscoGI_History < Attribute( "DiscoGI_History" ); >;

	RWTexture2D<float4> DiscoGI_OutAccumulation < Attribute( "DiscoGI_OutAccumulation" ); >;
	RWTexture2D<float4> DiscoGI_OutSpatial < Attribute( "DiscoGI_OutSpatial" ); >;
	RWTexture2D<float4> DiscoGI_OutHistory < Attribute( "DiscoGI_OutHistory" ); >;
	Texture2D DiscoGI_DiagInput < Attribute( "DiscoGI_DiagInput" ); >;
	RWStructuredBuffer<uint> DiscoGI_DiagBuffer < Attribute( "DiscoGI_DiagBuffer" ); >;
	int DiscoGI_DiagStage < Attribute( "DiscoGI_DiagStage" ); Default( 0 ); >;
	int DiscoGI_DiagMode < Attribute( "DiscoGI_DiagMode" ); Default( 0 ); >;

	float2 DiscoGI_InvResolution < Attribute( "DiscoGI_InvResolution" ); >;
	float2 DiscoGI_InputScale < Attribute( "DiscoGI_InputScale" ); >;

	float DiscoGI_UpdateFraction < Attribute( "DiscoGI_UpdateFraction" ); Default( 1.0f ); >;
	float DiscoGI_TemporalBlend < Attribute( "DiscoGI_TemporalBlend" ); Default( 0.9f ); >;
	float DiscoGI_BounceStrength < Attribute( "DiscoGI_BounceStrength" ); Default( 0.75f ); >;
	int DiscoGI_FrameParity < Attribute( "DiscoGI_FrameParity" ); Default( 0 ); >;

	float ComputeEnergy( float3 radiance )
	{
		return max( dot( max( radiance, 0.0f ), float3( 0.2126f, 0.7152f, 0.0722f ) ), 0.0f );
	}

	uint PackCell( uint2 pixelCoord )
	{
		return (pixelCoord.x & 0xFFFFu) | ((pixelCoord.y & 0xFFFFu) << 16u);
	}

	float2 CacheUv( uint2 pixelCoord )
	{
		return (float2( pixelCoord ) + 0.5f) * DiscoGI_InvResolution;
	}

	int2 FullResPixel( uint2 cachePixel )
	{
		return int2( (float2( cachePixel ) + 0.5f) * DiscoGI_InputScale );
	}

	bool ShouldUpdatePixel( uint2 pixelCoord )
	{
		uint pattern = (pixelCoord.x & 1u) | ((pixelCoord.y & 1u) << 1u);
		pattern = (pattern + (uint)(DiscoGI_FrameParity & 3)) & 3;

		uint activeTiles = (uint)clamp( round( saturate( DiscoGI_UpdateFraction ) * 4.0f ), 1.0f, 4.0f );
		return pattern < activeTiles;
	}

	// ----------------------------------------------------------------------------------------------------------------
	// Pass 0: Raymarching & Radiance Injection
	// ----------------------------------------------------------------------------------------------------------------
	float3 BuildRadianceAccumulation( uint2 pixelCoord, bool updatePixel )
	{
		float2 uv = CacheUv( pixelCoord );
		float3 history = DiscoGI_History.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;

		if ( !updatePixel )
		{
			return history;
		}

		int2 fullPixel = FullResPixel( pixelCoord );
		float3 normalWs = Normals::Sample( fullPixel );
		float depth = Depth::GetNormalized( fullPixel );
		float linearDepth = Depth::Linearize( depth, fullPixel + g_vViewportOffset.xy );
		float ao = ScreenSpaceAmbientOcclusion::Sample( float4( fullPixel + g_vViewportOffset.xy, 0, 0 ) );

		float3 sceneRadiance = DiscoGI_InputColor.SampleLevel( g_sBilinearClamp, uv, 1.5f ).rgb;
		float luminance = dot( sceneRadiance, float3( 0.2126f, 0.7152f, 0.0722f ) );

		float normalFacing = 0.35f + 0.65f * saturate( abs( normalWs.z ) );
		float depthAttenuation = rcp( 1.0f + linearDepth * 0.0025f );
		float aoAttenuation = max( saturate( ao ), 0.2f );
		float energyBoost = 0.6f + saturate( luminance * 0.5f );

		float3 accumulation = sceneRadiance;
		accumulation *= (0.2f + 0.8f * normalFacing);
		accumulation *= (0.4f + 0.6f * depthAttenuation);
		accumulation *= aoAttenuation;
		accumulation *= energyBoost;

		return max( accumulation, 0.0f );
	}

	// ----------------------------------------------------------------------------------------------------------------
	// Pass 1: Spatial Filtering & Local Propagation
	// ----------------------------------------------------------------------------------------------------------------
	float3 PropagateSpatialCache( uint2 pixelCoord )
	{
		float2 uv = CacheUv( pixelCoord );
		float2 sampleStep = DiscoGI_InvResolution;

		float3 center = DiscoGI_RadianceAccumulation.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float3 north = DiscoGI_RadianceAccumulation.SampleLevel( g_sBilinearClamp, uv + float2( 0, -sampleStep.y ), 0.0f ).rgb;
		float3 south = DiscoGI_RadianceAccumulation.SampleLevel( g_sBilinearClamp, uv + float2( 0, sampleStep.y ), 0.0f ).rgb;
		float3 east = DiscoGI_RadianceAccumulation.SampleLevel( g_sBilinearClamp, uv + float2( sampleStep.x, 0 ), 0.0f ).rgb;
		float3 west = DiscoGI_RadianceAccumulation.SampleLevel( g_sBilinearClamp, uv + float2( -sampleStep.x, 0 ), 0.0f ).rgb;

		float3 neighborhood = (north + south + east + west) * 0.25f;
		float bounce = max( DiscoGI_BounceStrength, 0.0f );

		float3 propagated = center + neighborhood * bounce;
		return max( propagated, 0.0f );
	}

	// ----------------------------------------------------------------------------------------------------------------
	// Pass 2: Temporal Accumulation
	// ----------------------------------------------------------------------------------------------------------------
	float ComputeReactiveFactor( uint2 pixelCoord )
	{
		int2 fullPixel = FullResPixel( pixelCoord );
		float centerDepth = Depth::GetNormalized( fullPixel );
		float rightDepth = Depth::GetNormalized( fullPixel + int2( 1, 0 ) );
		float upDepth = Depth::GetNormalized( fullPixel + int2( 0, 1 ) );

		float depthDelta = max( abs( centerDepth - rightDepth ), abs( centerDepth - upDepth ) );
		return saturate( depthDelta * 16.0f );
	}

	float3 TemporalResolve( uint2 pixelCoord, bool updatePixel )
	{
		float2 uv = CacheUv( pixelCoord );
		float3 current = DiscoGI_SpatialCache.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float3 history = DiscoGI_History.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float2 step = DiscoGI_InvResolution;
		
		float3 currentNorth = DiscoGI_SpatialCache.SampleLevel( g_sBilinearClamp, uv + float2( 0.0f, -step.y ), 0.0f ).rgb;
		float3 currentSouth = DiscoGI_SpatialCache.SampleLevel( g_sBilinearClamp, uv + float2( 0.0f, step.y ), 0.0f ).rgb;
		float3 currentEast = DiscoGI_SpatialCache.SampleLevel( g_sBilinearClamp, uv + float2( step.x, 0.0f ), 0.0f ).rgb;
		float3 currentWest = DiscoGI_SpatialCache.SampleLevel( g_sBilinearClamp, uv + float2( -step.x, 0.0f ), 0.0f ).rgb;
		
		float3 prefilteredCurrent = lerp( current, 0.25f * (currentNorth + currentSouth + currentEast + currentWest), 0.35f );

		float reactiveFactor = ComputeReactiveFactor( pixelCoord );
		float temporalBlend = saturate( DiscoGI_TemporalBlend ) * (1.0f - reactiveFactor);

		if ( !updatePixel )
		{
			temporalBlend = max( temporalBlend, 0.95f );
		}

		float3 resolved = lerp( prefilteredCurrent, history, temporalBlend );
		return max( resolved, 0.0f );
	}
}

//---------------------------------------------------------------------------------------------------------------------
CS
{
	DynamicCombo( D_PASS, 0..3, Sys( ALL ) );

	[numthreads( 8, 8, 1 )]
	void MainCs( uint3 vThreadId : SV_DispatchThreadID )
	{
		uint width = (uint)round( 1.0f / max( DiscoGI_InvResolution.x, 0.0001f ) );
		uint height = (uint)round( 1.0f / max( DiscoGI_InvResolution.y, 0.0001f ) );

		if ( any( vThreadId.xy >= uint2( width, height ) ) )
		{
			return;
		}

		uint2 pixelCoord = vThreadId.xy;
		bool updatePixel = ShouldUpdatePixel( pixelCoord );

		#if D_PASS == 0
		{
			DiscoGI_OutAccumulation[pixelCoord] = float4( BuildRadianceAccumulation( pixelCoord, updatePixel ), 1.0f );
		}
		#elif D_PASS == 1
		{
			DiscoGI_OutSpatial[pixelCoord] = float4( PropagateSpatialCache( pixelCoord ), 1.0f );
		}
		#else
		#if D_PASS == 2
		{
			DiscoGI_OutHistory[pixelCoord] = float4( TemporalResolve( pixelCoord, updatePixel ), 1.0f );
		}
		#else
		{
			// Diagnostics pass: capture whether each stage output is actually carrying energy.
			float luma = 0.0f;
			float2 uv = CacheUv( pixelCoord );

			if ( DiscoGI_DiagMode == 0 )
			{
				float3 radiance = DiscoGI_DiagInput.Load( int3( pixelCoord, 0 ) ).rgb;
				luma = ComputeEnergy( radiance );
			}
			else
			{
				int2 fullPixel = FullResPixel( pixelCoord );
				float3 sceneRadiance = DiscoGI_InputColor.SampleLevel( g_sBilinearClamp, uv, 1.5f ).rgb;
				float luminance = dot( sceneRadiance, float3( 0.2126f, 0.7152f, 0.0722f ) );
				float3 normalWs = Normals::Sample( fullPixel );
				float normalFacing = 0.35f + 0.65f * saturate( abs( normalWs.z ) );
				float depth = Depth::GetNormalized( fullPixel );
				float linearDepth = Depth::Linearize( depth, fullPixel + g_vViewportOffset.xy );
				float depthAttenuation = rcp( 1.0f + linearDepth * 0.0025f );
				float ao = ScreenSpaceAmbientOcclusion::Sample( float4( fullPixel + g_vViewportOffset.xy, 0, 0 ) );
				float aoAttenuation = max( saturate( ao ), 0.2f );
				float energyBoost = 0.6f + saturate( luminance * 0.5f );

				if ( DiscoGI_DiagMode == 1 ) luma = luminance;
				else if ( DiscoGI_DiagMode == 2 ) luma = normalFacing;
				else if ( DiscoGI_DiagMode == 3 ) luma = depthAttenuation;
				else if ( DiscoGI_DiagMode == 4 ) luma = aoAttenuation;
				else if ( DiscoGI_DiagMode == 5 ) luma = energyBoost;
			}

			uint nonZero = luma > 1e-5f ? 1u : 0u;
			uint lumaScaled = (uint)min( luma * 1024.0f, 4294967295.0f );
			uint baseIndex = (uint)max( DiscoGI_DiagStage, 0 ) * 4u;

			InterlockedAdd( DiscoGI_DiagBuffer[baseIndex + 0u], 1u );
			InterlockedAdd( DiscoGI_DiagBuffer[baseIndex + 1u], nonZero );
			InterlockedAdd( DiscoGI_DiagBuffer[baseIndex + 2u], lumaScaled );
			InterlockedMax( DiscoGI_DiagBuffer[baseIndex + 3u], lumaScaled );
		}
		#endif
		#endif
	}
}
