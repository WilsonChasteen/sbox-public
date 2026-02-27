#ifndef BRDF_HLSL
#define BRDF_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Disney BRDF (Bidirectional Reflectance Distribution Function)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Implementation of the Disney Principled BRDF model as described by Brent Burge.
// This model provides a physically-based shading framework with artist-friendly parameters.
//
// Key components:
// - Diffuse: Modified Lambert with energy conservation and retro-reflection
// - Subsurface: Approximation of subsurface scattering
// - Metallic: Blends between dielectric and conductor Fresnel
// - Specular: Microfacet GGX distribution with Smith visibility
// - Sheen: Fabric-like grazing angle reflection
// - Clearcoat: Additional clear coat layer with fixed IOR (1.5)
// - Anisotropic: Directional roughness for brushed surfaces
//
// Copyright Disney Enterprises, Inc. - Apache License 2.0
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// BRDF Lookup Texture (for legacy compatibility)
Texture2D BRDFLookup < Attribute("BRDFLookup"); > ;

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Constants
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
static const float BRDF_PI = 3.14159265358979323846;
static const float BRDF_INV_PI = 0.31830988618379067154;

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Utility Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Square function for cleaner code
float Sqr(float x)
{
    return x * x;
}

// Schlick Fresnel approximation
// u: cosine of angle between view/light direction and half vector
float SchlickFresnel(float u)
{
    float m = saturate(1.0 - u);
    float m2 = m * m;
    return m2 * m2 * m; // pow(m, 5) optimized
}

// Schlick Fresnel for RGB
float3 SchlickFresnelRGB(float3 F0, float u)
{
    return F0 + (1.0 - F0) * SchlickFresnel(u);
}

// Fresnel for diffuse - goes from 1 at normal incidence to 0.5 at grazing
float FresnelDiffuse(float NdotL, float NdotV, float LdotH, float roughness)
{
    float FL = SchlickFresnel(NdotL);
    float FV = SchlickFresnel(NdotV);
    float Fd90 = 0.5 + 2.0 * LdotH * LdotH * roughness;
    return lerp(1.0, Fd90, FL) * lerp(1.0, Fd90, FV);
}

// GTR1 - Generalized Trowbridge-Reitz for clearcoat (sharp lobe)
// NdotH: cosine between normal and half vector
// a: roughness parameter
float GTR1(float NdotH, float a)
{
    if (a >= 1.0)
        return BRDF_INV_PI;

    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NdotH * NdotH;
    return (a2 - 1.0) / (BRDF_PI * log(a2) * t);
}

// GTR2 - Generalized Trowbridge-Reitz for specular (standard lobe)
// NdotH: cosine between normal and half vector
// a: roughness parameter
float GTR2(float NdotH, float a)
{
    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NdotH * NdotH;
    return a2 / (BRDF_PI * t * t);
}

// GTR2 Anisotropic - for anisotropic surfaces
// NdotH: cosine between normal and half vector
// HdotX, HdotY: cosines between half vector and tangent/bitangent
// ax, ay: roughness in tangent and bitangent directions
float GTR2Aniso(float NdotH, float HdotX, float HdotY, float ax, float ay)
{
    return 1.0 / (BRDF_PI * ax * ay * Sqr(Sqr(HdotX / ax) + Sqr(HdotY / ay) + NdotH * NdotH));
}

// Smith GGX Geometry function (isotropic)
// NdotV: cosine between normal and view/light direction
// alphaG: roughness parameter
float SmithGGX(float NdotV, float alphaG)
{
    float a = alphaG * alphaG;
    float b = NdotV * NdotV;
    return 1.0 / (NdotV + sqrt(a + b - a * b));
}

// Smith GGX Geometry function (anisotropic)
// NdotV: cosine between normal and view/light direction
// VdotX, VdotY: cosines between view/light vector and tangent/bitangent
// ax, ay: roughness in tangent and bitangent directions
float SmithGGXAniso(float NdotV, float VdotX, float VdotY, float ax, float ay)
{
    return 1.0 / (NdotV + sqrt(Sqr(VdotX * ax) + Sqr(VdotY * ay) + Sqr(NdotV)));
}

