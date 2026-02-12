HEADER
{
	Description = "Dazzle GI - Surfel Management";
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
	#include "common/classes/Depth.hlsl"
	#include "common/classes/Normals.hlsl"
}

CS
{
	RWStructuredBuffer<DazzleSurfel> SurfelBuffer < Attribute( "SurfelBuffer" ); >;
	RWByteAddressBuffer SurfelCountBuffer < Attribute( "SurfelCountBuffer" ); >;
	RWTexture3D<uint> SurfelHashGrid < Attribute( "SurfelHashGrid" ); >;

	Texture2D g_tColor < Attribute( "Color" ); >;

	uint MaxSurfels < Attribute( "MaxSurfels" ); >;
	float SurfelRadius < Attribute( "SurfelRadius" ); >;
	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 HashGridSize < Attribute( "HashGridSize" ); >;

	uint GetHash( int3 pos )
	{
		return (uint)( ( pos.x * 73856093 ) ^ ( pos.y * 19349663 ) ^ ( pos.z * 83492791 ) );
	}

	[numthreads( 8, 8, 1 )]
	void MainCs( uint2 id : SV_DispatchThreadID )
	{
		// Only sample every Nth pixel to save performance
		if ( ( id.x % 16 != 0 ) || ( id.y % 16 != 0 ) ) return;

		float depth = Depth::Get( id );
		if ( depth >= 1.0f ) return;

		float3 posWs = Position3PsToWs( float3( id, depth ) );
		if ( any( posWs < VolumeMin ) || any( posWs > VolumeMax ) ) return;

		float3 normalWs = Normals::Sample( id );
		float3 albedo = g_tColor.Load( int3( id, 0 ) ).rgb;

		// Check if covered by existing surfel
		float3 posLocal = ( posWs - VolumeMin ) / ( VolumeMax - VolumeMin );
		int3 hashPos = int3( posLocal * HashGridSize );

		// Simple spatial check in hash grid
		// For now, we just spawn if the cell is empty or if we are the first one there
		uint cellValue;
		InterlockedCompareExchange( SurfelHashGrid[hashPos], 0, 1, cellValue );

		if ( cellValue == 0 )
		{
			// Spawn new surfel
			uint index;
			SurfelCountBuffer.InterlockedAdd( 0, 1, index );

			if ( index < MaxSurfels )
			{
				DazzleSurfel s;
				s.Position = posWs;
				s.Normal = normalWs;
				s.Albedo = albedo;
				s.Radiance = 0;
				s.Radius = SurfelRadius;
				s.LastUsedFrame = (uint)g_flTime;
				SurfelBuffer[index] = s;

				// Store index in hash grid (+1 so 0 means empty)
				SurfelHashGrid[hashPos] = index + 1;
			}
		}
	}
}
