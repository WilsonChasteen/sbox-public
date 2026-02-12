#ifndef RTXGI_DDGI_VOLUME_DESC_GPU_H
#define RTXGI_DDGI_VOLUME_DESC_GPU_H

// Engine-packed GPU volume data layout (matches RTXGIVolumeUpdater.DDGIVolumeDescGPUPacked).
struct DDGIVolumeDescGPUPacked
{
    float4 data0;
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
    float4 data5;
    float4 data6;
    float4 data7;
    float4 data8;
    float4 data9;
    float4 data10;
    float4 data11;
    float4 data12;
    float4 data13;
    float4 data14;
    float4 data15;
};

struct DDGIVolumeResourceIndices
{
    uint rayDataUAVIndex;
    uint rayDataSRVIndex;
    uint probeIrradianceUAVIndex;
    uint probeIrradianceSRVIndex;
    uint probeDistanceUAVIndex;
    uint probeDistanceSRVIndex;
    uint probeDataUAVIndex;
    uint probeDataSRVIndex;
    uint probeVariabilityUAVIndex;
    uint probeVariabilitySRVIndex;
    uint probeVariabilityAverageUAVIndex;
    uint probeVariabilityAverageSRVIndex;
};

struct DDGIVolumeDescGPU
{
    float3 origin;
    float4 rotation;
    float4 probeRayRotation;
    uint movementType;
    float3 probeSpacing;
    int3 probeCounts;
    int probeNumRays;
    int probeNumIrradianceInteriorTexels;
    int probeNumDistanceInteriorTexels;
    float probeHysteresis;
    float probeMaxRayDistance;
    float probeNormalBias;
    float probeViewBias;
    float probeDistanceExponent;
    float probeIrradianceEncodingGamma;
    float probeIrradianceThreshold;
    float probeBrightnessThreshold;
    float probeRandomRayBackfaceThreshold;
    float probeFixedRayBackfaceThreshold;
    float probeMinFrontfaceDistance;
    int3 probeScrollOffsets;
    bool probeScrollClear[3];
    bool probeScrollDirections[3];
    uint probeRayDataFormat;
    uint probeIrradianceFormat;
    bool probeRelocationEnabled;
    bool probeClassificationEnabled;
    bool probeVariabilityEnabled;
};

DDGIVolumeDescGPU UnpackDDGIVolumeDescGPU(DDGIVolumeDescGPUPacked input)
{
    DDGIVolumeDescGPU output = (DDGIVolumeDescGPU)0;

    output.origin = input.data0.xyz;
    output.probeMaxRayDistance = input.data0.w;
    output.rotation = input.data1;

    // Engine data does not currently provide a separate probe ray rotation.
    output.probeRayRotation = input.data1;

    output.movementType = 0;
    output.probeSpacing = input.data2.xyz;
    output.probeHysteresis = input.data2.w;

    output.probeCounts = int3(asint(input.data3.x), asint(input.data3.y), asint(input.data3.z));
    output.probeNormalBias = input.data3.w;

    output.probeViewBias = input.data4.x;
    output.probeNumRays = asint(input.data4.y);
    output.probeNumIrradianceInteriorTexels = asint(input.data4.z);
    output.probeNumDistanceInteriorTexels = asint(input.data4.w);

    output.probeIrradianceEncodingGamma = input.data5.x;
    output.probeIrradianceThreshold = input.data5.y;
    output.probeBrightnessThreshold = input.data5.z;
    output.probeRandomRayBackfaceThreshold = input.data5.w;

    output.probeDistanceExponent = input.data6.x;
    output.probeIrradianceFormat = asuint(input.data6.y);
    output.probeRayDataFormat = asuint(input.data6.z);
    output.probeRelocationEnabled = (asint(input.data6.w) != 0);

    output.probeClassificationEnabled = (asint(input.data7.x) != 0);
    output.probeVariabilityEnabled = (asint(input.data7.y) != 0);

    output.probeScrollOffsets = int3(input.data8.xyz);
    output.probeScrollDirections[0] = (asint(input.data9.x) != 0);
    output.probeScrollDirections[1] = (asint(input.data9.y) != 0);
    output.probeScrollDirections[2] = (asint(input.data9.z) != 0);
    output.probeScrollClear[0] = (asint(input.data10.x) != 0);
    output.probeScrollClear[1] = (asint(input.data10.y) != 0);
    output.probeScrollClear[2] = (asint(input.data10.z) != 0);

    output.probeFixedRayBackfaceThreshold = input.data11.x;
    output.probeMinFrontfaceDistance = input.data11.y;

    return output;
}

#endif // RTXGI_DDGI_VOLUME_DESC_GPU_H
