#ifndef BRDF_EXTENDED_HLSL
#define BRDF_EXTENDED_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Extended BRDF Models
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Advanced BRDF models for specialized materials
// Includes: Hair, Skin, Fabric, Layered materials, Anisotropic surfaces
//
// These models extend the base Disney BRDF with physically-accurate
// specializations for specific material types.
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "common/BRDF.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Hair BRDF Models
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Based on Marschner et al. and d'Eon et al. hair shading models
// Hair shading uses cylindrical coordinates with longitudinal and azimuthal components

struct HairBRDFParams
{
    float3 sigma_a;       // Absorption coefficient (RGB)
    float3 sigma_s;       // Scattering coefficient (RGB)
    float roughness_longitudinal; // Along the hair strand
    float roughness_azimuthal;    // Around the hair strand
    float tilt_angle;     // Cuticle tilt angle (radians)
    float specular_weight; // Primary highlight weight
    float secondary_weight; // Secondary highlight weight
    float transmission_weight; // Transmission highlight weight
};

// Default hair parameters for common hair colors
HairBRDFParams GetHairParams(int hairColor)
{
    // hairColor: 0=Black, 1=Brown, 2=Blonde, 3=Red, 4=White
    if (hairColor == 0) // Black
        return HairBRDFParams(float3(0.8, 0.6, 0.5), float3(0.8, 0.6, 0.5), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
    else if (hairColor == 1) // Brown
        return HairBRDFParams(float3(0.6, 0.4, 0.3), float3(0.6, 0.4, 0.3), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
    else if (hairColor == 2) // Blonde
        return HairBRDFParams(float3(0.3, 0.2, 0.1), float3(0.3, 0.2, 0.1), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
    else if (hairColor == 3) // Red
        return HairBRDFParams(float3(0.7, 0.2, 0.1), float3(0.7, 0.2, 0.1), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
    else if (hairColor == 4) // White
        return HairBRDFParams(float3(0.1, 0.1, 0.1), float3(0.1, 0.1, 0.1), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
    
    // Default to brown
    return HairBRDFParams(float3(0.6, 0.4, 0.3), float3(0.6, 0.4, 0.3), 0.25, 0.5, 0.0, 0.8, 0.3, 0.1);
}

// Convert hair direction to tangent frame
void HairTangentFrame(float3 hairDir, float3 normal, out float3 tangent, out float3 bitangent)
{
    tangent = normalize(hairDir - normal * dot(hairDir, normal));
    bitangent = cross(normal, tangent);
}

// Marschner hair BRDF - Primary reflection (R)
// Light reflects off the surface of the hair
float3 HairBRDF_Primary(float3 L, float3 V, float3 normal, float3 tangent, HairBRDFParams params)
{
    float3 H = normalize(L + V);
    
    // Longitudinal and azimuthal components
    float cosThetaH = dot(H, normal);
    float sinThetaH = sqrt(1.0 - cosThetaH * cosThetaH);
    
    // NDF for hair (Gaussian in longitudinal direction)
    float alpha = params.roughness_longitudinal;
    float ndf = exp(-0.5 * Sqr(cosThetaH / alpha)) / (sqrt(2.0 * BRDF_PI) * alpha);
    
    // Fresnel for primary reflection
    float F = SchlickFresnel(sinThetaH);
    
    // Geometry term (simplified)
    float G = 1.0;
    
    // Attenuation due to absorption
    float3 A = exp(-params.sigma_a);
    
    return params.specular_weight * F * ndf * G * A;
}

// Marschner hair BRDF - Secondary reflection (TRT)
// Light enters, reflects internally, and exits
float3 HairBRDF_Secondary(float3 L, float3 V, float3 normal, float3 tangent, HairBRDFParams params)
{
    float3 H = normalize(L + V);
    
    float cosThetaH = dot(H, normal);
    float alpha = params.roughness_longitudinal;
    float ndf = exp(-0.5 * Sqr(cosThetaH / alpha)) / (sqrt(2.0 * BRDF_PI) * alpha);
    
    // Fresnel for transmission and internal reflection
    float F = SchlickFresnel(cosThetaH);
    float T = 1.0 - F;
    
    // Secondary = T * R_internal * T
    float3 secondary = T * T * T;
    
    // Absorption through hair
    float3 A = exp(-2.0 * params.sigma_a);
    
    return params.secondary_weight * secondary * ndf * A;
}

// Marschner hair BRDF - Transmission (TT)
// Light passes through the hair
float3 HairBRDF_Transmission(float3 L, float3 V, float3 normal, float3 tangent, HairBRDFParams params)
{
    float3 H = normalize(L + V);
    
    float cosThetaH = dot(H, normal);
    float alpha = params.roughness_longitudinal;
    float ndf = exp(-0.5 * Sqr(cosThetaH / alpha)) / (sqrt(2.0 * BRDF_PI) * alpha);
    
    // Transmission = T * T
    float F = SchlickFresnel(cosThetaH);
    float T = 1.0 - F;
    float3 transmission = T * T;
    
    // Absorption through hair
    float3 A = exp(-params.sigma_a);
    
    return params.transmission_weight * transmission * ndf * A;
}

// Full hair BRDF
float3 HairBRDF(float3 L, float3 V, float3 N, float3 hairDir, HairBRDFParams params)
{
    float3 tangent, bitangent;
    HairTangentFrame(hairDir, N, tangent, bitangent);
    
    float3 primary = HairBRDF_Primary(L, V, N, tangent, params);
    float3 secondary = HairBRDF_Secondary(L, V, N, tangent, params);
    float3 transmission = HairBRDF_Transmission(L, V, N, tangent, params);
    
    return primary + secondary + transmission;
}

// Simplified anisotropic hair shader (faster)
float3 HairBRDFSimplified(float3 L, float3 V, float3 N, float3 hairDir, float3 baseColor, float roughness)
{
    float3 H = normalize(L + V);
    
    // Anisotropic NDF
    float3 T = normalize(hairDir - N * dot(hairDir, N));
    float HdotT = dot(H, T);
    float HdotN = dot(H, N);
    
    float alpha = roughness * roughness;
    float ndf = 1.0 / (BRDF_PI * alpha * Sqr(Sqr(HdotT / alpha) + Sqr(HdotN)));
    
    // Fresnel
    float3 F0 = float3(0.04, 0.04, 0.04);
    float3 F = SchlickFresnelRGB(F0, dot(H, V));
    
    // Tint by hair color
    return ndf * F * baseColor;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Skin BRDF Models
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Specialized subsurface scattering for realistic skin rendering

struct SkinBRDFParams
{
    float3 epidermis_albedo;    // Outer layer color
    float3 dermis_albedo;       // Inner layer color
    float epidermis_thickness;  // Thickness of epidermis
    float scattering_strength;  // SSS strength
    float specular_weight;      // Surface specular
    float roughness;            // Surface roughness
};

// Default skin parameters for different skin tones
SkinBRDFParams GetSkinParams(int skinType)
{
    // skinType: 0=Fair, 1=Medium, 2=Dark, 3=Asian, 4=African
    if (skinType == 0) // Fair
        return SkinBRDFParams(float3(0.64, 0.50, 0.45), float3(0.85, 0.60, 0.55), 0.1, 0.7, 0.5, 0.4);
    else if (skinType == 1) // Medium
        return SkinBRDFParams(float3(0.55, 0.42, 0.35), float3(0.75, 0.52, 0.45), 0.12, 0.7, 0.5, 0.4);
    else if (skinType == 2) // Dark
        return SkinBRDFParams(float3(0.35, 0.28, 0.22), float3(0.55, 0.40, 0.35), 0.15, 0.7, 0.5, 0.4);
    else if (skinType == 3) // Asian
        return SkinBRDFParams(float3(0.60, 0.48, 0.40), float3(0.80, 0.58, 0.50), 0.11, 0.7, 0.5, 0.4);
    else if (skinType == 4) // African
        return SkinBRDFParams(float3(0.30, 0.24, 0.18), float3(0.50, 0.36, 0.30), 0.16, 0.7, 0.5, 0.4);
    
    // Default to medium
    return SkinBRDFParams(float3(0.55, 0.42, 0.35), float3(0.75, 0.52, 0.45), 0.12, 0.7, 0.5, 0.4);
}

// Epidermis layer (surface scattering + specular)
float3 SkinBRDF_Epidermis(float NdotL, float NdotV, float LdotH, SkinBRDFParams params)
{
    // Surface specular
    float3 F0 = float3(0.04, 0.04, 0.04);
    float3 F = SchlickFresnelRGB(F0, LdotH);
    float D = GTR2(NdotH, params.roughness * params.roughness);
    float G = SmithGGX(NdotL, params.roughness) * SmithGGX(NdotV, params.roughness);
    
    float3 specular = F * D * G * params.specular_weight;
    
    // Subsurface from epidermis
    float sss = SubsurfaceScattering(NdotL, NdotV, LdotH, params.roughness);
    float3 diffuse = params.epidermis_albedo * sss * (1.0 - params.specular_weight);
    
    return specular + diffuse;
}

// Full skin BRDF with multi-layer scattering
float3 SkinBRDF(float3 L, float3 V, float3 N, SkinBRDFParams params)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);
    
    float3 H = normalize(L + V);
    float NdotH = dot(N, H);
    float LdotH = dot(L, H);
    
    // Epidermis layer
    float3 epidermis = SkinBRDF_Epidermis(NdotL, NdotV, LdotH, params);
    
    // Dermis layer (deeper scattering)
    float sssDeep = SubsurfaceScatteringThickness(NdotL, NdotV, LdotH, params.roughness, 
                                                   params.epidermis_thickness, 0.5);
    float3 dermis = params.dermis_albedo * sssDeep * params.scattering_strength;
    
    return epidermis + dermis;
}

// Simplified skin shader (faster, good for real-time)
float3 SkinBRDFSimplified(float3 L, float3 V, float3 N, float3 baseColor, float roughness, float sssStrength)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);
    
    float3 H = normalize(L + V);
    float NdotH = dot(N, H);
    float LdotH = dot(L, H);
    
    // Surface specular (skin has weak specular)
    float3 F0 = float3(0.04, 0.04, 0.04);
    float3 F = SchlickFresnelRGB(F0, LdotH);
    float a = roughness * roughness;
    float D = GTR2(NdotH, a);
    float G = SmithGGX(NdotL, a) * SmithGGX(NdotV, a);
    float3 specular = F * D * G * 0.5;
    
    // Subsurface diffusion
    float sss = SubsurfaceScattering(NdotL, NdotV, LdotH, roughness);
    float3 diffuse = baseColor * sss * sssStrength;
    
    return diffuse + specular;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Fabric BRDF Models
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Specialized shading for cloth, velvet, and woven materials

struct FabricBRDFParams
{
    float3 base_color;
    float roughness;
    float sheen_intensity;
    float3 sheen_color;
    float anisotropy;       // Directionality of fibers
    float fiber_direction;  // Fiber orientation angle
};

// Velvet BRDF - soft grazing angle highlights
float3 FabricBRDF_Velvet(float NdotL, float NdotV, float LdotH, FabricBRDFParams params)
{
    // Diffuse with retro-reflection (Ashikhmin model)
    float diffuse = NdotL / (NdotL + NdotV + BRDF_EPSILON);
    
    // Sheen term (brighter at grazing angles)
    float sheen = SchlickFresnel(LdotH);
    float3 sheenTerm = params.sheen_color * params.sheen_intensity * sheen;
    
    return (params.base_color * diffuse + sheenTerm) * BRDF_INV_PI;
}

// Silk BRDF - anisotropic highlights
float3 FabricBRDF_Silk(float3 L, float3 V, float3 N, float3 tangent, FabricBRDFParams params)
{
    float3 H = normalize(L + V);
    
    // Anisotropic NDF
    float HdotT = dot(H, tangent);
    float HdotN = dot(H, N);
    
    float ax = params.roughness * (1.0 + params.anisotropy);
    float ay = params.roughness * (1.0 - params.anisotropy);
    ax = max(ax, 0.001);
    ay = max(ay, 0.001);
    
    float D = GTR2Aniso(HdotN, HdotT, dot(H, cross(N, tangent)), ax, ay);
    
    // Fresnel
    float3 F0 = float3(0.04, 0.04, 0.04);
    float3 F = SchlickFresnelRGB(F0, dot(H, V));
    
    return D * F * params.base_color;
}

// Full fabric BRDF
float3 FabricBRDF(float3 L, float3 V, float3 N, float3 tangent, FabricBRDFParams params)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);
    
    float3 H = normalize(L + V);
    float LdotH = dot(L, H);
    
    // Blend between velvet and silk based on roughness
    float velvetWeight = smoothstep(0.5, 1.0, params.roughness);
    
    float3 velvet = FabricBRDF_Velvet(NdotL, NdotV, LdotH, params);
    float3 silk = FabricBRDF_Silk(L, V, N, tangent, params);
    
    return lerp(silk, velvet, velvetWeight);
}

// Simplified cloth shader
float3 ClothBRDFSimplified(float3 L, float3 V, float3 N, float3 baseColor, float roughness, float sheen)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);
    
    float3 H = normalize(L + V);
    float LdotH = dot(L, H);
    
    // Diffuse
    float3 diffuse = baseColor * NdotL * BRDF_INV_PI;
    
    // Sheen (fabric Fresnel)
    float sheenTerm = SchlickFresnel(LdotH) * sheen;
    
    return diffuse + sheenTerm * baseColor;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Layered BRDF Models
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Stack multiple BRDF layers for complex materials (dirt on metal, paint on clearcoat, etc.)

