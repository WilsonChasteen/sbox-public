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

	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	float ReservoirCellSize < Attribute( "ReservoirCellSize" ); >;
	uint MaxReservoirs < Attribute( "MaxReservoirs" ); >;
	uint CurrentEpoch < Attribute( "CurrentEpoch" ); >;

	uint GetHash( int3 pos )
	{
		return (uint)( ( pos.x * 73856093 ) ^ ( pos.y * 19349663 ) ^ ( pos.z * 83492791 ) );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		// id.xyz represents a grid cell in the volume
		int3 probeCounts = int3( 16, 16, 16 );
		if ( any( (int3)id >= probeCounts ) ) return;

		float3 posWs = VolumeMin + ( (float3)id + 0.5f ) * ( ( VolumeMax - VolumeMin ) / 16.0f );

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

		// Resample from Cascades
		// In a real implementation, we'd draw multiple candidates
		uint2 cascadePos = uint2( id.x + id.z * 16, id.y + 0 * 16 ); // Sample dir 0 for now
		float4 cascadeVal = CascadeAtlas.Load( int3( cascadePos, 0 ) );

		float3 candidateRadiance = cascadeVal.rgb;
		float candidateWeight = length( candidateRadiance );

		// Update reservoir (Simplified ReSTIR)
		r.W_sum += candidateWeight;
		r.M += 1;
		if ( FracSin( (float)hash + g_flTime ) < ( candidateWeight / max( r.W_sum, 0.0001f ) ) )
		{
			r.Radiance = candidateRadiance;
			r.Direction = float3( 0, 1, 0 ); // Should be the actual direction
		}

		r.Weight = r.W_sum / max( (float)r.M * candidateWeight, 0.0001f );

		ReservoirBuffer[resIdx] = r;
	}
}
