HEADER
{
	Description = "Dazzle GI - Surfel Lighting";
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
	RWStructuredBuffer<DazzleSurfel> SurfelBuffer < Attribute( "SurfelBuffer" ); >;
	StructuredBuffer<uint> CountBuffer < Attribute( "CountBuffer" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;
	uint MaxSurfels < Attribute( "MaxSurfels" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 64, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint rawCount = CountBuffer[0];
		uint count = min( rawCount, MaxSurfels );
		if ( id.x >= count ) return;
		DbgAdd( DAZZLE_DBG_SURFEL_LIGHTING_THREADS, 1u );

		DazzleSurfel s = SurfelBuffer[id.x];

		// Directional + ambient approximation to keep surfel radiance physically plausible.
		float3 sunDir = normalize( float3( 0.35f, -0.75f, 0.55f ) );
		float ndotl = saturate( dot( s.Normal, -sunDir ) );
		float3 direct = s.Albedo * ndotl * 1.25f;
		float3 ambient = s.Albedo * 0.08f;
		s.Radiance = direct + ambient;
		if ( any( s.Radiance > 0.0f.xxx ) )
		{
			DbgAdd( DAZZLE_DBG_SURFEL_LIGHTING_NONZERO, 1u );
		}

		SurfelBuffer[id.x] = s;
	}
}
