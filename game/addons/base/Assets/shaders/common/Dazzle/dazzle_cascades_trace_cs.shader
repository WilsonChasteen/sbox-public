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

	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int CascadeLevel < Attribute( "CascadeLevel" ); >;
	int TotalLevels < Attribute( "TotalLevels" ); >;
	int BaseDirections < Attribute( "BaseDirections" ); >;

	bool UseRT < Attribute( "UseRT" ); >;

	float SampleSDF( float3 posWs )
	{
		float3 posLocal = ( posWs - VolumeMin ) / ( VolumeMax - VolumeMin );
		if ( any( posLocal < 0 ) || any( posLocal > 1 ) ) return 10000.0f;
		return SDF.SampleLevel( g_sBilinearClamp, posLocal, 0 ).r;
	}

	float3 GetRadianceAt( float3 posWs, float3 normal )
	{
		// TODO: Sample surfels or reservoirs
		return 0.1f; // Placeholder
	}

	float3 GetDirection( uint dirIdx, uint totalDirs )
	{
		float goldenRatio = 1.61803398875f;
		float PI = 3.14159265359f;
		float i = (float)dirIdx + 0.5f;
		float phi = 2.0f * PI * goldenRatio * i;
		float cosTheta = 1.0f - 2.0f * ( i / totalDirs );
		float sinTheta = sqrt( 1.0f - cosTheta * cosTheta );
		return float3( cos( phi ) * sinTheta, sin( phi ) * sinTheta, cosTheta );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		// id.xyz is probe index in the volume
		int3 probeCounts = int3( 16, 16, 16 ) >> CascadeLevel; // Coarser for higher levels
		if ( any( (int3)id >= probeCounts ) ) return;

		float3 spacing = ( VolumeMax - VolumeMin ) / (float3)probeCounts;
		float3 origin = VolumeMin + ( (float3)id + 0.5f ) * spacing;

		uint numDirs = BaseDirections << ( 2 * CascadeLevel );
		float intervalMin = CascadeLevel == 0 ? 0 : ( 1.0f * ( 1 << ( CascadeLevel - 1 ) ) );
		float intervalMax = 1.0f * ( 1 << CascadeLevel );

		// We need to store radiance for each direction
		// For now, let's just do one direction per thread and use id.w as direction index?
		// No, let's just iterate directions in a loop for simplicity in Level 0

		for ( uint d = 0; d < numDirs; d++ )
		{
			float3 dir = GetDirection( d, numDirs );

			// Raymarch SDF
			float dist = intervalMin;
			float hitRadiance = 0;
			float transmittance = 1.0f;

			[loop]
			for ( int i = 0; i < 32; i++ )
			{
				float3 pos = origin + dir * dist;
				float step = SampleSDF( pos );
				if ( step < 0.01f )
				{
					hitRadiance = GetRadianceAt( pos, -dir );
					transmittance = 0.0f;
					break;
				}
				dist += step;
				if ( dist > intervalMax ) break;
			}

			// Store in Atlas (simplified indexing)
			uint2 atlasPos = uint2( id.x + id.z * 16, id.y + d * 16 );
			CascadeAtlas[atlasPos] = float4( hitRadiance * ( 1.0f - transmittance ), transmittance, 0, 0 );
		}
	}
}
