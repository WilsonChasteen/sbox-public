HEADER
{
	Description = "Dazzle GI - Surfel Dispatch Fixup";
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
	RWByteAddressBuffer DispatchBuffer < Attribute( "DispatchBuffer" ); >;
	StructuredBuffer<uint> CountBuffer < Attribute( "CountBuffer" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;
	uint MaxSurfels < Attribute( "MaxSurfels" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 1, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint rawCount = CountBuffer[0];
		uint count = min( rawCount, MaxSurfels );
		DbgAdd( DAZZLE_DBG_SURFEL_COUNT, count );
		uint groups = ( count + 63 ) / 64;
		DispatchBuffer.Store( 0, groups );
		DispatchBuffer.Store( 4, 1 );
		DispatchBuffer.Store( 8, 1 );
	}
}
