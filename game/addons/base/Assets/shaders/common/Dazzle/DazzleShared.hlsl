#ifndef DAZZLE_SHARED_HLSL
#define DAZZLE_SHARED_HLSL

struct DazzleSurfel
{
	float3 Position;
	float3 Normal;
	float3 Albedo;
	float3 Radiance;
	float Radius;
	uint LastUsedFrame;
	float3 Padding;
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