struct LayeredBRDFLayer
{
    float3 albedo;
    float roughness;
    float metalness;
    float thickness;          // Layer thickness
    float3 absorption;        // Light absorption through layer
    float weight;             // Layer contribution weight
};

// Blend two BRDF layers with proper energy conservation
float3 LayeredBRDF_Blend(float3 L, float3 V, float3 N, float3 X, float3 Y,
                         LayeredBRDFLayer topLayer, LayeredBRDFLayer bottomLayer)
{
    // Top layer BRDF
    float3 topBRDF = DisneyBRDFEnhanced(L, V, N, X, Y,
                                        topLayer.albedo, topLayer.metalness, 0.0, 1.0,
                                        topLayer.roughness, false, 0.0, 0.0, 0.0,
                                        0.0, 1.0, 0.0, 1.0, float3(0,0,0), 0.0, 1.5, 1.5, false);
    
    // Bottom layer BRDF (attenuated by top layer)
    float3 bottomBRDF = DisneyBRDFEnhanced(L, V, N, X, Y,
                                           bottomLayer.albedo, bottomLayer.metalness, 0.0, 1.0,
                                           bottomLayer.roughness, false, 0.0, 0.0, 0.0,
                                           0.0, 1.0, 0.0, 1.0, float3(0,0,0), 0.0, 1.5, 1.5, false);
    
    // Attenuation through top layer
    float3 transmission = exp(-topLayer.absorption * topLayer.thickness);
    
    // Combine: top layer + (bottom layer * transmission^2)
    // (transmission squared for light going in and out)
    return topLayer.weight * topBRDF + bottomLayer.weight * bottomBRDF * transmission * transmission;
}

