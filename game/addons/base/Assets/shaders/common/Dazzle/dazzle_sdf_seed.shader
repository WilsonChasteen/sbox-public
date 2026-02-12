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
}

CS
{
	Texture3D<float> VoxelGrid < Attribute( "VoxelGrid" ); >;
	RWTexture3D<float4> DestSDF < Attribute( "DestSDF" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( id >= GridSize ) ) return;

		if ( VoxelGrid.Load( int4( id, 0 ) ) > 0.5f )
		{
			DestSDF[id] = float4( (float3)id, 1.0f );
		}
		else
		{
			DestSDF[id] = float4( 0, 0, 0, 0 );
		}
	}
}
