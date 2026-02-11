HEADER
{
	DevShader = true;
	Description = "RTXGI DDGI Probe Tracing - Hardware RT";
}

MODES
{
	Default();
}

COMMON
{
    #define RTXGI_DDGI_RESOURCE_MANAGEMENT 0
	#define RTXGI_DDGI_SHADER_REFLECTION 1
	#define RTXGI_DDGI_BINDLESS_RESOURCES 0
    #define RTXGI_COORDINATE_SYSTEM 3
    #define RTXGI_DDGI_NUM_FIXED_RAYS 32

	#include "common.fxc"
    #include "common/classes/Raytracing.hlsl"

    // Bindings
    StructuredBuffer<DDGIVolumeDescGPUPacked> DDGIVolumes < Attribute( "DDGIVolumes" ); >;
    RWTexture2DArray<float4> RayData < Attribute( "RayData" ); >;
    RWTexture2DArray<float4> ProbeData < Attribute( "ProbeData" ); >;

    // For recursive irradiance
    Texture2DArray<float4> IrradianceTexture < Attribute( "IrradianceTexture" ); >;
    Texture2DArray<float4> DistanceTexture < Attribute( "DistanceTexture" ); >;

    // Placeholder for lighting info
    float3 skyRadiance < Attribute( "skyRadiance" ); Default3( 0.5, 0.7, 1.0 ); >;
}

RT
{
    // We need to implement RayGen, Miss, and CHS here
    // RTXGI SDK provides ProbeTraceRGS.hlsl but it needs some adapting

    #include "common/rtxgi/ddgi/Irradiance.hlsl"

    [shader("raygeneration")]
    void RayGen()
    {
        uint volumeIndex = 0; // Assume first volume for now or get from root constants
        DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU( DDGIVolumes[volumeIndex] );

        uint3 rayIdx = DispatchRaysIndex();
        int rayIndex = rayIdx.x;
        int probePlaneIndex = rayIdx.y;
        int planeIndex = rayIdx.z;
        int probesPerPlane = volume.probeCounts.x * volume.probeCounts.y;
        int probeIndex = (planeIndex * probesPerPlane) + probePlaneIndex;

        int3 probeCoords = DDGIGetProbeCoords( probeIndex, volume );
        int scrollingProbeIndex = DDGIGetScrollingProbeIndex( probeCoords, volume );

        float probeState = DDGILoadProbeState( scrollingProbeIndex, ProbeData, volume );
        if ( probeState == RTXGI_DDGI_PROBE_STATE_INACTIVE && rayIndex >= RTXGI_DDGI_NUM_FIXED_RAYS ) return;

        float3 probeWorldPosition = DDGIGetProbeWorldPosition( probeCoords, volume, ProbeData );
        float3 probeRayDirection = DDGIGetProbeRayDirection( rayIndex, volume );
        uint3 outputCoords = DDGIGetRayDataTexelCoords( rayIndex, scrollingProbeIndex, volume );

        RayDesc ray;
        ray.Origin = probeWorldPosition;
        ray.Direction = probeRayDirection;
        ray.TMin = 0.001;
        ray.TMax = volume.probeMaxRayDistance;

        // Trace
        RaytracingAccelerationStructure SceneTLAS = Raytracing::GetAccelerationStructure();

        // Simple payload for now
        struct Payload {
            float3 radiance;
            float hitT;
            bool isBackface;
        };
        Payload payload;
        payload.radiance = skyRadiance;
        payload.hitT = -1.0f;
        payload.isBackface = false;

        TraceRay( SceneTLAS, RAY_FLAG_NONE, 0xFF, 0, 0, 0, ray, payload );

        if ( payload.hitT < 0.0f )
        {
            DDGIStoreProbeRayMiss( RayData, outputCoords, volume, payload.radiance );
            return;
        }

        if ( payload.isBackface )
        {
            DDGIStoreProbeRayBackfaceHit( RayData, outputCoords, volume, payload.hitT );
            return;
        }

        if ( (volume.probeRelocationEnabled || volume.probeClassificationEnabled) && rayIndex < RTXGI_DDGI_NUM_FIXED_RAYS )
        {
            DDGIStoreProbeRayFrontfaceHit( RayData, outputCoords, volume, payload.hitT );
            return;
        }

        // Recursive GI
        float3 irradiance = 0;
        DDGIVolumeResources resources;
        resources.probeIrradiance = IrradianceTexture;
        resources.probeDistance = DistanceTexture;
        resources.probeData = ProbeData;
        resources.bilinearSampler = g_sTrilinearClamp;

        float3 hitPosition = ray.Origin + ray.Direction * payload.hitT;
        // Assume some hit normal for recursive GI, for now we don't have it in payload
        float3 hitNormal = -ray.Direction; // Hack

        float3 surfaceBias = DDGIGetSurfaceBias( hitNormal, ray.Direction, volume );
        irradiance = DDGIGetVolumeIrradiance( hitPosition, surfaceBias, hitNormal, volume, resources );

        float3 radiance = payload.radiance + irradiance * 0.9f / 3.14159;
        DDGIStoreProbeRayFrontfaceHit( RayData, outputCoords, volume, radiance, payload.hitT );
    }

    [shader("miss")]
    void Miss( inout Payload payload )
    {
        payload.radiance = skyRadiance;
        payload.hitT = -1.0f;
    }

    [shader("closesthit")]
    void ClosestHit( inout Payload payload, in BuiltInTriangleIntersectionAttributes attr )
    {
        payload.hitT = RayTCurrent();
        payload.radiance = float3( 0.5, 0.5, 0.5 ); // Simple gray for now
        payload.isBackface = HitKind() == HIT_KIND_TRIANGLE_BACK_FACE;
    }
}
