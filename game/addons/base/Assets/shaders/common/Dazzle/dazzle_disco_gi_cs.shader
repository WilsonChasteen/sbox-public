//---------------------------------------------------------------------------------------------------------------------
HEADER
{
	DevShader = true;
	Description = "Dazzle real-time DISCO GI update pass";
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

	Texture2D DazzleInputColor < Attribute( "DazzleInputColor" ); SrgbRead( false ); >;
	Texture2D DazzleDiscoIrradiance < Attribute( "DazzleDiscoIrradiance" ); >;
	Texture2D DazzleDiscoLightField < Attribute( "DazzleDiscoLightField" ); >;
	Texture2D DazzleDiscoHistory < Attribute( "DazzleDiscoHistory" ); >;

	RWTexture2D<float4> DazzleDiscoOutIrradiance < Attribute( "DazzleDiscoOutIrradiance" ); >;
	RWTexture2D<float4> DazzleDiscoOutLightField < Attribute( "DazzleDiscoOutLightField" ); >;
	RWTexture2D<float4> DazzleDiscoOutHistory < Attribute( "DazzleDiscoOutHistory" ); >;
	RWTexture2D<float4> DazzleDiscoVoxelCache < Attribute( "DazzleDiscoVoxelCache" ); >;
	RWTexture2D<float4> DazzleDiscoDirectionalCache < Attribute( "DazzleDiscoDirectionalCache" ); >;

	float2 DazzleInvDiscoSize < Attribute( "DazzleInvDiscoSize" ); >;
	float2 DazzleInputToDiscoScale < Attribute( "DazzleInputToDiscoScale" ); >;

	float Dazzle_GIUpdateFraction < Attribute( "Dazzle_GIUpdateFraction" ); Default( 1.0f ); >;
	float Dazzle_GITemporalBlend < Attribute( "Dazzle_GITemporalBlend" ); Default( 0.9f ); >;
	float Dazzle_GIBounceStrength < Attribute( "Dazzle_GIBounceStrength" ); Default( 0.8f ); >;
	float Dazzle_MultiBounceInfluence < Attribute( "Dazzle_MultiBounceInfluence" ); Default( 0.65f ); >;
	float Dazzle_ExposureCompensation < Attribute( "Dazzle_ExposureCompensation" ); Default( 1.0f ); >;
	float Dazzle_WhitePoint < Attribute( "Dazzle_WhitePoint" ); Default( 8.0f ); >;
	float Dazzle_TonemapShoulder < Attribute( "Dazzle_TonemapShoulder" ); Default( 0.75f ); >;
	int DazzleDiscoFrameParity < Attribute( "DazzleDiscoFrameParity" ); Default( 0 ); >;
	int DazzleDiscoDiagEnabled < Attribute( "DazzleDiscoDiagEnabled" ); Default( 0 ); >;
	RWStructuredBuffer<uint> DazzleDiscoDiagBuffer < Attribute( "DazzleDiscoDiagBuffer" ); >;
	float Dazzle_GIVoxelFeedback < Attribute( "Dazzle_GIVoxelFeedback" ); Default( 0.9f ); >;
	float Dazzle_GIDirectionalCache < Attribute( "Dazzle_GIDirectionalCache" ); Default( 0.7f ); >;

	static const uint Diag_Version = 1u;
	static const uint Diag_IndexVersion = 0u;
	static const uint Diag_IndexFrameParity = 1u;
	static const uint Diag_IndexCascadeWidth = 2u;
	static const uint Diag_IndexCascadeHeight = 3u;
	static const uint Diag_IndexStageMask = 4u;
	static const uint Diag_IndexTotalPixels = 5u;
	static const uint Diag_IndexUpdatedPixels = 6u;
	static const uint Diag_IndexInvalidRadiance = 7u;
	static const uint Diag_IndexNaNValues = 8u;
	static const uint Diag_IndexZeroCascade = 9u;
	static const uint Diag_IndexPropagationFailures = 10u;
	static const uint Diag_IndexMissingInputs = 11u;
	static const uint Diag_IndexTemporalInstability = 12u;
	static const uint Diag_IndexClampedValues = 13u;
	static const uint Diag_IndexNearSampleCounter = 14u;
	static const uint Diag_IndexFarSampleCounter = 15u;
	static const uint Diag_IndexTemporalSampleCounter = 16u;

	static const uint Diag_SampleCapacity = 4u;
	static const uint Diag_SampleStride = 8u;
	static const uint Diag_SamplesBaseNear = 24u;
	static const uint Diag_SamplesBaseFar = Diag_SamplesBaseNear + Diag_SampleCapacity * Diag_SampleStride;
	static const uint Diag_SamplesBaseTemporal = Diag_SamplesBaseFar + Diag_SampleCapacity * Diag_SampleStride;

	static const uint Diag_FlagInvalid = 1u;
	static const uint Diag_FlagMissingInput = 2u;
	static const uint Diag_FlagZeroCascade = 4u;
	static const uint Diag_FlagPropagationFailure = 8u;
	static const uint Diag_FlagTemporalInstability = 16u;
	static const uint Diag_FlagClamped = 32u;
	static const uint Diag_FlagSkippedUpdate = 64u;
	static const uint Diag_FlagNaN = 128u;

	bool DiagEnabled()
	{
		return DazzleDiscoDiagEnabled != 0;
	}

	bool IsFiniteFloat( float value )
	{
		return value == value && abs( value ) < 1.0e20f;
	}

	bool IsFiniteFloat3( float3 value )
	{
		return IsFiniteFloat( value.x ) && IsFiniteFloat( value.y ) && IsFiniteFloat( value.z );
	}

	float ComputeEnergy( float3 radiance )
	{
		return max( dot( max( radiance, 0.0f ), float3( 0.2126f, 0.7152f, 0.0722f ) ), 0.0f );
	}

	float3 ExposureAwareClamp( float3 radiance );
	float3 EnergyConserve( float3 radiance, float bias );

	uint PackCell( uint2 pixelCoord )
	{
		return (pixelCoord.x & 0xFFFFu) | ((pixelCoord.y & 0xFFFFu) << 16u);
	}

	void DiagAdd( uint index, uint value = 1u )
	{
		if ( !DiagEnabled() )
			return;

		uint previous;
		InterlockedAdd( DazzleDiscoDiagBuffer[index], value, previous );
	}

	void DiagInitHeader( uint2 pixelCoord, uint2 dimensions )
	{
		if ( !DiagEnabled() || any( pixelCoord != uint2( 0, 0 ) ) )
			return;

		DazzleDiscoDiagBuffer[Diag_IndexVersion] = Diag_Version;
		DazzleDiscoDiagBuffer[Diag_IndexFrameParity] = (uint)(DazzleDiscoFrameParity & 3);
		DazzleDiscoDiagBuffer[Diag_IndexCascadeWidth] = dimensions.x;
		DazzleDiscoDiagBuffer[Diag_IndexCascadeHeight] = dimensions.y;
	}

	void DiagMarkStage( uint stageMask )
	{
		if ( !DiagEnabled() )
			return;

		uint previous;
		InterlockedOr( DazzleDiscoDiagBuffer[Diag_IndexStageMask], stageMask, previous );
	}

	bool DiagShouldCapture( uint2 pixelCoord, uint stageSalt )
	{
		uint hash = pixelCoord.x * 73856093u;
		hash ^= pixelCoord.y * 19349663u;
		hash ^= stageSalt * 83492791u;
		hash ^= (uint)(DazzleDiscoFrameParity & 3) * 2654435761u;
		return (hash & 63u) == 0u;
	}

	void DiagStoreSample( uint counterIndex, uint baseIndex, uint2 pixelCoord, uint flags, float m0, float m1, float m2, float m3, float m4, float m5 )
	{
		if ( !DiagEnabled() )
			return;

		uint slot;
		InterlockedAdd( DazzleDiscoDiagBuffer[counterIndex], 1u, slot );
		if ( slot >= Diag_SampleCapacity )
			return;

		uint writeIndex = baseIndex + slot * Diag_SampleStride;
		DazzleDiscoDiagBuffer[writeIndex + 0u] = PackCell( pixelCoord );
		DazzleDiscoDiagBuffer[writeIndex + 1u] = flags;
		DazzleDiscoDiagBuffer[writeIndex + 2u] = asuint( m0 );
		DazzleDiscoDiagBuffer[writeIndex + 3u] = asuint( m1 );
		DazzleDiscoDiagBuffer[writeIndex + 4u] = asuint( m2 );
		DazzleDiscoDiagBuffer[writeIndex + 5u] = asuint( m3 );
		DazzleDiscoDiagBuffer[writeIndex + 6u] = asuint( m4 );
		DazzleDiscoDiagBuffer[writeIndex + 7u] = asuint( m5 );
	}

	float2 CascadeUv( uint2 pixelCoord )
	{
		return (float2( pixelCoord ) + 0.5f) * DazzleInvDiscoSize;
	}

	int2 FullResPixel( uint2 cascadePixel )
	{
		return int2( (float2( cascadePixel ) + 0.5f) * DazzleInputToDiscoScale );
	}

	bool ShouldUpdatePixel( uint2 pixelCoord )
	{
		uint pattern = (pixelCoord.x & 1u) | ((pixelCoord.y & 1u) << 1u);
		pattern = (pattern + (uint)(DazzleDiscoFrameParity & 3)) & 3;

		uint activeTiles = (uint)clamp( round( saturate( Dazzle_GIUpdateFraction ) * 4.0f ), 1.0f, 4.0f );
		return pattern < activeTiles;
	}

	float3 BuildNearCascade( uint2 pixelCoord, bool updatePixel )
	{
		float2 uv = CascadeUv( pixelCoord );
		float3 history = DazzleDiscoHistory.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;

		if ( !updatePixel )
		{
			if ( DiagEnabled() && DiagShouldCapture( pixelCoord, 1u ) )
			{
				float historyEnergy = ComputeEnergy( history );
				uint flags = Diag_FlagSkippedUpdate;
				if ( historyEnergy <= 1.0e-6f )
				{
					flags |= Diag_FlagZeroCascade;
					DiagAdd( Diag_IndexZeroCascade );
				}
				if ( !IsFiniteFloat3( history ) )
				{
					flags |= Diag_FlagInvalid | Diag_FlagNaN;
					DiagAdd( Diag_IndexInvalidRadiance );
					DiagAdd( Diag_IndexNaNValues );
				}

				DiagStoreSample( Diag_IndexNearSampleCounter, Diag_SamplesBaseNear, pixelCoord, flags, 0.0f, 0.0f, 0.0f, historyEnergy, historyEnergy, 0.0f );
			}
			return history;
		}

		int2 fullPixel = FullResPixel( pixelCoord );
		float3 normalWs = Normals::Sample( fullPixel );
		float depth = Depth::GetNormalized( fullPixel );
		float linearDepth = Depth::Linearize( depth, fullPixel + g_vViewportOffset.xy );
		float ao = ScreenSpaceAmbientOcclusion::Sample( float4( fullPixel + g_vViewportOffset.xy, 0, 0 ) );

		float3 sceneRadiance = DazzleInputColor.SampleLevel( g_sBilinearClamp, uv, 1.5f ).rgb;
		float luminance = dot( sceneRadiance, float3( 0.2126f, 0.7152f, 0.0722f ) );

		float normalFacing = 0.35f + 0.65f * saturate( abs( normalWs.z ) );
		float depthAttenuation = rcp( 1.0f + linearDepth * 0.0025f );
		float aoAttenuation = saturate( ao );
		float energyBoost = 0.6f + saturate( luminance * 0.5f );

		float3 nearCascade = sceneRadiance;
		nearCascade *= (0.2f + 0.8f * normalFacing);
		nearCascade *= (0.4f + 0.6f * depthAttenuation);
		nearCascade *= aoAttenuation;
		nearCascade *= energyBoost;
		nearCascade = ExposureAwareClamp( nearCascade );
		nearCascade = EnergyConserve( nearCascade, 0.8f );

		if ( DiagEnabled() )
		{
			bool aoClamped = abs( ao - aoAttenuation ) > 1.0e-5f;
			float normalLen = length( normalWs );
			bool missingInput = normalLen < 0.2f || depth <= 0.0f || depth >= 1.0f;
			bool invalidRadiance = !IsFiniteFloat3( sceneRadiance ) || !IsFiniteFloat3( nearCascade );
			bool hasNaN = sceneRadiance.x != sceneRadiance.x || sceneRadiance.y != sceneRadiance.y || sceneRadiance.z != sceneRadiance.z;
			float nearEnergy = ComputeEnergy( nearCascade );
			bool zeroCascade = nearEnergy <= 1.0e-6f;

			if ( aoClamped )
				DiagAdd( Diag_IndexClampedValues );
			if ( missingInput )
				DiagAdd( Diag_IndexMissingInputs );
			if ( invalidRadiance )
				DiagAdd( Diag_IndexInvalidRadiance );
			if ( hasNaN )
				DiagAdd( Diag_IndexNaNValues );
			if ( zeroCascade )
				DiagAdd( Diag_IndexZeroCascade );

			if ( DiagShouldCapture( pixelCoord, 2u ) )
			{
				uint flags = 0u;
				if ( aoClamped ) flags |= Diag_FlagClamped;
				if ( missingInput ) flags |= Diag_FlagMissingInput;
				if ( invalidRadiance ) flags |= Diag_FlagInvalid;
				if ( hasNaN ) flags |= Diag_FlagNaN;
				if ( zeroCascade ) flags |= Diag_FlagZeroCascade;

				DiagStoreSample(
					Diag_IndexNearSampleCounter,
					Diag_SamplesBaseNear,
					pixelCoord,
					flags,
					aoAttenuation,
					depth,
					normalLen,
					luminance,
					nearEnergy,
					energyBoost );
			}
		}

		return nearCascade;
	}


	float3 SafeNormalize3( float3 v )
	{
		float lenSq = max( dot( v, v ), 1.0e-8f );
		return v * rsqrt( lenSq );
	}

	float ComputeDirectionalAnisotropy( float3 center, float3 east, float3 west, float3 north, float3 south )
	{
		float3 gradient = abs( east - west ) + abs( north - south );
		return saturate( ComputeEnergy( gradient ) * 0.35f );
	}

	float3 PropagateCascades( uint2 pixelCoord, bool updatePixel )
	{
		float2 uv = CascadeUv( pixelCoord );
		float2 sampleStep = DazzleInvDiscoSize;

		float3 center = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float3 north = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + float2( 0, -sampleStep.y ), 0.0f ).rgb;
		float3 south = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + float2( 0, sampleStep.y ), 0.0f ).rgb;
		float3 east = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + float2( sampleStep.x, 0 ), 0.0f ).rgb;
		float3 west = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + float2( -sampleStep.x, 0 ), 0.0f ).rgb;

		float3 crossNeighborhood = (north + south + east + west) * 0.25f;
		float crossEnergy = ComputeEnergy( crossNeighborhood );
		float centerEnergy = ComputeEnergy( center );
		float variance = abs( centerEnergy - crossEnergy ) / max( centerEnergy + crossEnergy, 1.0e-4f );

		float3 neighborhood = crossNeighborhood;
		if ( variance > 0.14f )
		{
			float3 northEast = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + sampleStep * float2( 1, -1 ), 0.0f ).rgb;
			float3 northWest = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + sampleStep * float2( -1, -1 ), 0.0f ).rgb;
			float3 southEast = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + sampleStep * float2( 1, 1 ), 0.0f ).rgb;
			float3 southWest = DazzleDiscoIrradiance.SampleLevel( g_sBilinearClamp, uv + sampleStep * float2( -1, 1 ), 0.0f ).rgb;
			float3 diagNeighborhood = (northEast + northWest + southEast + southWest) * 0.25f;
			neighborhood = lerp( neighborhood, 0.6f * neighborhood + 0.4f * diagNeighborhood, saturate( variance * 1.9f ) );
		}

		float bounceRaw = Dazzle_GIBounceStrength;
		float bounce = clamp( bounceRaw, 0.0f, 2.0f );
		float multiBounce = saturate( Dazzle_MultiBounceInfluence );
		float directionalCache = saturate( Dazzle_GIDirectionalCache );
		float anisotropy = ComputeDirectionalAnisotropy( center, east, west, north, south );

		float directionalGain = lerp( 1.0f, 1.35f, directionalCache * anisotropy );
		float diffusion = bounce * directionalGain;
		float3 propagated = center + neighborhood * diffusion;
		propagated += neighborhood * diffusion * multiBounce * 0.45f;
		propagated /= (1.0f + diffusion * (1.0f + multiBounce * 0.45f));

		if ( !updatePixel )
		{
			float3 cached = DazzleDiscoVoxelCache[pixelCoord].rgb;
			propagated = lerp( propagated, cached, 0.75f );
		}

		propagated = ExposureAwareClamp( propagated );
		propagated = EnergyConserve( propagated, 0.9f );

		float voxelFeedback = clamp( Dazzle_GIVoxelFeedback, 0.0f, 2.0f );
		float3 voxelRadiance = lerp( propagated, neighborhood, directionalCache );
		DazzleDiscoVoxelCache[pixelCoord] = float4( voxelRadiance * voxelFeedback, 1.0f );
		float3 dirVector = SafeNormalize3( abs( east - west ) + abs( north - south ) + 1.0e-4f );
		DazzleDiscoDirectionalCache[pixelCoord] = float4( dirVector, 1.0f );

		if ( DiagEnabled() )
		{
			float farEnergy = ComputeEnergy( propagated );
			bool invalidRadiance = !IsFiniteFloat3( center ) || !IsFiniteFloat3( propagated );
			bool zeroCascade = farEnergy <= 1.0e-6f;
			bool propagationFailure = (centerEnergy > 1.0e-4f && farEnergy < centerEnergy * 0.02f) || (farEnergy > centerEnergy * 12.0f + 1.0e-4f);
			bool clamped = abs( bounceRaw - bounce ) > 1.0e-4f;

			if ( invalidRadiance ) DiagAdd( Diag_IndexInvalidRadiance );
			if ( zeroCascade ) DiagAdd( Diag_IndexZeroCascade );
			if ( propagationFailure ) DiagAdd( Diag_IndexPropagationFailures );
			if ( clamped ) DiagAdd( Diag_IndexClampedValues );

			if ( DiagShouldCapture( pixelCoord, 3u ) )
			{
				uint flags = 0u;
				if ( invalidRadiance ) flags |= Diag_FlagInvalid;
				if ( zeroCascade ) flags |= Diag_FlagZeroCascade;
				if ( propagationFailure ) flags |= Diag_FlagPropagationFailure;
				if ( clamped ) flags |= Diag_FlagClamped;
				if ( !updatePixel ) flags |= Diag_FlagSkippedUpdate;

				DiagStoreSample(
					Diag_IndexFarSampleCounter,
					Diag_SamplesBaseFar,
					pixelCoord,
					flags,
					centerEnergy,
					ComputeEnergy( neighborhood ),
					farEnergy,
					diffusion,
					anisotropy,
					variance );
			}
		}

		return propagated;
	}


	float3 ExposureAwareClamp( float3 radiance )
	{
		float exposure = max( Dazzle_ExposureCompensation, 0.1f );
		float whitePoint = max( Dazzle_WhitePoint, 1.0f ) * exposure;
		float shoulder = lerp( 0.7f, 1.6f, saturate( Dazzle_TonemapShoulder ) );
		float3 hdr = max( radiance * exposure, 0.0f );
		float3 mapped = hdr * (1.0f + hdr / (whitePoint * whitePoint * shoulder));
		mapped /= (1.0f + hdr);
		float restore = 1.0f + ComputeEnergy( radiance );
		return max( mapped * restore, 0.0f );
	}

	float3 EnergyConserve( float3 radiance, float bias )
	{
		float energy = ComputeEnergy( radiance );
		float conservation = rcp( 1.0f + max( energy - bias, 0.0f ) * 0.35f );
		return max( radiance * conservation, 0.0f );
	}


	float ComputeTemporalVariance( float3 center, float3 north, float3 south, float3 east, float3 west )
	{
		float centerEnergy = ComputeEnergy( center );
		float neighborhoodEnergy = 0.25f * (ComputeEnergy( north ) + ComputeEnergy( south ) + ComputeEnergy( east ) + ComputeEnergy( west ));
		return saturate( abs( centerEnergy - neighborhoodEnergy ) / max( neighborhoodEnergy + centerEnergy, 1.0e-4f ) );
	}

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
		float2 uv = CascadeUv( pixelCoord );
		float3 current = DazzleDiscoLightField.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float3 history = DazzleDiscoHistory.SampleLevel( g_sBilinearClamp, uv, 0.0f ).rgb;
		float2 step = DazzleInvDiscoSize;
		float3 currentNorth = DazzleDiscoLightField.SampleLevel( g_sBilinearClamp, uv + float2( 0.0f, -step.y ), 0.0f ).rgb;
		float3 currentSouth = DazzleDiscoLightField.SampleLevel( g_sBilinearClamp, uv + float2( 0.0f, step.y ), 0.0f ).rgb;
		float3 currentEast = DazzleDiscoLightField.SampleLevel( g_sBilinearClamp, uv + float2( step.x, 0.0f ), 0.0f ).rgb;
		float3 currentWest = DazzleDiscoLightField.SampleLevel( g_sBilinearClamp, uv + float2( -step.x, 0.0f ), 0.0f ).rgb;
		float3 prefilteredCurrent = lerp( current, 0.25f * (currentNorth + currentSouth + currentEast + currentWest), 0.35f );

		float reactiveFactor = ComputeReactiveFactor( pixelCoord );
		float temporalVariance = ComputeTemporalVariance( current, currentNorth, currentSouth, currentEast, currentWest );
		float temporalBlend = saturate( Dazzle_GITemporalBlend ) * (1.0f - reactiveFactor);
		temporalBlend = lerp( temporalBlend, temporalBlend * 0.72f, temporalVariance );

		// When doing incremental updates, preserve history harder on skipped tiles.
		if ( !updatePixel )
		{
			temporalBlend = max( temporalBlend, 0.95f );
		}

		float3 voxelCache = DazzleDiscoVoxelCache[pixelCoord].rgb;
		float3 directionalCache = DazzleDiscoDirectionalCache[pixelCoord].rgb;
		float directionalLuma = saturate( dot( directionalCache, float3( 0.577f, 0.577f, 0.577f ) ) );
		float cacheWeight = saturate( Dazzle_GIDirectionalCache ) * lerp( 0.35f, 0.65f, directionalLuma );
		float3 cacheFused = lerp( prefilteredCurrent, voxelCache, cacheWeight );
		cacheFused *= (0.75f + 0.25f * directionalLuma);
		float historyTrust = saturate( temporalBlend * (0.9f + 0.1f * directionalLuma) );
		float3 resolved = lerp( cacheFused, history, historyTrust );
		resolved = ExposureAwareClamp( resolved );
		resolved = EnergyConserve( resolved, 1.0f );

		if ( DiagEnabled() )
		{
			float currentEnergy = ComputeEnergy( current );
			float historyEnergy = ComputeEnergy( history );
			float resolvedEnergy = ComputeEnergy( resolved );
			float deltaEnergy = abs( currentEnergy - historyEnergy );

			bool invalidRadiance = !IsFiniteFloat3( current ) || !IsFiniteFloat3( history ) || !IsFiniteFloat3( resolved );
			bool zeroCascade = resolvedEnergy <= 1.0e-6f;
			bool temporalInstability = deltaEnergy > (0.12f + historyEnergy * 1.10f) && temporalBlend > 0.72f;
			bool clamped = temporalBlend <= 0.001f || temporalBlend >= 0.999f;

			if ( invalidRadiance ) DiagAdd( Diag_IndexInvalidRadiance );
			if ( zeroCascade ) DiagAdd( Diag_IndexZeroCascade );
			if ( temporalInstability ) DiagAdd( Diag_IndexTemporalInstability );
			if ( clamped ) DiagAdd( Diag_IndexClampedValues );

			if ( DiagShouldCapture( pixelCoord, 4u ) )
			{
				uint flags = 0u;
				if ( invalidRadiance ) flags |= Diag_FlagInvalid;
				if ( zeroCascade ) flags |= Diag_FlagZeroCascade;
				if ( temporalInstability ) flags |= Diag_FlagTemporalInstability;
				if ( clamped ) flags |= Diag_FlagClamped;
				if ( !updatePixel ) flags |= Diag_FlagSkippedUpdate;

				DiagStoreSample(
					Diag_IndexTemporalSampleCounter,
					Diag_SamplesBaseTemporal,
					pixelCoord,
					flags,
					currentEnergy,
					historyEnergy,
					resolvedEnergy,
					temporalBlend,
					reactiveFactor,
					temporalVariance );
			}
		}

		return resolved;
	}
}

