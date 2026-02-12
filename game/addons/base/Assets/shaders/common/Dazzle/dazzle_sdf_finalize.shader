HEADER
{
	Description = "Dazzle GI - SDF Finalize";
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
	Texture3D<float4> SourceSDF < Attribute( "SourceSDF" ); >;
	RWTexture3D<float> DestSDF < Attribute( "DestSDF" ); >;
	float3 VoxelSize < Attribute( "VoxelSize" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( id >= GridSize ) ) return;

		float4 val = SourceSDF.Load( int4( id, 0 ) );
		if ( val.w > 0 )
		{
			float3 seedPos = val.xyz;
			float dist = length( ( seedPos - (float3)id ) * VoxelSize );
			DestSDF[id] = dist;
		}
		else
		{
			DestSDF[id] = 10000.0f;
		}
	}
}