// Clearcoat over base material (common for car paint, varnished wood)
float3 LayeredBRDF_Clearcoat(float3 L, float3 V, float3 N, float3 X, float3 Y,
                             float3 baseAlbedo, float baseRoughness, float baseMetalness,
                             float coatWeight, float coatRoughness, float coatIOR)
{
    // Base material
    float3 baseBRDF = DisneyBRDFEnhanced(L, V, N, X, Y,
                                         baseAlbedo, baseMetalness, 0.0, 1.0,
                                         baseRoughness, false, 0.0, 0.0, 0.0,
                                         0.0, 1.0, 0.0, 1.0, float3(0,0,0), 0.0, 1.5, 1.5, false);
    
    // Clearcoat layer
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    float3 H = normalize(L + V);
    float NdotH = dot(N, H);
    
    float3 coatBRDF = ClearcoatEnhanced(NdotH, NdotL, NdotV, coatWeight, 1.0 - coatRoughness, coatIOR);
    
    // Clearcoat Fresnel attenuation for base layer
    float coatF0 = GetDielectricF0Value(coatIOR);
    float coatFresnel = coatF0 + (1.0 - coatF0) * SchlickFresnel(NdotH);
    
    return baseBRDF * (1.0 - coatFresnel) * (1.0 - coatWeight) + coatBRDF;
}