//---------------------------------------------------------------------------------------------------------------------
CS
{
	DynamicCombo( D_PASS, 0..2, Sys( ALL ) );

	[numthreads( 8, 8, 1 )]
	void MainCs( uint3 vThreadId : SV_DispatchThreadID )
	{
		uint width;
		uint height;
		DazzleDiscoOutHistory.GetDimensions( width, height );

		if ( any( vThreadId.xy >= uint2( width, height ) ) )
		{
			return;
		}

		uint2 pixelCoord = vThreadId.xy;
		bool updatePixel = ShouldUpdatePixel( pixelCoord );

		if ( DiagEnabled() )
		{
			DiagInitHeader( pixelCoord, uint2( width, height ) );
			DiagAdd( Diag_IndexTotalPixels );
			if ( updatePixel )
			{
				DiagAdd( Diag_IndexUpdatedPixels );
			}
		}

		#if D_PASS == 0
		{
			DiagMarkStage( 1u << 0 );
			DazzleDiscoOutIrradiance[pixelCoord] = float4( BuildNearCascade( pixelCoord, updatePixel ), 1.0f );
		}
		#elif D_PASS == 1
		{
			DiagMarkStage( 1u << 1 );
			DazzleDiscoOutLightField[pixelCoord] = float4( PropagateCascades( pixelCoord, updatePixel ), 1.0f );
		}
		#else
		{
			DiagMarkStage( 1u << 2 );
			DazzleDiscoOutHistory[pixelCoord] = float4( TemporalResolve( pixelCoord, updatePixel ), 1.0f );
		}
		#endif
	}
}
