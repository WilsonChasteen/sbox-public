HEADER
{
	DevShader = true;
	Description = "RTXGI DDGI Probe Blending - Distance";
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

    #define RTXGI_DDGI_BLEND_RADIANCE 0
    #define RTXGI_DDGI_PROBE_NUM_TEXELS 16
    #define RTXGI_DDGI_PROBE_NUM_INTERIOR_TEXELS 14
    #define RTXGI_DDGI_BLEND_SHARED_MEMORY 1
    #define RTXGI_DDGI_BLEND_RAYS_PER_PROBE 256
    #define RTXGI_DDGI_BLEND_SCROLL_SHARED_MEMORY 1
    #define RTXGI_DDGI_NUM_FIXED_RAYS 32
    #define RTXGI_DDGI_DEBUG_PROBE_INDEXING 0
    #define RTXGI_DDGI_DEBUG_OCTAHEDRAL_INDEXING 0

	#include "common.fxc"

    // Bindings
    StructuredBuffer<DDGIVolumeDescGPUPacked> DDGIVolumes < Attribute( "DDGIVolumes" ); >;
    RWTexture2DArray<float4> RayData < Attribute( "RayData" ); >;
    RWTexture2DArray<float4> Output < Attribute( "Output" ); >;
    RWTexture2DArray<float4> ProbeData < Attribute( "ProbeData" ); >;
}

CS
{
    #include "common/rtxgi/ddgi/ProbeBlendingCS.hlsl"
}
