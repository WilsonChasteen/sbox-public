HEADER
{
	Description = "Dazzle GI - Compute Voxelization";
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
	RWTexture3D<float> VoxelGrid < Attribute( "VoxelGrid" ); >;
	RWStructuredBuffer<uint> DazzleDebugCounters < Attribute( "DazzleDebugCounters" ); >;

	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	#include "common/classes/Raytracing.hlsl"

	void DbgAdd( uint index, uint value )
	{
		uint original;
		InterlockedAdd( DazzleDebugCounters[index], value, original );
	}

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( (int3)id >= GridSize ) ) return;
		DbgAdd( DAZZLE_DBG_SDF_SEED_VOXELS, 1u );

		float3 volumeSize = VolumeMax - VolumeMin;
		float3 voxelSize = volumeSize / (float3)GridSize;
		float3 posWs = VolumeMin + ( (float3)id + 0.5f ) * voxelSize;

		bool occupied = false;

		// No shortcuts: use RayQuery to detect geometry within the voxel.
		RayDesc ray;
		ray.Origin = posWs - float3( 0, 0, voxelSize.z * 0.51f );
		ray.Direction = float3( 0, 0, 1 );
		ray.TMin = 0.0f;
		ray.TMax = voxelSize.z * 1.02f;

		RayQuery<RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
		q.TraceRayInline( Raytracing::GetAccelerationStructure(), RAY_FLAG_NONE, 0xFF, ray );
		q.Proceed();

		if ( q.CommittedStatus() == COMMITTED_TRIANGLE_HIT )
		{
			occupied = true;
		}
		else
		{
			// Check other axes for robustness if the first ray missed (it might be parallel to a thin wall)
			ray.Direction = float3( 1, 0, 0 );
			ray.Origin = posWs - float3( voxelSize.x * 0.51f, 0, 0 );
			ray.TMax = voxelSize.x * 1.02f;
			q.TraceRayInline( Raytracing::GetAccelerationStructure(), RAY_FLAG_NONE, 0xFF, ray );
			q.Proceed();
			if ( q.CommittedStatus() == COMMITTED_TRIANGLE_HIT ) occupied = true;
		}

		if ( occupied )
		{
			VoxelGrid[id] = 1.0f;
			DbgAdd( DAZZLE_DBG_SDF_SEED_ACTIVE, 1u );
		}
	}
}
