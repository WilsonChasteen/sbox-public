HEADER
{
	DevShader = true;
	Description = "RTXGI DDGI Probe Classification";
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

}

CS
{
    #define DDGIProbeClassificationCS MainCs
    #include "common/rtxgi/ddgi/ProbeClassificationCS.hlsl"
}
