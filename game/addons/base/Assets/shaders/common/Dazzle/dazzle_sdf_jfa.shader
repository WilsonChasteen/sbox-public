HEADER
{
	Description = "Dazzle GI - Jump Flood Algorithm for SDF generation";
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
	RWTexture3D<float4> DestSDF < Attribute( "DestSDF" ); >;
	Texture3D SourceSDF < Attribute( "SourceSDF" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;
	int StepSize < Attribute( "StepSize" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( id >= GridSize ) ) return;
		DbgAdd( DAZZLE_DBG_SDF_JFA_VOXELS, 1u );

		float4 best = SourceSDF.Load( int4( id, 0 ) );
		float bestDistSq = 1e30f;

		if ( best.w > 0 )
		{
			float3 seedPos = best.xyz;
			float3 diff = seedPos - (float3)id;
			bestDistSq = dot( diff, diff );
		}

		[unroll]
		for ( int z = -1; z <= 1; ++z )
		{
			[unroll]
			for ( int y = -1; y <= 1; ++y )
			{
				[unroll]
				for ( int x = -1; x <= 1; ++x )
				{
					if ( x == 0 && y == 0 && z == 0 ) continue;

					int3 samplePos = (int3)id + int3( x, y, z ) * StepSize;
					if ( any( samplePos < 0 ) || any( samplePos >= GridSize ) ) continue;

					float4 val = SourceSDF.Load( int4( samplePos, 0 ) );
					if ( val.w > 0 )
					{
						float3 seedPos = val.xyz;
						float3 diff = seedPos - (float3)id;
						float distSq = dot( diff, diff );
						if ( distSq < bestDistSq )
						{
							DbgAdd( DAZZLE_DBG_SDF_JFA_UPDATES, 1u );
							bestDistSq = distSq;
							best = val;
						}
					}
				}
			}
		}

		DestSDF[id] = best;
	}
}