// Dust/dirt layer on surface
float3 LayeredBRDF_Dust(float3 L, float3 V, float3 N, float3 X, float3 Y,
                        float3 cleanAlbedo, float cleanRoughness,
                        float3 dustAlbedo, float dustRoughness, float dustAmount)
{
    LayeredBRDFLayer cleanLayer;
    cleanLayer.albedo = cleanAlbedo;
    cleanLayer.roughness = cleanRoughness;
    cleanLayer.metalness = 0.0;
    cleanLayer.thickness = 1.0;
    cleanLayer.absorption = float3(0.1, 0.1, 0.1);
    cleanLayer.weight = 1.0 - dustAmount;
    
    LayeredBRDFLayer dustLayer;
    dustLayer.albedo = dustAlbedo;
    dustLayer.roughness = dustRoughness;
    dustLayer.metalness = 0.0;
    dustLayer.thickness = 0.1;
    dustLayer.absorption = float3(0.5, 0.5, 0.5);
    dustLayer.weight = dustAmount;
    
    return LayeredBRDF_Blend(L, V, N, X, Y, dustLayer, cleanLayer);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Anisotropic BRDF Utilities
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Create tangent frame from anisotropy direction
float3 CreateAnisotropicTangent(float3 normal, float3 direction)
{
    float3 tangent = normalize(direction - normal * dot(direction, normal));
    return tangent;
}

// Rotate tangent frame by angle (for anisotropy rotation)
void RotateTangentFrame(float3 normal, float3 tangent, float angle, out float3 newTangent, out float3 newBitangent)
{
    float c = cos(angle);
    float s = sin(angle);
    float3 bitangent = cross(normal, tangent);
    newTangent = tangent * c + bitangent * s;
    newBitangent = cross(normal, newTangent);
}

// Anisotropic roughness from surface direction
float2 AnisotropicRoughness(float isotropicRoughness, float anisotropy, float direction)
{
    float aspect = sqrt(1.0 - anisotropy * 0.9);
    float ax = isotropicRoughness / aspect;
    float ay = isotropicRoughness * aspect;
    return float2(ax, ay);
}

#endif /* BRDF_EXTENDED_HLSL */
