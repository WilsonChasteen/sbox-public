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
	RWStructuredBuffer<uint> SurfelCountBuffer < Attribute( "SurfelCountBuffer" ); >;
	RWTexture3D<uint> SurfelHashGrid < Attribute( "SurfelHashGrid" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;

	Texture2D g_tColor < Attribute( "Color" ); >;

	uint MaxSurfels < Attribute( "MaxSurfels" ); >;
	float SurfelRadius < Attribute( "SurfelRadius" ); >;
	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 HashGridSize < Attribute( "HashGridSize" ); >;
	int2 ScreenSize < Attribute( "ScreenSize" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 8, 8, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( (int2)id.xy >= ScreenSize ) ) return;

		// Subsample the screen for stability/performance without starving surfel coverage.
		if ( ( id.x % 4 != 0 ) || ( id.y % 4 != 0 ) ) return;
		DbgAdd( DAZZLE_DBG_SURFEL_MANAGE_PIXELS, 1u );

		float depth = Depth::Get( id.xy );
		if ( depth >= 1.0f ) return;
		DbgAdd( DAZZLE_DBG_SURFEL_MANAGE_DEPTH_HITS, 1u );

		float3 posWs = Depth::GetWorldPosition( id.xy );
		if ( any( isnan( posWs ) ) || any( isinf( posWs ) ) ) return;
		float3 volumeSize = VolumeMax - VolumeMin;
		if ( any( volumeSize <= 1e-6f.xxx ) ) return;
		float3 posLocal = ( posWs - VolumeMin ) / volumeSize;
		if ( any( posLocal < 0.0f.xxx ) || any( posLocal > 1.0f.xxx ) ) return;
		DbgAdd( DAZZLE_DBG_SURFEL_MANAGE_IN_VOLUME, 1u );

		float3 normalWs = Normals::Sample( id.xy );
		float nLenSq = dot( normalWs, normalWs );
		if ( nLenSq < 1e-6f || any( isnan( normalWs ) ) || any( isinf( normalWs ) ) )
		{
			normalWs = float3( 0.0f, 0.0f, 1.0f );
		}
		else
		{
			normalWs *= rsqrt( nLenSq );
		}
		float3 albedo = g_tColor.Load( int3( id.xy, 0 ) ).rgb;
		if ( all( albedo <= 0.0f.xxx ) )
		{
			albedo = 0.7f.xxx;
		}

		int3 maxHashPos = max( HashGridSize - 1, int3( 0, 0, 0 ) );
		int3 hashPos = clamp( int3( posLocal * HashGridSize ), int3( 0, 0, 0 ), maxHashPos );

		uint index;
		InterlockedAdd( SurfelCountBuffer[0], 1u, index );

		if ( index < MaxSurfels )
		{
			DbgAdd( DAZZLE_DBG_SURFEL_MANAGE_SPAWNED, 1u );
			DazzleSurfel s;
			s.Position = posWs;
			s.Normal = normalWs;
			s.Albedo = albedo;
			s.Radiance = 0;
			s.Radius = SurfelRadius;
			s.LastUsedFrame = (uint)g_flTime;
			SurfelBuffer[index] = s;

			SurfelHashGrid[hashPos] = index + 1;
		}
	}
}
