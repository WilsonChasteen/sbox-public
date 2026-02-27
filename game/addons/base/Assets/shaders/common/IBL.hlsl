#ifndef IBL_HLSL
#define IBL_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Image-Based Lighting (IBL) for Disney BRDF
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Provides environment map sampling with proper BRDF integration
// Includes: Prefiltered environment maps, BRDF LUT, diffuse irradiance
//
// Based on "Real Shading in Unreal Engine 4" (Epic Games, 2013)
// and "Physically Based Rendering in Filament" (Google, 2018)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "BRDF.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// BRDF LUT (Look-Up Table) Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Split-sum approximation for specular IBL
// Pre-integrates the BRDF into a 2D texture lookup

// Compute BRDF LUT value analytically (for pre-computation or runtime)
// Returns: scale and bias for specular environment map sampling
float2 ComputeBRDFLUT(float NdotV, float roughness)
{
    float VdotN = NdotV;
    
    // Epic's split-sum approximation
    float r = roughness;
    float a = r * r;
    
    float A = 0.0;
    float B = 0.0;
    float C = 0.0;
    
    // Numerical integration (simplified Gaussian quadrature)
    const int SAMPLES = 1024;
    const float INV_SAMPLES = 1.0 / float(SAMPLES);
    
    float lambdaV = 0.0;
    
    for (int i = 0; i < SAMPLES; i++)
    {
        float xi = (float(i) + 0.5) * INV_SAMPLES;
        
        // Sample hemisphere
        float r1 = sqrt(1.0 - xi);
        float r2 = 2.0 * BRDF_PI * (float(i) + 0.5);
        
        float Hx = sqrt(1.0 - r1 * r1) * cos(r2);
        float Hy = sqrt(1.0 - r1 * r1) * sin(r2);
        float Hz = r1;
        
        float3 H = float3(Hx, Hy, Hz);
        float3 V = float3(0.0, sqrt(1.0 - VdotN * VdotN), VdotN);
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        
        if (L.z > 0.0)
        {
            float NdotL = L.z;
            float NdotH = H.z;
            float VdotH = dot(V, H);
            
            // GGX distribution
            float D = a * a / (BRDF_PI * pow((NdotH * NdotH) * (a * a - 1.0) + 1.0, 2.0));
            
            // Smith visibility
            float lambdaL = (-1.0 + sqrt(1.0 + a * a * (1.0 - NdotL * NdotL) / (NdotL * NdotL))) * 0.5;
            lambdaV = (-1.0 + sqrt(1.0 + a * a * (1.0 - VdotN * VdotN) / (VdotN * VdotN))) * 0.5;
            float G = 1.0 / ((1.0 + lambdaV + lambdaL) * 4.0);
            
            // Fresnel
            float F = SchlickFresnel(VdotH);
            
            A += NdotL * D * G * F;
            B += NdotL * D * G * (1.0 - F);
            C += NdotL;
        }
    }
    
    float scale = A * INV_SAMPLES * BRDF_PI * 4.0;
    float bias = B * INV_SAMPLES * BRDF_PI * 4.0;
    
    return float2(scale, bias);
}

// Simplified BRDF LUT approximation (faster, good quality)
float2 ComputeBRDFLUTApprox(float NdotV, float roughness)
{
    float r = roughness;
    
    // Schlick Fresnel approximation
    float a = 1.0 - NdotV;
    float a2 = a * a;
    float a5 = a2 * a2 * a;
    
    // Fitted coefficients for GGX
    float c0 = 0.30346;
    float c1 = 0.70407;
    float c2 = 0.01920;
    float c3 = 0.09329;
    float c4 = 0.36598;
    float c5 = 0.03503;
    float c6 = 0.33135;
    float c7 = 0.77156;
    float c8 = 0.03125;
    float c9 = 0.90047;
    float c10 = 0.98372;
    float c11 = 0.21376;
    float c12 = 0.07090;
    
    float k = r * r / 2.0;
    
    float scale = 1.0 / (1.0 + k * (1.0 / NdotV - 1.0));
    float bias = a5 * (1.0 - scale);
    
    // Correction terms
    scale = scale * (c0 + c1 * r + c2 * NdotV + c3 * r * NdotV);
    bias = bias * (c4 + c5 * r + c6 * NdotV + c7 * r * NdotV);
    
    return float2(scale, bias);
}