// Subsurface scattering approximation
// Based on Hanrahan-Krueger BRDF approximation of isotropic BSSRDF
// 1.25 scale is used to (roughly) preserve albedo
float SubsurfaceScattering(float NdotL, float NdotV, float LdotH, float roughness)
{
    float Fss90 = LdotH * LdotH * roughness;
    float FL = SchlickFresnel(NdotL);
    float FV = SchlickFresnel(NdotV);
    float Fss = lerp(1.0, Fss90, FL) * lerp(1.0, Fss90, FV);
    return 1.25 * (Fss * (1.0 / (NdotL + NdotV) - 0.5) + 0.5);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Sample the BRDF lookup texture (legacy compatibility)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
float4 SampleBRDF(float2 vBRDFLookup)
{
    return BRDFLookup.SampleLevel(g_sTrilinearClamp, vBRDFLookup.xy, 0.0);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Disney BRDF Core Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Compute the full Disney BRDF
// Returns: reflected radiance (diffuse + specular + sheen + clearcoat)
//
// Parameters:
// - L: light direction (normalized, pointing towards light)
// - V: view direction (normalized, pointing towards camera)
// - N: surface normal (normalized)
// - X: tangent vector (normalized, for anisotropy)
// - Y: bitangent vector (normalized, for anisotropy)
// - baseColor: linear RGB base color (albedo)
// - metallic: 0 = dielectric, 1 = conductor
// - subsurface: 0 = no subsurface, 1 = full subsurface
// - specular: specular intensity (0-1, default 0.5)
// - roughness: surface roughness (0-1)
// - specularTint: 0 = achromatic specular, 1 = tinted by base color
// - anisotropic: 0 = isotropic, 1 = fully anisotropic
// - sheen: sheen intensity (0-1)
// - sheenTint: 0 = white sheen, 1 = tinted by base color
// - clearcoat: clearcoat intensity (0-1)
// - clearcoatGloss: clearcoat glossiness (0-1, default 1)
float3 DisneyBRDF(
    float3 L, float3 V, float3 N, float3 X, float3 Y,
    float3 baseColor,
    float metallic,
    float subsurface,
    float specular,
    float roughness,
    float specularTint,
    float anisotropic,
    float sheen,
    float sheenTint,
    float clearcoat,
    float clearcoatGloss)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    // Early exit for back-facing surfaces
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);

    // Compute half vector
    float3 H = normalize(L + V);
    float NdotH = dot(N, H);
    float LdotH = dot(L, H);

    // Linearize base color (assume sRGB input)
    float3 Cdlin = baseColor * baseColor; // Simple gamma ~2.2 approximation
    
    // Compute luminance and chroma
    float Cdlum = 0.3 * Cdlin.r + 0.6 * Cdlin.g + 0.1 * Cdlin.b;
    float3 Ctint = Cdlum > 0.0 ? Cdlin / Cdlum : float3(1.0, 1.0, 1.0);
    
    // Compute F0 (specular color at normal incidence)
    // Dielectrics: ~0.04 (IOR ~1.5), Metals: tinted by base color
    float3 Cspec0 = lerp(specular * 0.08 * lerp(float3(1.0, 1.0, 1.0), Ctint, specularTint), Cdlin, metallic);
    
    // Compute sheen color
    float3 Csheen = lerp(float3(1.0, 1.0, 1.0), Ctint, sheenTint);

    // -------------------------------------------------------------------------
    // Diffuse component (with subsurface approximation)
    // -------------------------------------------------------------------------
    float Fd = FresnelDiffuse(NdotL, NdotV, LdotH, roughness);
    float ss = SubsurfaceScattering(NdotL, NdotV, LdotH, roughness);
    float3 diffuseTerm = (BRDF_INV_PI * lerp(Fd, ss, subsurface) * Cdlin) * (1.0 - metallic);

    // -------------------------------------------------------------------------
    // Specular component (GGX microfacet)
    // -------------------------------------------------------------------------
    float aspect = sqrt(1.0 - anisotropic * 0.9);
    float ax = max(0.001, Sqr(roughness) / aspect);
    float ay = max(0.001, Sqr(roughness) * aspect);
    
    float Ds = GTR2Aniso(NdotH, dot(H, X), dot(H, Y), ax, ay);
    float3 Fs = SchlickFresnelRGB(Cspec0, LdotH);
    float Gs = SmithGGXAniso(NdotL, dot(L, X), dot(L, Y), ax, ay) *
               SmithGGXAniso(NdotV, dot(V, X), dot(V, Y), ax, ay);
    
    float3 specularTerm = Gs * Fs * Ds;

    // -------------------------------------------------------------------------
    // Sheen component (fabric-like grazing angle reflection)
    // -------------------------------------------------------------------------
    float3 Fsheen = SchlickFresnel(LdotH) * sheen * Csheen;
    float3 sheenTerm = Fsheen * (1.0 - metallic);

    // -------------------------------------------------------------------------
    // Clearcoat component (additional sharp specular layer, IOR = 1.5 -> F0 = 0.04)
    // -------------------------------------------------------------------------
    float Dr = GTR1(NdotH, lerp(0.1, 0.001, clearcoatGloss));
    float3 Fr = SchlickFresnelRGB(float3(0.04, 0.04, 0.04), LdotH);
    float Gr = SmithGGX(NdotL, 0.25) * SmithGGX(NdotV, 0.25);
    
    float3 clearcoatTerm = 0.25 * clearcoat * Gr * Fr * Dr;

    // Combine all components
    return diffuseTerm + sheenTerm + specularTerm + clearcoatTerm;
}

