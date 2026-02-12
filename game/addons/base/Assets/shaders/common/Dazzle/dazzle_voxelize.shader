HEADER
{
	Description = "Dazzle GI - Voxelization";
	DevShader = true;
}

MODES
{
	Default();
}

FEATURES
{
    #include "vr_common_features.fxc"
}

COMMON
{
	#define CUSTOM_MATERIAL_INPUTS
	#include "common/shared.hlsl"
	#include "common/Bindless.hlsl"

	RWTexture3D<float> VoxelGrid < Attribute( "VoxelGrid" ); >;
	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;
}

struct VertexInput
{
	float3 Position : POSITION < Semantic( PosXyz ); >;
};

struct PixelInput
{
	float3 WorldPosition : TEXCOORD0;
	float4 PixelPosition : SV_Position;
};

VS
{
	PixelInput MainVs( VertexInput i )
	{
		PixelInput o;
		o.WorldPosition = mul( g_matLocalToWorld, float4( i.Position, 1.0 ) ).xyz;
		o.PixelPosition = mul( g_matWorldToProjection, float4( o.WorldPosition, 1.0 ) );
		return o;
	}
}

PS
{
	void MainPs( PixelInput i )
	{
		float3 pos = ( i.WorldPosition - VolumeMin ) / ( VolumeMax - VolumeMin );
		if ( any( pos < 0 ) || any( pos > 1 ) ) return;

		int3 voxel = int3( pos * GridSize );
		VoxelGrid[voxel] = 1.0f;
	}
}
