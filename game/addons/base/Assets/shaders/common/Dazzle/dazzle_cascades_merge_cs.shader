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
	int BaseDirections < Attribute( "BaseDirections" ); >;

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		int3 probeCounts = int3( 16, 16, 16 ) >> CascadeLevel;
		if ( any( (int3)id >= probeCounts ) ) return;

		uint numDirs = (uint)BaseDirections << ( 2 * CascadeLevel );

		for ( uint d = 0; d < numDirs; d++ )
		{
			uint2 currentPos = uint2( id.x + id.z * 16, id.y + d * 16 );
			float4 currentVal = CascadeAtlas[currentPos];

			if ( currentVal.y > 0.001f )
			{
				float3 nextProbePos = (float3)id * 0.5f;
				float3 nextRadiance = 0;

				uint3 nextId = uint3( nextProbePos );

				for ( uint nd = 0; nd < 4; nd++ )
				{
					uint2 nextPos = uint2( nextId.x + nextId.z * 16, nextId.y + ( d * 4 + nd ) * 16 );
					nextRadiance += CascadeAtlas[nextPos].rgb * 0.25f;
				}

				currentVal.rgb += currentVal.a * nextRadiance; // Using a for transmittance? Wait, I stored it in y.
				// Wait, in trace shader: CascadeAtlas[atlasPos] = float4( hitRadiance * ( 1.0f - transmittance ), transmittance );
				// So y is transmittance.
				currentVal.rgb += currentVal.y * nextRadiance;
				CascadeAtlas[currentPos] = currentVal;
			}
		}
	}
}