// Simplified Disney BRDF for common use cases (isotropic, no clearcoat/sheen)
float3 DisneyBRDFSimplified(
    float3 L, float3 V, float3 N,
    float3 baseColor,
    float metallic,
    float roughness,
    float specular)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    
    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);

    float3 H = normalize(L + V);
    float NdotH = dot(N, H);
    float LdotH = dot(L, H);

    // Linearize base color
    float3 Cdlin = baseColor * baseColor;
    float Cdlum = 0.3 * Cdlin.r + 0.6 * Cdlin.g + 0.1 * Cdlin.b;
    float3 Ctint = Cdlum > 0.0 ? Cdlin / Cdlum : float3(1.0, 1.0, 1.0);
    
    // F0
    float3 Cspec0 = lerp(specular * 0.08, Cdlin, metallic);

    // Diffuse
    float Fd = FresnelDiffuse(NdotL, NdotV, LdotH, roughness);
    float3 diffuseTerm = (BRDF_INV_PI * Fd * Cdlin) * (1.0 - metallic);

    // Specular (isotropic GGX)
    float a = Sqr(roughness);
    float Ds = GTR2(NdotH, a);
    float3 Fs = SchlickFresnelRGB(Cspec0, LdotH);
    float Gs = SmithGGX(NdotL, a) * SmithGGX(NdotV, a);
    
    float3 specularTerm = Gs * Fs * Ds;

    return diffuseTerm + specularTerm;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Legacy GGX BRDF Functions (for compatibility)
// Updated to use Disney BRDF model internally
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Compute the GGX BRDF using Disney's GTR2 distribution
// NOTE: Returns D * PI / G (combined D and Smith G terms).
float2 ComputeGGXBRDF(float2 vRoughness, float flNdotL, float flNdotV, float flNdotH, float2 vPositionSs)
{
    // Disney uses perceptual roughness squared (alpha = roughness^2)
    float2 alpha = vRoughness.xy * vRoughness.xy;
    
    // GTR2 distribution (Disney's microfacet model)
    // D = alpha^2 / (pi * ((NdotH^2 * (alpha^2 - 1) + 1)^2))
    // We return D * PI, so we omit the PI denominator
    float2 t = 1.0 + (alpha * alpha - 1.0) * flNdotH * flNdotH;
    float2 D = (alpha * alpha) / (t * t);
    
    // Smith GGX visibility function (separable form)
    // G = 1 / ((NdotL + NdotV) * alpha^2 + (NdotL + NdotV) - (NdotL + NdotV) * alpha^2)
    // Simplified Schlick-Smith form used by Disney
    float2 a = alpha * alpha;
    float2 b = float2(flNdotL * flNdotL, flNdotV * flNdotV);
    float2 G_L = 1.0 / (flNdotL.xx + sqrt(a + b - a * b));
    b = float2(flNdotV * flNdotV, flNdotV * flNdotV);
    float2 G_V = 1.0 / (flNdotV.xx + sqrt(a + b - a * b));
    
    return D * G_L * G_V;
}

// Compute the GGX Anisotropic BRDF using Disney's anisotropic GTR2
// NOTE: Returns D * PI / G (combined D and Smith G terms).
float ComputeGGXAnisoBRDF(float2 vRoughness, float flNdotL, float flNdotV, float flNdotH, float flXdotH, float flYdotH, float flVdotH, float2 vPositionSs)
{
    // Disney anisotropic roughness conversion
    float aspect = sqrt(1.0 - 0.9); // Default anisotropy factor
    float ax = max(0.001, vRoughness.x * vRoughness.x / aspect);
    float ay = max(0.001, vRoughness.y * vRoughness.y * aspect);

    // GTR2 Anisotropic distribution (Disney)
    float D = 1.0 / (BRDF_PI * ax * ay * Sqr(Sqr(flXdotH / ax) + Sqr(flYdotH / ay) + flNdotH * flNdotH));
    
    // Smith GGX Anisotropic visibility
    float G_L = SmithGGXAniso(flNdotL, flXdotH, flYdotH, ax, ay);
    float G_V = SmithGGXAniso(flNdotV, flXdotH, flYdotH, ax, ay);
    
    return D * G_L * G_V;
}

