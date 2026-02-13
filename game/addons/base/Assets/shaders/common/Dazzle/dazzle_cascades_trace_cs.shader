HEADER
{
	Description = "Dazzle GI - Radiance Cascade Tracing";
	DevShader = true;
}

MODES
{
	Default();
}

COMMON
{
	#include "common/shared.hlsl"
	#include "common/Dazzle/DazzleShared.hlsl"
	#include "common/Bindless.hlsl"
}

CS
{
	RWTexture2D<float4> CascadeAtlas < Attribute( "CascadeAtlas" ); >;
	Texture3D SDF < Attribute( "SDF" ); >;
	StructuredBuffer<DazzleSurfel> SurfelBuffer < Attribute( "SurfelBuffer" ); >;
	Texture3D<uint> SurfelHashGrid < Attribute( "SurfelHashGrid" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;

	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 HashGridSize < Attribute( "HashGridSize" ); >;
	uint MaxSurfels < Attribute( "MaxSurfels" ); >;
	int CascadeLevel < Attribute( "CascadeLevel" ); >;
	int TotalLevels < Attribute( "TotalLevels" ); >;
	int BaseDirections < Attribute( "BaseDirections" ); >;

	bool UseRT < Attribute( "UseRT" ); >;

	#define DAZZLE_RC_ATLAS_HEIGHT 1024u
	#define DAZZLE_RC_BASE_PROBE_DIM 16u

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	uint RequestedDirCount( uint baseDirections, uint level )
	{
		uint shift = min( level * 2u, 12u );
		return max( 1u, baseDirections << shift );
	}

	bool GetPackedLevelInfo( uint level, uint totalLevels, uint baseDirections, out uint probeDim, out uint numDirs, out uint2 atlasOffset )
	{
		probeDim = 1u;
		numDirs = 0u;
		atlasOffset = uint2( 0u, 0u );

		uint clampedLevels = clamp( totalLevels, 1u, 8u );
		uint offsetY = 0u;

		[loop]
		for ( uint l = 0u; l < clampedLevels; ++l )
		{
			uint dim = max( 1u, DAZZLE_RC_BASE_PROBE_DIM >> l );
			uint requestedDirs = RequestedDirCount( baseDirections, l );
			uint remainingRows = ( offsetY < DAZZLE_RC_ATLAS_HEIGHT ) ? ( DAZZLE_RC_ATLAS_HEIGHT - offsetY ) : 0u;
			uint maxDirsFit = remainingRows / dim;
			uint dirs = min( requestedDirs, maxDirsFit );

			if ( l == level )
			{
				probeDim = dim;
				numDirs = dirs;
				atlasOffset = uint2( 0u, offsetY );
				return dirs > 0u;
			}

			offsetY += dirs * dim;
		}

		return false;
	}

	uint2 PackedAtlasCoord( uint2 levelOffset, uint probeDim, uint3 probeCoord, uint dir )
	{
		return uint2(
			levelOffset.x + probeCoord.x + probeCoord.z * probeDim,
			levelOffset.y + probeCoord.y + dir * probeDim
		);
	}

	float SampleSDF( float3 posWs )
	{
		float3 posLocal = ( posWs - VolumeMin ) / ( VolumeMax - VolumeMin );
		if ( any( posLocal < 0 ) || any( posLocal > 1 ) ) return 10000.0f;
		return SDF.SampleLevel( g_sBilinearClamp, posLocal, 0 ).r;
	}

	float3 EstimateSDFNormal( float3 posWs, float3 voxelSize )
	{
		float3 e = max( voxelSize * 0.5f, 0.01f.xxx );
		float dx = SampleSDF( posWs + float3( e.x, 0, 0 ) ) - SampleSDF( posWs - float3( e.x, 0, 0 ) );
		float dy = SampleSDF( posWs + float3( 0, e.y, 0 ) ) - SampleSDF( posWs - float3( 0, e.y, 0 ) );
		float dz = SampleSDF( posWs + float3( 0, 0, e.z ) ) - SampleSDF( posWs - float3( 0, 0, e.z ) );
		float3 n = float3( dx, dy, dz );
		float nLenSq = dot( n, n );
		if ( nLenSq < 1e-8f )
			return float3( 0, 0, 1 );
		return normalize( n );
	}

	float3 EvaluateFallbackRadiance( float3 posWs, float3 voxelSize )
	{
		float3 n = EstimateSDFNormal( posWs, voxelSize );
		float3 sunDir = normalize( float3( 0.35f, -0.75f, 0.55f ) );
		float ndotl = saturate( dot( n, -sunDir ) );
		float3 albedo = 0.7f.xxx;
		float3 direct = albedo * ndotl * 1.25f;
		float3 ambient = albedo * 0.08f;
		return direct + ambient;
	}

	bool TryGetHashCell( float3 posWs, out int3 cell )
	{
		float3 local = ( posWs - VolumeMin ) / ( VolumeMax - VolumeMin );
		if ( any( local < 0.0f ) || any( local > 1.0f ) )
		{
			cell = int3( 0, 0, 0 );
			return false;
		}

		int3 maxCell = max( HashGridSize - 1, int3( 0, 0, 0 ) );
		cell = clamp( int3( local * HashGridSize ), int3( 0, 0, 0 ), maxCell );
		return true;
	}

	bool IsOccupied( float3 posWs )
	{
		int3 centerCell;
		if ( !TryGetHashCell( posWs, centerCell ) )
			return false;

		int3 maxCell = max( HashGridSize - 1, int3( 0, 0, 0 ) );

		[unroll]
		for ( int z = -1; z <= 1; ++z )
		{
			[unroll]
			for ( int y = -1; y <= 1; ++y )
			{
				[unroll]
				for ( int x = -1; x <= 1; ++x )
				{
					int3 cell = clamp( centerCell + int3( x, y, z ), int3( 0, 0, 0 ), maxCell );
					if ( SurfelHashGrid.Load( int4( cell, 0 ) ) > 0u )
						return true;
				}
			}
		}

		return false;
	}

	float3 GetRadianceAt( float3 posWs, float3 normal )
	{
		int3 centerCell;
		if ( !TryGetHashCell( posWs, centerCell ) )
			return 0.0f;

		int3 maxCell = max( HashGridSize - 1, int3( 0, 0, 0 ) );
		float bestDistSq = 1e30f;
		float3 bestRadiance = 0.0f;

		[unroll]
		for ( int z = -1; z <= 1; ++z )
		{
			[unroll]
			for ( int y = -1; y <= 1; ++y )
			{
				[unroll]
				for ( int x = -1; x <= 1; ++x )
				{
					int3 cell = clamp( centerCell + int3( x, y, z ), int3( 0, 0, 0 ), maxCell );
					uint packed = SurfelHashGrid.Load( int4( cell, 0 ) );
					if ( packed == 0u )
						continue;

					uint surfelIndex = packed - 1u;
					if ( surfelIndex >= MaxSurfels )
						continue;

					DazzleSurfel surfel = SurfelBuffer[surfelIndex];
					float3 toSurfel = surfel.Position - posWs;
					float distSq = dot( toSurfel, toSurfel );
					float3 wi = distSq > 1e-6f ? normalize( toSurfel ) : normal;

					float ndotl = saturate( dot( normal, wi ) );
					float surfelFacing = saturate( dot( surfel.Normal, -wi ) );
					float geom = ndotl * surfelFacing;
					if ( geom <= 0.0f )
						continue;

					float3 radiance = surfel.Radiance * geom / ( 1.0f + distSq );
					if ( distSq < bestDistSq )
					{
						bestDistSq = distSq;
						bestRadiance = radiance;
					}
				}
			}
		}

		return bestRadiance;
	}

	float3 GetDirection( uint dirIdx, uint totalDirs )
	{
		float goldenRatio = 1.61803398875f;
		float PI = 3.14159265359f;
		float i = (float)dirIdx + 0.5f;
		float phi = 2.0f * PI * goldenRatio * i;
		float cosTheta = 1.0f - 2.0f * ( i / totalDirs );
		float sinTheta = sqrt( saturate( 1.0f - cosTheta * cosTheta ) );
		return float3( cos( phi ) * sinTheta, sin( phi ) * sinTheta, cosTheta );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint level = (uint)max( CascadeLevel, 0 );
		uint totalLevels = (uint)max( TotalLevels, 1 );
		uint baseDirs = (uint)max( BaseDirections, 1 );

		uint probeDim = 0u;
		uint numDirs = 0u;
		uint2 atlasOffset = uint2( 0u, 0u );
		if ( !GetPackedLevelInfo( level, totalLevels, baseDirs, probeDim, numDirs, atlasOffset ) )
			return;

		int3 probeCounts = int3( probeDim, probeDim, probeDim );
		if ( any( (int3)id >= probeCounts ) )
			return;

		float3 spacing = ( VolumeMax - VolumeMin ) / (float3)max(probeCounts, 1);
		float3 origin = VolumeMin + ( (float3)id + 0.5f ) * spacing;

		float baseInterval = max( min( spacing.x, min( spacing.y, spacing.z ) ), 1.0f );
		float intervalMin = level == 0u ? 0.0f : ( baseInterval * ( 1u << ( level - 1u ) ) );
		float intervalMax = baseInterval * ( 1u << level );

		for ( uint d = 0u; d < numDirs; ++d )
		{
			DbgAdd( DAZZLE_DBG_TRACE_RAYS, 1u );
			float3 dir = GetDirection( d, numDirs );

			// Raymarch SDF
			float dist = intervalMin;
			float3 hitRadiance = 0.0f;
			float transmittance = 1.0f;
			float3 voxelSize = ( VolumeMax - VolumeMin ) / max( (float3)HashGridSize, 1.0f.xxx );
			float sdfHitThreshold = max( min( voxelSize.x, min( voxelSize.y, voxelSize.z ) ) * 0.75f, 0.02f );
			float minStep = max( min( voxelSize.x, min( voxelSize.y, voxelSize.z ) ) * 0.5f, 0.02f );
			float maxStep = minStep * 4.0f;

			[loop]
			for ( int i = 0; i < 96; i++ )
			{
				DbgAdd( DAZZLE_DBG_TRACE_STEPS, 1u );
				float3 pos = origin + dir * dist;
				float sdfDist = SampleSDF( pos );
				bool sdfHit = sdfDist <= sdfHitThreshold;
				if ( sdfHit || IsOccupied( pos ) )
				{
					DbgAdd( DAZZLE_DBG_TRACE_HITS, 1u );
					hitRadiance = GetRadianceAt( pos, -dir );
					if ( !any( hitRadiance > 0.0f.xxx ) )
					{
						hitRadiance = EvaluateFallbackRadiance( pos, voxelSize );
					}
					transmittance = 0.0f;
					break;
				}

				float step = clamp( sdfDist, minStep, maxStep );
				dist += step;
				if ( dist > intervalMax ) break;
			}

			if ( transmittance > 0.0f )
			{
				DbgAdd( DAZZLE_DBG_TRACE_MISSES, 1u );
			}

			if ( any( hitRadiance > 0.0f.xxx ) )
			{
				DbgAdd( DAZZLE_DBG_TRACE_NONZERO_RADIANCE, 1u );
			}

			// Store in Atlas (simplified indexing)
			uint2 atlasPos = PackedAtlasCoord( atlasOffset, probeDim, id, d );
			CascadeAtlas[atlasPos] = float4( hitRadiance * ( 1.0f - transmittance ), transmittance );
		}
	}
}
