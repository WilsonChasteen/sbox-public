HEADER
{
	Description = "Dazzle GI - Radiance Cascade Merge";
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
}

CS
{
	RWTexture2D<float4> CascadeAtlas < Attribute( "CascadeAtlas" ); >;
	int CascadeLevel < Attribute( "CascadeLevel" ); >;
	int TotalLevels < Attribute( "TotalLevels" ); >;
	int BaseDirections < Attribute( "BaseDirections" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;

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

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint level = (uint)max( CascadeLevel, 0 );
		uint totalLevels = (uint)max( TotalLevels, 1 );
		uint baseDirs = (uint)max( BaseDirections, 1 );

		uint probeDim = 0u;
		uint numDirs = 0u;
		uint2 levelOffset = uint2( 0u, 0u );
		if ( !GetPackedLevelInfo( level, totalLevels, baseDirs, probeDim, numDirs, levelOffset ) )
			return;

		int3 probeCounts = int3( probeDim, probeDim, probeDim );
		if ( any( (int3)id >= probeCounts ) )
			return;

		uint nextLevel = level + 1u;
		uint nextProbeDim = 0u;
		uint nextNumDirs = 0u;
		uint2 nextLevelOffset = uint2( 0u, 0u );
		bool hasNextLevel = GetPackedLevelInfo( nextLevel, totalLevels, baseDirs, nextProbeDim, nextNumDirs, nextLevelOffset );
		uint nextMaxProbeIndex = max( nextProbeDim, 1u ) - 1u;
		uint3 nextMaxProbeIndex3 = uint3( nextMaxProbeIndex, nextMaxProbeIndex, nextMaxProbeIndex );

		for ( uint d = 0u; d < numDirs; ++d )
		{
			DbgAdd( DAZZLE_DBG_MERGE_DIRS, 1u );
			uint2 currentPos = PackedAtlasCoord( levelOffset, probeDim, id, d );
			float4 currentVal = CascadeAtlas[currentPos];

			if ( currentVal.w > 0.001f && hasNextLevel && nextNumDirs > 0u )
			{
				float3 nextRadiance = 0.0f;
				uint sampleCount = 0u;
				uint dirScale = max( nextNumDirs / max( numDirs, 1u ), 1u );
				uint nextDir = min( d * dirScale, nextNumDirs - 1u );
				uint3 childBase = min( id * 2u, nextMaxProbeIndex3 );

				[unroll]
				for ( uint z = 0u; z < 2u; ++z )
				{
					[unroll]
					for ( uint y = 0u; y < 2u; ++y )
					{
						[unroll]
						for ( uint x = 0u; x < 2u; ++x )
						{
							uint3 childProbe = min( childBase + uint3( x, y, z ), nextMaxProbeIndex3 );
							uint2 nextPos = PackedAtlasCoord( nextLevelOffset, nextProbeDim, childProbe, nextDir );
							nextRadiance += CascadeAtlas[nextPos].rgb;
							DbgAdd( DAZZLE_DBG_MERGE_SAMPLES, 1u );
							sampleCount++;
						}
					}
				}

				float invSampleCount = sampleCount > 0u ? rcp( (float)sampleCount ) : 0.0f;
				currentVal.rgb += currentVal.w * ( nextRadiance * invSampleCount );
				CascadeAtlas[currentPos] = currentVal;
			}
		}
	}
}
