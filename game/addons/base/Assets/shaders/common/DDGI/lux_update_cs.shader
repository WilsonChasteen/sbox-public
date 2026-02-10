//---------------------------------------------------------------------------------------------------------------------
HEADER
{
	DevShader = true;
	Description = "Lux GI Real-time Probe Updater";
}

//---------------------------------------------------------------------------------------------------------------------
MODES
{
	Default();
}

//---------------------------------------------------------------------------------------------------------------------
FEATURES
{
}

//---------------------------------------------------------------------------------------------------------------------
COMMON
{
	#include "common.fxc"
	#include "math_general.fxc"
	#include "common_samplers.fxc"
	#include "common/DDGI/DDGI.hlsl"
	#include "common/Bindless.hlsl"
	#include "common/classes/Depth.hlsl"
	#include "common/classes/ScreenSpaceTrace.hlsl"

	RWTexture3D<float4> IrradianceVolume < Attribute( "IrradianceVolume" ); >;
	RWTexture3D<float2> DistanceVolume < Attribute( "DistanceVolume" ); >;
	Texture3D RelocationTexture < Attribute( "RelocationTexture" ); >;

	float RandomSeed < Attribute( "RandomSeed" ); >;
	float Time < Attribute( "Time" ); >;
	float EnergyLoss < Attribute( "EnergyLoss" ); Default( 1.0f ); >;

	float3 BBoxMin < Attribute( "BBoxMin" ); >;
	float3 BBoxMax < Attribute( "BBoxMax" ); >;
	float3 ProbeSpacing < Attribute( "ProbeSpacing" ); >;
	int3 ProbeCounts < Attribute( "ProbeCounts" ); >;

	Texture2D ColorBuffer < Attribute( "ColorBuffer" ); >;
	
	int BlueNoiseIndex < Attribute( "BlueNoiseIndex" ); >;

	#define ProbeSampler g_sTrilinearClamp

	// Better random using blue noise
	float3 GetRandomDirection( int3 probeIndex, uint rayIdx )
	{
		int2 noiseCoord = (probeIndex.xy + int2(rayIdx * 17, rayIdx * 31) + int2(Time * 100, Time * 200)) % 256;
		float3 noise = Bindless::GetTexture2D(BlueNoiseIndex)[noiseCoord].rgb;
		
		float theta = noise.x * 2.0 * 3.14159;
		float phi = acos( 2.0 * noise.y - 1.0 );
		return float3( sin( phi ) * cos( theta ), sin( phi ) * sin( theta ), cos( phi ) );
	}

	float3 GetProbeWorldPosition( int3 index )
	{
		return BBoxMin + float3( index ) * ProbeSpacing;
	}
}

//---------------------------------------------------------------------------------------------------------------------
CS
{
	float3 HammersleyHemisphere(uint i, uint N)
	{
		float rdi = frac(float(i) * 0.754877666f);
		float phi = 2.0 * 3.14159265 * rdi;
		float cosTheta = 1.0 - (float(i) + 0.5) / float(N);
		float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
		return float3(
			cos(phi) * sinTheta,
			sin(phi) * sinTheta,
			cosTheta
		);
	}

	void WriteProbeTexels(
		int3 probeIndex,
		float3 dir,
		float3 radiance,
		float dist
	)
	{
		float2 oct = DDGI::OctahedralEncode(dir);

		// Irradiance
		{
			const uint res = DDGI_IRRADIANCE_OCT_RESOLUTION;
			uint2 baseCoord = DDGI::BaseCoordinate(probeIndex.xy, res);
			uint2 texel = uint2(oct * res);
			uint3 dst = uint3(baseCoord + 1 + texel, probeIndex.z);

			IrradianceVolume[dst] = float4(radiance, 1.0);
		}

		// Distance
		{
			const uint res = DDGI_DISTANCE_OCT_RESOLUTION;
			uint2 baseCoord = DDGI::BaseCoordinate(probeIndex.xy, res);
			uint2 texel = uint2(oct * res);
			uint3 dst = uint3(baseCoord + 1 + texel, probeIndex.z);

			DistanceVolume[dst] = float2(dist, dist * dist);
		}
	}

	[numthreads(8,8,1)]
	void MainCs(uint3 id : SV_DispatchThreadID)
	{
		int3 probeIndex = int3(id);
		if (any(probeIndex >= ProbeCounts)) return;

		float4 relocation = RelocationTexture.Load(int4(probeIndex, 0));
		if (relocation.w < 0.5) return;

		float3 probePos = GetProbeWorldPosition(probeIndex) + relocation.xyz;

		const uint RAY_COUNT = 64;

		float3 accumulatedRadiance = 0;
		float accumulatedWeight = 0;

		for (uint i = 0; i < RAY_COUNT; ++i)
		{
			float3 rayDir = HammersleyHemisphere(i, RAY_COUNT);

			TraceResult hit = ScreenSpace::Trace(probePos, rayDir, 48);
			if (!hit.ValidHit) continue;

			float2 uv = hit.HitClipSpace.xy * 0.5 + 0.5;
			uv.y = 1.0 - uv.y;

			float3 color = ColorBuffer.SampleLevel(g_sBilinearClamp, uv, 0).rgb;

			float3 hitWs = InvProjectPosition(hit.HitClipSpace.xyz, g_matProjectionToWorld) + g_vCameraPositionWs;
			float dist = distance(probePos, hitWs);

			float weight = max(dot(rayDir, normalize(hitWs - probePos)), 0.0);

			accumulatedRadiance += color * weight;
			accumulatedWeight += weight;

			WriteProbeTexels(probeIndex, rayDir, color, dist);
		}

		if (accumulatedWeight > 0)
		{
			float3 finalRadiance = accumulatedRadiance / accumulatedWeight;

			// Write a fallback average to center texel for stability
			WriteProbeTexels(probeIndex, float3(0,0,1), finalRadiance, 1.0);
		}
	}
}
