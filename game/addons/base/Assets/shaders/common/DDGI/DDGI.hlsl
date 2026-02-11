#ifndef DDGI_HLSL
#define DDGI_HLSL

#include "common/rtxgi/ddgi/Irradiance.hlsl"

// Bridge between engine's DDGI system and RTXGI-DDGI SDK

struct DDGIVolume
{
    uint Index;
    bool IsValid() { return Index != 0xFFFFFFFF; }
};

int DDGI_VolumeCount < Attribute( "DDGI_VolumeCount" ); >;
StructuredBuffer<DDGIVolumeDescGPUPacked> DDGI_Volumes < Attribute( "DDGI_Volumes" ); >;

class DDGI
{
    static bool IsEnabled()
    {
        return DDGI_VolumeCount > 0;
    }

    static DDGIVolume GetVolume( float3 WorldPosition )
    {
        for ( int i = 0; i < DDGI_VolumeCount; ++i )
        {
            DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU( DDGI_Volumes[i] );

            float3 localPos = WorldPosition - volume.origin;
            float3 extent = (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;

            if ( all( abs( localPos ) <= extent ) )
            {
                DDGIVolume v;
                v.Index = (uint)i;
                return v;
            }
        }

        DDGIVolume invalid;
        invalid.Index = 0xFFFFFFFF;
        return invalid;
    }

    static float3 Evaluate( DDGIVolume volume, float3 WorldPosition, float3 WorldNormal, float3 CameraDir )
    {
        DDGIVolumeDescGPU desc = UnpackDDGIVolumeDescGPU( DDGI_Volumes[volume.Index] );

        // Retrieve texture indices from the packed data where we stored them in C#
        // data12 = (IrradianceTextureIndex, DistanceTextureIndex, ProbeDataTextureIndex, Method)
        float4 indices = DDGI_Volumes[volume.Index].data12;

        DDGIVolumeResources resources;
        resources.probeIrradiance = Bindless::GetTexture2DArray( (int)indices.x );
        resources.probeDistance   = Bindless::GetTexture2DArray( (int)indices.y );
        resources.probeData       = Bindless::GetTexture2DArray( (int)indices.z );
        resources.bilinearSampler = g_sTrilinearClamp;

        float3 surfaceBias = DDGIGetSurfaceBias( WorldNormal, -CameraDir, desc );

        return DDGIGetVolumeIrradiance( WorldPosition, surfaceBias, WorldNormal, desc, resources );
    }
};

#endif
