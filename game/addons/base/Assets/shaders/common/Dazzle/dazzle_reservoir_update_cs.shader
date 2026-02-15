HEADER
{
	Description = "Dazzle GI - Persistent Reservoir Update";
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
	RWStructuredBuffer<DazzleReservoir> ReservoirBuffer < Attribute( "ReservoirBuffer" ); >;
	Texture2D<float4> CascadeAtlas < Attribute( "CascadeAtlas" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;

	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	float ReservoirCellSize < Attribute( "ReservoirCellSize" ); >;
	uint MaxReservoirs < Attribute( "MaxReservoirs" ); >;
	uint CurrentEpoch < Attribute( "CurrentEpoch" ); >;
	int BaseDirections < Attribute( "BaseDirections" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	uint GetHash( int3 pos )
	{
		return (uint)( ( pos.x * 73856093 ) ^ ( pos.y * 19349663 ) ^ ( pos.z * 83492791 ) );
	}

	float SimpleHash( float n )
	{
		return frac( sin( n ) * 43758.5453123 );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		// id.xyz represents a grid cell in the volume
		int3 probeCounts = int3( 16, 16, 16 );
		if ( any( (int3)id >= probeCounts ) ) return;
		DbgAdd( DAZZLE_DBG_RESERVOIR_CELLS, 1u );

		uint hash = GetHash( (int3)id );
		uint resIdx = hash % MaxReservoirs;

		DazzleReservoir r = ReservoirBuffer[resIdx];

		// Epoch-based invalidation
		if ( r.Epoch != CurrentEpoch )
		{
			r.W_sum = 0;
			r.M = 0;
			r.Epoch = CurrentEpoch;
		}

		// Resample from several level-0 cascade directions to avoid single-direction starvation.
		uint numDirs = max( (uint)BaseDirections, 1u );
		float3 candidateRadiance = 0.0f;
		const uint candidateSamples = 4u;
		[unroll]
		for ( uint s = 0u; s < candidateSamples; ++s )
		{
			uint dir = ( hash + s * 977u ) % numDirs;
			uint2 cascadePos = uint2( id.x + id.z * 16u, id.y + dir * 16u );
			candidateRadiance += CascadeAtlas.Load( int3( cascadePos, 0 ) ).rgb;
		}
		candidateRadiance *= rcp( (float)candidateSamples );
		float candidateWeight = length( candidateRadiance );
		if ( candidateWeight > 0.0f )
		{
			DbgAdd( DAZZLE_DBG_RESERVOIR_NONZERO_CANDIDATES, 1u );
		}

		// Update reservoir (Simplified ReSTIR)
		r.W_sum += candidateWeight;
		r.M += 1;
		if ( SimpleHash( (float)hash + g_flTime ) < ( candidateWeight / max( r.W_sum, 0.0001f ) ) )
		{
			DbgAdd( DAZZLE_DBG_RESERVOIR_REPLACEMENTS, 1u );
			r.Radiance = candidateRadiance;
			r.Direction = float3( 0, 1, 0 ); // Should be the actual direction
		}

		r.Weight = r.W_sum / max( (float)r.M * candidateWeight, 0.0001f );

		ReservoirBuffer[resIdx] = r;
	}
}