// Compute the Charlie Sheen BRDF using Disney's sheen model
// Uses Schlick Fresnel for fabric-like grazing angle reflection
float ComputeCharlieSheenBRDF(float flRoughness, float flNdotL, float flNdotV, float flNdotH)
{
    // Disney sheen uses Schlick Fresnel with energy compensation
    float FL = SchlickFresnel(flNdotL);
    float FV = SchlickFresnel(flNdotV);
    
    // Sheen Fresnel term - goes to 1 at grazing angles
    float Fsheen = SchlickFresnel(flNdotH);
    
    // Diffuse-like term with retro-reflection based on roughness
    float Fd90 = 0.5 + 2.0 * flNdotH * flNdotH * flRoughness;
    float Fd = lerp(1.0, Fd90, FL) * lerp(1.0, Fd90, FV);

    // Combine sheen and diffuse terms (energy conserving)
    return lerp(Fd, Fsheen, flRoughness) * BRDF_PI;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// BRDF Reflection Factor (legacy compatibility)
// Updated to use Disney Fresnel model
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
float3 CalcBRDFReflectionFactor(float flNDotV, float flRoughness, float3 vSpecularColor)
{
    // Disney uses Schlick Fresnel with roughness-dependent energy compensation
    float FV = SchlickFresnel(flNDotV);
    
    // Roughness affects the Fresnel response - rougher surfaces have more uniform reflection
    float roughnessFactor = lerp(1.0, 0.5, flRoughness);
    
    // Disney-style Fresnel: F = F0 + (1 - F0) * (1 - NdotV)^5
    // With energy compensation term
    float3 F = vSpecularColor + (1.0 - vSpecularColor) * FV * roughnessFactor;
    
    // Add energy compensation for rough surfaces (Disney approach)
    float energyCompensation = lerp(1.0, 0.0, flRoughness * flRoughness);
    
    return F * energyCompensation;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Roughness Utilities
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Convert anisotropic roughness to isotropic roughness
float IsotropicRoughnessFromAnisotropicRoughness(float2 vRoughness)
{
    float flRoughness = dot(vRoughness, float2(0.5f, 0.5f));
    return flRoughness;
}

// Calculate the geometric roughness factor
float CalculateGeometricRoughnessFactor(float3 vGeometricNormalWs)
{
    float3 vNormalWsDdx = ddx(vGeometricNormalWs.xyz);
    float3 vNormalWsDdy = ddy(vGeometricNormalWs.xyz);
    float flGeometricRoughnessFactor = pow(saturate(max(dot(vNormalWsDdx.xyz, vNormalWsDdx.xyz), dot(vNormalWsDdy.xyz, vNormalWsDdy.xyz))), 0.333);
    return flGeometricRoughnessFactor;
}

// Adjust roughness by geometric normal
float2 AdjustRoughnessByGeometricNormal(float2 vRoughness, float3 vGeometricNormalWs)
{
    float flGeometricRoughnessFactor = CalculateGeometricRoughnessFactor(vGeometricNormalWs.xyz);
    vRoughness.xy = max(vRoughness.xy, flGeometricRoughnessFactor.xx);
    return vRoughness.xy;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Disney BRDF Helper Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Convert roughness to perceptual roughness (0-1 scale)
float PerceptualToLinearRoughness(float perceptualRoughness)
{
    return perceptualRoughness * perceptualRoughness;
}

// Convert linear roughness to perceptual roughness
float LinearToPerceptualRoughness(float linearRoughness)
{
    return sqrt(linearRoughness);
}

// Compute F0 from IOR (for dielectrics)
float3 ComputeF0FromIOR(float ior)
{
    float n = ior * ior;
    return float3(n, n, n) * ((1.0 - ior) / (1.0 + ior)) * ((1.0 - ior) / (1.0 + ior));
}

// Standard dielectric F0 (IOR = 1.5)
float3 GetDielectricF0()
{
    return float3(0.04, 0.04, 0.04);
}

#endif /* BRDF_HLSL */
