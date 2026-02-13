HEADER
{
	Description = "Dazzle GI - Voxelization";
	DevShader = true;
}

MODES
{
	Default();
	Forward();
	Depth();
}

FEATURES
{
    #include "vr_common_features.fxc"
}

COMMON
{
	#define CUSTOM_MATERIAL_INPUTS
	#include "common/shared.hlsl"
}

struct VertexInput
{
	#include "common/vertexinput.hlsl"
};

struct PixelInput
{
	#include "common/pixelinput.hlsl"
};

VS
{
	#include "common/vertex.hlsl"

	PixelInput MainVs( VertexInput i )
	{
		PixelInput o = ProcessVertex( i );
		return FinalizeVertex( o );
	}
}

PS
{
	RWTexture3D<float> VoxelGrid < Attribute( "VoxelGrid" ); >;
	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	void MainPs( PixelInput i )
	{
		float3 volumeSize = VolumeMax - VolumeMin;
		if ( any( volumeSize <= 1e-6f.xxx ) ) return;

		float3 pos = ( i.vPositionWithOffsetWs + g_vHighPrecisionLightingOffsetWs.xyz - VolumeMin ) / volumeSize;
		if ( any( pos < 0 ) || any( pos > 1 ) ) return;

		int3 maxVoxel = max( GridSize - 1, int3( 0, 0, 0 ) );
		int3 voxel = clamp( int3( pos * GridSize ), int3( 0, 0, 0 ), maxVoxel );
		VoxelGrid[voxel] = 1.0f;
	}
}
