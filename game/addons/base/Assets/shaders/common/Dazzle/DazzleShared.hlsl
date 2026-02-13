#ifndef DAZZLE_SHARED_HLSL
#define DAZZLE_SHARED_HLSL

// Shared debug counters for Dazzle pipeline stage visibility.
// These are reset each frame by DazzleGISystem.
#define DAZZLE_DBG_COUNTER_COUNT 32u
#define DAZZLE_DBG_SDF_SEED_VOXELS 0u
#define DAZZLE_DBG_SDF_SEED_ACTIVE 1u
#define DAZZLE_DBG_SDF_JFA_VOXELS 2u
#define DAZZLE_DBG_SDF_JFA_UPDATES 3u
#define DAZZLE_DBG_SDF_FINALIZE_VOXELS 4u
#define DAZZLE_DBG_SDF_FINALIZE_VALID 5u
#define DAZZLE_DBG_SURFEL_MANAGE_PIXELS 6u
#define DAZZLE_DBG_SURFEL_MANAGE_DEPTH_HITS 7u
#define DAZZLE_DBG_SURFEL_MANAGE_SPAWNED 8u
#define DAZZLE_DBG_SURFEL_LIGHTING_THREADS 9u
#define DAZZLE_DBG_SURFEL_LIGHTING_NONZERO 10u
#define DAZZLE_DBG_TRACE_RAYS 11u
#define DAZZLE_DBG_TRACE_HITS 12u
#define DAZZLE_DBG_TRACE_MISSES 13u
#define DAZZLE_DBG_TRACE_STEPS 14u
#define DAZZLE_DBG_TRACE_NONZERO_RADIANCE 15u
#define DAZZLE_DBG_MERGE_DIRS 16u
#define DAZZLE_DBG_MERGE_SAMPLES 17u
#define DAZZLE_DBG_RESERVOIR_CELLS 18u
#define DAZZLE_DBG_RESERVOIR_NONZERO_CANDIDATES 19u
#define DAZZLE_DBG_RESERVOIR_REPLACEMENTS 20u
#define DAZZLE_DBG_SURFEL_COUNT 21u
#define DAZZLE_DBG_SURFEL_MANAGE_IN_VOLUME 22u

struct DazzleSurfel
{
	float3 Position;
	float3 Normal;
	float3 Albedo;
	float3 Radiance;
	float Radius;
	uint LastUsedFrame;
	float Padding[6];
};

struct DazzleReservoir
{
	float3 Radiance;
	float3 Direction;
	float Weight;
	uint M; // Sample count for ReSTIR
	float W_sum;
	float3 Normal;
	uint Epoch;
	float3 Padding;
};

#endif
