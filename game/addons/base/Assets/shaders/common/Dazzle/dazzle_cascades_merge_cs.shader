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
	int CascadeLevel < Attribute( "CascadeLevel" ); >; // The level we are merging INTO (lower level)

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		// id.xyz is probe index at CascadeLevel
		int3 probeCounts = int3( 16, 16, 16 ) >> CascadeLevel;
		if ( any( (int3)id >= probeCounts ) ) return;

		uint numDirs = 16u << ( 2 * CascadeLevel );

		for ( uint d = 0; d < numDirs; d++ )
		{
			uint2 currentPos = uint2( id.x + id.z * 16, id.y + d * 16 );
			float4 currentVal = CascadeAtlas[currentPos];

			if ( currentVal.y > 0.001f ) // If there is remaining transmittance
			{
				// Sample from next level (CascadeLevel + 1)
				// Next level is coarser spatially but finer angularly
				float3 nextProbePos = (float3)id * 0.5f;
				// Angularly: current direction maps to 4 directions in next level
				float3 nextRadiance = 0;

				// Simplified: just sample the corresponding probe in next level
				uint3 nextId = uint3( nextProbePos );
				uint nextNumDirs = 16u << ( 2 * ( CascadeLevel + 1 ) );

				for ( uint nd = 0; nd < 4; nd++ )
				{
					uint2 nextPos = uint2( nextId.x + nextId.z * 16, nextId.y + ( d * 4 + nd ) * 16 );
					nextRadiance += CascadeAtlas[nextPos].rgb * 0.25f;
				}

				currentVal.rgb += currentVal.y * nextRadiance;
				CascadeAtlas[currentPos] = currentVal;
			}
		}
	}
}