// Sample pre-computed BRDF LUT texture
// Assumes g_tBRDFLUT is a 2D texture with:
// - X axis: NdotV (0-1)
// - Y axis: roughness (0-1)
// - RG channels: scale, bias
Texture2D g_tBRDFLUT < Attribute("BRDFLUT"); > ;

float2 SampleBRDFLUT(float NdotV, float roughness)
{
    float2 uv = float2(NdotV, roughness);
    return g_tBRDFLUT.SampleLevel(g_sTrilinearClamp, uv, 0.0).rg;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Diffuse Irradiance
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Sample environment map for diffuse lighting (Lambertian)

// Sample irradiance from cubemap (low frequency, can be pre-filtered)
float3 SampleDiffuseIrradiance(float3 N, TextureCube envMap)
{
    float3 irradiance = float3(0.0, 0.0, 0.0);
    
    // Simple 6-tap cubemap sampling (can be improved with more taps)
    float3 up = float3(0.0, 1.0, 0.0);
    float3 right = cross(up, N);
    up = cross(N, right);
    
    float sampleDelta = 0.025;
    float nrSamples = 0.0;
    
    for (float phi = 0.0; phi < 2.0 * BRDF_PI; phi += sampleDelta)
    {
        for (float theta = 0.0; theta < 0.5 * BRDF_PI; theta += sampleDelta)
        {
            float3 tangentSample = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;
            
            irradiance += envMap.SampleLevel(g_sTrilinearClamp, sampleVec, 0.0).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    
    irradiance = BRDF_INV_PI * irradiance / nrSamples;
    
    return irradiance;
}

// Pre-filtered irradiance (faster, uses mipmapped cubemap)
float3 SampleDiffuseIrradiancePrefiltered(float3 N, TextureCube irradianceMap)
{
    return irradianceMap.SampleLevel(g_sTrilinearClamp, N, 0.0).rgb;
}

// Spherical harmonics irradiance (fastest, compact representation)
float3 SampleDiffuseIrradianceSH(float3 N, float3 shCoeffs[9])
{
    // SH basis functions
    float x = N.x;
    float y = N.y;
    float z = N.z;
    
    // Band 0
    float3 result = shCoeffs[0] * 0.886227;
    
    // Band 1
    result += shCoeffs[1] * 1.02333 * y;
    result += shCoeffs[2] * 1.02333 * z;
    result += shCoeffs[3] * 0.590817 * x;
    
    // Band 2
    result += shCoeffs[4] * 2.89061 * x * y;
    result += shCoeffs[5] * 2.89061 * y * z;
    result += shCoeffs[6] * (0.946174 * z * z - 0.315391);
    result += shCoeffs[7] * 2.89061 * x * z;
    result += shCoeffs[8] * 1.44531 * (x * x - y * y);
    
    return result;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Specular IBL
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Sample pre-filtered environment map for specular reflections

// Sample specular environment map with roughness-based mip level
float3 SampleSpecularIBL(float3 R, float roughness, float NdotV, TextureCube prefilteredMap)
{
    // Roughness to mip level conversion
    // Higher roughness = blurrier reflection = higher mip level
    float mipLevel = roughness * 7.0; // Assuming 8 mip levels (0-7)
    
    return prefilteredMap.SampleLevel(g_sTrilinearClamp, R, mipLevel).rgb;
}

// Full specular IBL with BRDF LUT
float3 ComputeSpecularIBL(float3 R, float3 N, float3 V, float roughness, float3 F0, 
                          TextureCube prefilteredMap)
{
    float NdotV = max(dot(N, V), 0.0);
    
    // Sample pre-filtered environment map
    float3 specularColor = SampleSpecularIBL(R, roughness, NdotV, prefilteredMap);
    
    // Sample BRDF LUT
    float2 brdf = SampleBRDFLUTApprox(NdotV, roughness);
    
    // Apply Fresnel
    float3 F = F0 + (float3(1.0, 1.0, 1.0) - F0) * SchlickFresnel(NdotV);
    
    // Combine
    float3 specular = specularColor * (F * brdf.x + brdf.y);
    
    return specular;
}

// Specular IBL with energy compensation for rough surfaces
float3 ComputeSpecularIBLEnergyComp(float3 R, float3 N, float3 V, float roughness, float3 F0,
                                    TextureCube prefilteredMap)
{
    float3 specular = ComputeSpecularIBL(R, N, V, roughness, F0, prefilteredMap);
    
    // Energy compensation for multi-scattering
    float3 Ed = float3(1.0, 1.0, 1.0) - F0;
    float3 Ems = 1.0 / (1.0 - roughness * roughness * Ed);
    float3 Favg = (F0.r + F0.g + F0.b) / 3.0;
    float3 Fms = F0 * Ems;
    
    specular += Fms * (1.0 - Favg);
    
    return specular;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Combined IBL
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Full image-based lighting with diffuse and specular

struct IBLResult
{
    float3 diffuse;
    float3 specular;
    float3 combined;
};

IBLResult ComputeIBL(float3 N, float3 V, float3 baseColor, float metallic, float roughness,
                     float3 F0, TextureCube irradianceMap, TextureCube prefilteredMap)
{
    IBLResult result;
    
    // Reflect vector
    float3 R = reflect(-V, N);
    
    // Diffuse irradiance
    result.diffuse = SampleDiffuseIrradiancePrefiltered(N, irradianceMap);
    
    // Specular IBL
    result.specular = ComputeSpecularIBL(R, N, V, roughness, F0, prefilteredMap);
    
    // Combine with material properties
    float3 kd = baseColor * (1.0 - metallic);
    result.diffuse *= kd;
    
    result.combined = result.diffuse + result.specular;
    
    return result;
}

// IBL with clearcoat layer
IBLResult ComputeIBLClearcoat(float3 N, float3 V, float3 baseColor, float metallic, float roughness,
                              float3 F0, float clearcoat, float clearcoatRoughness, float clearcoatIOR,
                              TextureCube irradianceMap, TextureCube prefilteredMap)
{
    IBLResult result = ComputeIBL(N, V, baseColor, metallic, roughness, F0, irradianceMap, prefilteredMap);
    
    // Clearcoat reflection
    float3 coatR = reflect(-V, N);
    float3 coatF0 = ComputeF0FromIOR(clearcoatIOR);
    float3 coatSpecular = ComputeSpecularIBL(coatR, N, V, clearcoatRoughness, coatF0, prefilteredMap);
    
    // Add clearcoat (attenuated by base specular)
    float3 F90 = float3(1.0, 1.0, 1.0);
    float NdotV = max(dot(N, V), 0.0);
    float coatFresnel = SchlickFresnel(NdotV);
    float3 coatBlend = coatF0 + (F90 - coatF0) * coatFresnel;
    
    result.specular += clearcoat * coatSpecular * coatBlend;
    result.combined = result.diffuse + result.specular;
    
    return result;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Prefiltering Functions (for offline/async prefiltering)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Importance sampling GGX for prefiltering
float3 SampleGGX(float2 xi, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    
    float phi = 2.0 * BRDF_PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a2 - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    
    float3 H;
    H.x = sinTheta * cos(phi);
    H.y = sinTheta * sin(phi);
    H.z = cosTheta;
    
    return H;
}

// PDF for GGX sampling
float PDF_GGX(float NdotH, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / (BRDF_PI * d * d);
}

// Prefilter environment map for specular IBL (compute shader would use this)
float3 PrefilterEnvMap(float3 R, float roughness, TextureCube envMap)
{
    float3 prefilteredColor = float3(0.0, 0.0, 0.0);
    float totalWeight = 0.0;
    
    const int SAMPLE_COUNT = 1024;
    
    for (int i = 0; i < SAMPLE_COUNT; i++)
    {
        // Generate sample
        float2 xi = float2((float(i) + 0.5) / SAMPLE_COUNT, (float(i) + 0.5) / SAMPLE_COUNT);
        float3 H = SampleGGX(xi, roughness);
        
        // Transform sample to world space
        float3 V = R;
        float3 L = normalize(2.0 * dot(V, H) * H - V);
        
        float NdotL = max(L.z, 0.0);
        if (NdotL > 0.0)
        {
            prefilteredColor += envMap.SampleLevel(g_sTrilinearClamp, L, 0.0).rgb * NdotL;
            totalWeight += NdotL;
        }
    }
    
    return prefilteredColor / totalWeight;
}

#endif /* IBL_HLSL */
