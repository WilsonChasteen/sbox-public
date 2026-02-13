HEADER
{
	Description = "Dazzle GI - SDF Seed";
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
	Texture3D<float> VoxelGrid < Attribute( "VoxelGrid" ); >;
	Texture3D<uint> SurfelHashGrid < Attribute( "SurfelHashGrid" ); >;
	RWTexture3D<float4> DestSDF < Attribute( "DestSDF" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( id >= GridSize ) ) return;
		DbgAdd( DAZZLE_DBG_SDF_SEED_VOXELS, 1u );

		bool occupied = VoxelGrid.Load( int4( id, 0 ) ) > 0.5f;
		occupied = occupied || ( SurfelHashGrid.Load( int4( id, 0 ) ) > 0u );

		if ( occupied )
		{
			DbgAdd( DAZZLE_DBG_SDF_SEED_ACTIVE, 1u );
			DestSDF[id] = float4( (float3)id, 1.0f );
		}
		else
		{
			DestSDF[id] = float4( 0, 0, 0, 0 );
		}
	}
}
