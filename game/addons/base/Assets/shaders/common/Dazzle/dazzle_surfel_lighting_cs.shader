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
	ByteAddressBuffer CountBuffer < Attribute( "CountBuffer" ); >;

	[numthreads( 64, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint count = CountBuffer.Load( 0 );
		if ( id.x >= count ) return;

		DazzleSurfel s = SurfelBuffer[id.x];

		// Dummy irradiance
		s.Radiance = s.Albedo * 0.5f;

		SurfelBuffer[id.x] = s;
	}
}
