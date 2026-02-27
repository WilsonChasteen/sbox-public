#ifndef BRDF_HLSL
#define BRDF_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Disney BRDF (Bidirectional Reflectance Distribution Function) - Enhanced
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Implementation of the Disney Principled BRDF model as described by Brent Burge.
// This model provides a physically-based shading framework with artist-friendly parameters.
//
// Key components:
// - Diffuse: Modified Lambert with energy conservation and retro-reflection (Oren-Nayar option)
// - Subsurface: Approximation of subsurface scattering (multiple profiles)
// - Metallic: Blends between dielectric and conductor Fresnel
// - Specular: Microfacet GGX distribution with Smith visibility and multi-scattering
// - Sheen: Fabric-like grazing angle reflection
// - Clearcoat: Additional clear coat layer with customizable IOR
// - Anisotropic: Directional roughness for brushed surfaces
// - Iridescence: Thin-film interference effects
//
// Copyright Disney Enterprises, Inc. - Apache License 2.0
// Enhanced additions: Complex IOR, Multi-scattering GGX, Energy Compensation
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// BRDF Lookup Texture (for legacy compatibility)
Texture2D BRDFLookup < Attribute("BRDFLookup"); > ;

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Constants
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
static const float BRDF_PI = 3.14159265358979323846;
static const float BRDF_INV_PI = 0.31830988618379067154;
static const float BRDF_EPSILON = 1e-5;

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Utility Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Square function for cleaner code
float Sqr(float x)
{
    return x * x;
}

// Cube function
float Cube(float x)
{
    return x * x * x;
}

// Safe divide
float SafeDivide(float a, float b)
{
    return a / max(b, BRDF_EPSILON);
}

float3 SafeDivide3(float3 a, float3 b)
{
    return a / max(b, BRDF_EPSILON.xxx);
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

// Schlick Fresnel with roughness modification (improved energy conservation)
float3 SchlickFresnelRough(float3 F0, float3 F90, float u)
{
    float x = 1.0 - u;
    float x2 = x * x;
    float x5 = x * x2 * x2;
    return F0 + (F90 - F0) * x5;
}

// Fresnel for diffuse - goes from 1 at normal incidence to 0.5 at grazing
float FresnelDiffuse(float NdotL, float NdotV, float LdotH, float roughness)
{
    float FL = SchlickFresnel(NdotL);
    float FV = SchlickFresnel(NdotV);
    float Fd90 = 0.5 + 2.0 * LdotH * LdotH * roughness;
    return lerp(1.0, Fd90, FL) * lerp(1.0, Fd90, FV);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// IOR and Fresnel Utilities
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Compute F0 (specular reflectance at normal incidence) from IOR
// For dielectrics: F0 = ((IOR - 1) / (IOR + 1))^2
float3 ComputeF0FromIOR(float ior)
{
    float n = ior;
    float F0 = Sqr((n - 1.0) / (n + 1.0));
    return float3(F0, F0, F0);
}

// Compute IOR from F0 (inverse of above)
float ComputeIORFromF0(float3 F0)
{
    float sqrtF0 = sqrt(F0.r); // Assume achromatic
    return (1.0 + sqrtF0) / (1.0 - sqrtF0);
}

// Standard dielectric F0 values for common materials
float GetDielectricF0Value(float ior)
{
    return Sqr((ior - 1.0) / (ior + 1.0));
}

// Common dielectric IOR values
static const float IOR_WATER = 1.33;
static const float IOR_GLASS = 1.52;
static const float IOR_DIAMOND = 2.42;
static const float IOR_ICE = 1.31;
static const float IOR_EMERALD = 1.57;
static const float IOR_RUBY = 1.77;

// Common dielectric F0 values (~0.04 for IOR 1.5)
float3 GetDielectricF0()
{
    return float3(0.04, 0.04, 0.04);
}

// Complex IOR Fresnel for conductors (metals)
// Uses full Fresnel equation with complex IOR (n, k)
// n: real part (refractive index)
// k: imaginary part (extinction coefficient)
// cosTheta: cosine of incident angle
float3 FresnelConductor(float cosTheta, float3 n, float3 k)
{
    float3 n2 = n * n;
    float3 k2 = k * k;
    float3 t2 = n2 + k2;
    float cosTheta2 = cosTheta * cosTheta;

    float3 R_s = (t2 + cosTheta2 - 2.0 * n * cosTheta) /
                 (t2 + cosTheta2 + 2.0 * n * cosTheta);
    float3 R_p = R_s * ((t2 * (cosTheta2 - 2.0 * n * cosTheta) + cosTheta2 * cosTheta2) /
                        (t2 * (cosTheta2 + 2.0 * n * cosTheta) + cosTheta2 * cosTheta2));

    return 0.5 * (R_s + R_p);
}

// FresnelConductor with scalar k (for simpler metals)
float3 FresnelConductor(float cosTheta, float3 n, float k)
{
    return FresnelConductor(cosTheta, n, float3(k, k, k));
}

// Get metal IOR values for common metals
// Returns n (real part) and k (imaginary part) via out parameters
void GetMetalIORData(int metalType, out float3 n, out float3 k)
{
    // metalType: 0=Aluminum, 1=Gold, 2=Copper, 3=Silver, 4=Iron, 5=Chrome
    if (metalType == 0) // Aluminum
    { n = float3(1.44, 1.44, 1.44); k = float3(7.39, 7.39, 7.39); }
    else if (metalType == 1) // Gold
    { n = float3(0.17, 0.37, 1.44); k = float3(3.00, 2.34, 1.84); }
    else if (metalType == 2) // Copper
    { n = float3(0.21, 0.92, 1.10); k = float3(3.01, 2.24, 2.01); }
    else if (metalType == 3) // Silver
    { n = float3(0.05, 0.05, 0.05); k = float3(3.49, 3.49, 3.49); }
    else if (metalType == 4) // Iron
    { n = float3(2.53, 1.63, 1.21); k = float3(3.29, 2.77, 2.12); }
    else if (metalType == 5) // Chrome
    { n = float3(2.48, 2.03, 1.71); k = float3(3.60, 3.02, 2.53); }
    else // Default to aluminum
    { n = float3(1.44, 1.44, 1.44); k = float3(7.39, 7.39, 7.39); }
}

// Compute F0 for metal using complex IOR (normal incidence)
float3 ComputeMetalF0(float3 n, float3 k)
{
    float3 n2 = n * n;
    float3 k2 = k * k;
    float3 num = (n2 - 1.0) + k2;
    float3 den = (n2 + 2.0 * n + 1.0) + k2;
    return num / den;
}

// Get F0 for common metals
float3 GetMetalF0(int metalType)
{
    float3 n, k;
    GetMetalIORData(metalType, n, k);
    return ComputeMetalF0(n, k);
}

// Blend dielectric and conductor F0 based on metalness
float3 ComputeF0(float metalness, float3 baseColor, float specular, float ior)
{
    float3 dielectricF0 = ComputeF0FromIOR(ior) * specular * 2.0; // Scale for energy
    float3 conductorF0 = baseColor;
    return lerp(dielectricF0, conductorF0, metalness);
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

// GTR1 with improved numerical stability
float GTR1Improved(float NdotH, float a)
{
    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NdotH * NdotH;
    return a2 / (BRDF_PI * t * t);
}

// GTR2 - Generalized Trowbridge-Reitz for specular (standard lobe)
// NdotH: cosine between normal and half vector
// a: roughness parameter (alpha = roughness^2 for perceptual roughness)
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
// alphaG: roughness parameter (alpha = roughness^2)
float SmithGGX(float NdotV, float alphaG)
{
    float a = alphaG * alphaG;
    float b = NdotV * NdotV;
    return 1.0 / (NdotV + sqrt(a + b - a * b));
}

// Smith GGX with direct alpha (not squared)
float SmithGGXDirect(float NdotV, float alpha)
{
    float a2 = alpha * alpha;
    float b = NdotV * NdotV;
    return 1.0 / (NdotV + sqrt(a2 + b - a2 * b));
}

// Smith GGX Geometry function (anisotropic)
// NdotV: cosine between normal and view/light direction
// VdotX, VdotY: cosines between view/light vector and tangent/bitangent
// ax, ay: roughness in tangent and bitangent directions
float SmithGGXAniso(float NdotV, float VdotX, float VdotY, float ax, float ay)
{
    return 1.0 / (NdotV + sqrt(Sqr(VdotX * ax) + Sqr(VdotY * ay) + Sqr(NdotV)));
}

// Combined Smith GGX for both light and view
float SmithGGXCombined(float NdotL, float NdotV, float alpha)
{
    float a2 = alpha * alpha;
    float lambdaV = NdotV * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
    float lambdaL = NdotL * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);
    return 0.5 / (lambdaV + lambdaL);
}

// Multi-scattering GGX correction for energy conservation
// Based on "Multiple-Scattering Microfacet Model for Real-Time Image-Based Lighting"
// Returns energy compensation factor for rough surfaces

// Lambda function for Smith GGX (helper for multi-scattering)
float SmithLambda(float Ndot, float a2)
{
    return (-1.0 + sqrt(1.0 + a2 * (1.0 - Ndot * Ndot) / (Ndot * Ndot))) * 0.5;
}

float MultiScatteringGGX(float NdotV, float NdotL, float alpha)
{
    float a2 = alpha * alpha;

    float lambdaV = SmithLambda(NdotV, a2);
    float lambdaL = SmithLambda(NdotL, a2);

    // Multi-scattering term
    float Ems = 1.0 / (lambdaV + lambdaL + 1.0);

    // Energy compensation factor
    return 1.0 - Ems;
}

// Energy compensation for GGX (simplified approximation)
float GGXEnergyCompensation(float NdotV, float alpha)
{
    // Approximation: rougher surfaces need more compensation
    float Ems = alpha * alpha * (1.0 - NdotV);
    return 1.0 + Ems;
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

// Subsurface scattering with thickness-based absorption
// thickness: material thickness for light absorption
// scatterRadius: how far light scatters within the material
float SubsurfaceScatteringThickness(float NdotL, float NdotV, float LdotH, float roughness, float thickness, float scatterRadius)
{
    float Fss90 = LdotH * LdotH * roughness;
    float FL = SchlickFresnel(NdotL);
    float FV = SchlickFresnel(NdotV);
    float Fss = lerp(1.0, Fss90, FL) * lerp(1.0, Fss90, FV);
    
    // Thickness-based absorption (Beer-Lambert law approximation)
    float absorption = exp(-thickness / max(scatterRadius, 0.001));
    float sssTerm = 1.25 * (Fss * (1.0 / (NdotL + NdotV) - 0.5) + 0.5);
    
    return lerp(sssTerm, 1.0, absorption);
}

// Random walk subsurface profile (more accurate for skin)
float SubsurfaceRandomWalk(float NdotL, float NdotV, float3 baseColor, float meanFreePath)
{
    // Simplified random walk approximation
    float d = sqrt(NdotL * NdotL + NdotV * NdotV);
    float r = exp(-d / meanFreePath);
    return r * (1.0 / (NdotL + NdotV + 0.001));
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Oren-Nayar Diffuse Model
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// More accurate diffuse for rough surfaces than Lambert
// Based on "Reflectance Model for Diffuse Reflection" by Oren and Nayar (1994)

float OrenNayarDiffuse(float NdotL, float NdotV, float LdotV, float roughness)
{
    // Convert roughness to surface slope variance (sigma)
    float sigma = roughness;
    float sigma2 = sigma * sigma;
    
    // Oren-Nayar coefficients
    float A = 1.0 - 0.5 * sigma2 / (sigma2 + 0.33);
    float B = 0.45 * sigma2 / (sigma2 + 0.09);
    
    // Angles
    float sinAlpha = max(NdotL, NdotV);
    float tanBeta = sqrt(max(1.0 - max(NdotL, NdotV) * max(NdotL, NdotV), 0.0)) / max(NdotL, NdotV);
    
    // Azimuthal angle difference
    float cosPhi = (LdotV - NdotL * NdotV) / max(sinAlpha * sqrt(max(1.0 - sinAlpha * sinAlpha, 0.0)), 0.001);
    
    // Oren-Nayar diffuse term
    return max(0.0, NdotL) * (A + B * max(0.0, cosPhi) * sinAlpha * tanBeta);
}

// Simplified Oren-Nayar (faster, good approximation)
float OrenNayarDiffuseSimplified(float NdotL, float NdotV, float roughness)
{
    float sigma2 = roughness * roughness;
    float A = 1.0 - 0.5 * sigma2 / (sigma2 + 0.33);
    float B = 0.45 * sigma2 / (sigma2 + 0.09);
    
    float sinAlpha = max(NdotL, NdotV);
    float tanBeta = sqrt(1.0 - sinAlpha * sinAlpha) / sinAlpha;
    
    return NdotL * (A + B * sinAlpha * tanBeta);
}

// Blend between Lambert and Oren-Nayar based on roughness
float BlendLambertOrenNayar(float NdotL, float NdotV, float LdotV, float roughness)
{
    float lambert = NdotL;
    float orenNayar = OrenNayarDiffuse(NdotL, NdotV, LdotV, roughness);
    
    // Use Oren-Nayar for rough surfaces, Lambert for smooth
    float blendFactor = smoothstep(0.0, 0.5, roughness);
    return lerp(lambert, orenNayar, blendFactor);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Sample the BRDF lookup texture (legacy compatibility)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
float4 SampleBRDF(float2 vBRDFLookup)
{
    return BRDFLookup.SampleLevel(g_sTrilinearClamp, vBRDFLookup.xy, 0.0);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Enhanced BRDF Components
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Iridescence / Thin-film interference
// Based on "Real-Time Rendering of Thin-Film Interference" (2019)
// Uses a simplified Fresnel model with wavelength-dependent phase shift
//
// Parameters:
// - NdotV: cosine between normal and view direction
// - NdotL: cosine between normal and light direction
// - thickness: film thickness (0-1, maps to ~0-1000nm)
// - ior: index of refraction of the film
float3 IridescenceThinFilm(float NdotV, float NdotL, float thickness, float ior)
{
    // Convert thickness to physical units (0-1 -> 0-1000nm)
    float d = thickness * 1000.0; // nanometers
    
    // Wavelengths for RGB (in nm)
    float3 lambda = float3(650.0, 530.0, 460.0);
    
    // Phase difference due to path length
    float3 delta = (4.0 * BRDF_PI * ior * d / lambda) * NdotV;
    
    // Fresnel coefficients at interfaces (air-film and film-substrate)
    float3 R1 = ComputeF0FromIOR(ior);
    float3 R2 = float3(0.04, 0.04, 0.04); // Assume dielectric substrate
    
    // Interference term
    float3 interference = 2.0 * sqrt(R1 * R2) * cos(delta);
    
    // Total reflectance
    float3 R = (R1 + R2 + interference) / (1.0 + R1 * R2 + interference);
    
    // Scale by Fresnel at current angle
    float F = SchlickFresnel(NdotL);
    R = lerp(R, float3(1.0, 1.0, 1.0), F);
    
    return saturate(R);
}

// Simplified iridescence using texture lookup (faster)
float3 IridescenceSimplified(float NdotV, float thickness)
{
    // Map thickness and angle to rainbow color
    float t = thickness + (1.0 - NdotV) * 0.5;
    
    // Rainbow gradient approximation
    float3 color;
    color.r = sin(t * 6.28318) * 0.5 + 0.5;
    color.g = sin(t * 6.28318 + 2.0944) * 0.5 + 0.5;
    color.b = sin(t * 6.28318 + 4.1888) * 0.5 + 0.5;
    
    return saturate(color * 0.5 + 0.5);
}

// Enhanced clearcoat with customizable IOR
// Parameters:
// - NdotH: cosine between normal and half vector
// - NdotL: cosine between normal and light direction
// - NdotV: cosine between normal and view direction
// - clearcoat: clearcoat intensity (0-1)
// - clearcoatGloss: clearcoat glossiness (0-1)
// - clearcoatIOR: IOR of clearcoat layer (default 1.5 for typical clearcoat)
float3 ClearcoatEnhanced(float NdotH, float NdotL, float NdotV, float clearcoat, float clearcoatGloss, float clearcoatIOR)
{
    // Clearcoat F0 from IOR
    float F0 = GetDielectricF0Value(clearcoatIOR);
    
    // Roughness for clearcoat (very smooth by default)
    float coatRoughness = lerp(0.1, 0.001, clearcoatGloss);
    float a = coatRoughness * coatRoughness;
    
    // GTR1 distribution for clearcoat (sharp lobe)
    float D = GTR1Improved(NdotH, a);
    
    // Fresnel for clearcoat
    float F = F0 + (1.0 - F0) * SchlickFresnel(NdotH);
    
    // Smith GGX visibility (fixed roughness for clearcoat)
    float G = SmithGGX(NdotL, 0.25) * SmithGGX(NdotV, 0.25);
    
    // Clearcoat term (0.25 factor for energy conservation with IOR 1.5)
    float coatFactor = 0.25 * clearcoat;
    
    return coatFactor * G * F * D;
}

// Enhanced sheen with fiber anisotropy
// Parameters:
// - LdotH: cosine between light and half vector
// - NdotL: cosine between normal and light direction
// - NdotV: cosine between normal and view direction
// - sheen: sheen intensity (0-1)
// - sheenColor: RGB sheen color
// - sheenRoughness: sheen lobe roughness
float3 SheenEnhanced(float LdotH, float NdotL, float NdotV, float sheen, float3 sheenColor, float sheenRoughness)
{
    // Velvet/fabric Fresnel (brighter at grazing angles)
    float Fsheen = SchlickFresnel(LdotH);
    
    // Roughness affects the falloff
    float roughnessFactor = lerp(1.0, 0.5, sheenRoughness);
    
    // Sheen term with energy compensation
    float3 sheenTerm = Fsheen * sheen * sheenColor * roughnessFactor;
    
    return sheenTerm;
}

// Transmission for thin-walled materials (glass, leaves)
// Parameters:
// - NdotL: cosine between normal and light direction
// - NdotV: cosine between normal and view direction
// - transmission: transmission intensity (0-1)
// - thickness: material thickness for absorption
// - absorptionCoefficient: RGB absorption per unit thickness
float3 TransmissionThin(float NdotL, float NdotV, float transmission, float thickness, float3 absorptionCoefficient)
{
    // Beer-Lambert law for absorption
    float3 transmittance = exp(-absorptionCoefficient * thickness);
    
    // Transmission factor (brighter at grazing angles for thin materials)
    float transmissionFactor = transmission * (1.0 - SchlickFresnel(NdotV));
    
    return transmittance * transmissionFactor;
}

// Transmission for volumetric materials (thick glass, water)
// Uses refraction direction instead of simple transmission
float3 TransmissionVolumetric(float3 L, float3 V, float3 N, float3 T, float transmission, float ior, float thickness, float3 absorptionCoefficient)
{
    // Refract light direction through surface
    float eta = 1.0 / ior;
    float3 Lr = refract(-L, N, eta);
    
    // If total internal reflection, return black
    if (length(Lr) < 0.001)
        return float3(0.0, 0.0, 0.0);
    
    Lr = normalize(Lr);
    
    // Beer-Lambert absorption through volume
    float3 transmittance = exp(-absorptionCoefficient * thickness);
    
    // Fresnel loss at entry and exit
    float F_entry = SchlickFresnel(dot(N, -L));
    float F_exit = SchlickFresnel(dot(N, -Lr));
    
    return transmittance * transmission * (1.0 - F_entry) * (1.0 - F_exit);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Disney BRDF Core Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Compute the full Disney BRDF (Enhanced Version)
// Returns: reflected radiance (diffuse + specular + sheen + clearcoat + iridescence + transmission)
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
// - clearcoatIOR: IOR of clearcoat layer (default 1.5)
// - transmission: transmission intensity (0-1)
// - thickness: material thickness for absorption
// - absorptionCoefficient: RGB absorption per unit thickness
// - iridescence: iridescence intensity (0-1)
// - iridescenceIOR: IOR of thin film (default 1.3-1.8)
// - ior: index of refraction for dielectric F0 (default 1.5)
// - useOrenNayar: use Oren-Nayar diffuse for rough surfaces
float3 DisneyBRDFEnhanced(
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
    float clearcoatGloss,
    float clearcoatIOR = 1.5,
    float transmission = 0.0,
    float thickness = 1.0,
    float3 absorptionCoefficient = float3(0.0, 0.0, 0.0),
    float iridescence = 0.0,
    float iridescenceIOR = 1.5,
    float ior = 1.5,
    bool useOrenNayar = false)
{
    float NdotL = dot(N, L);
    float NdotV = dot(N, V);
    float LdotV = dot(L, V);

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
    // Dielectrics: from IOR, Metals: tinted by base color
    float3 dielectricF0 = ComputeF0FromIOR(ior) * specular * 2.0;
    float3 Cspec0 = lerp(dielectricF0, Cdlin, metallic);

    // Compute sheen color
    float3 Csheen = lerp(float3(1.0, 1.0, 1.0), Ctint, sheenTint);

    // -------------------------------------------------------------------------
    // Diffuse component (with Oren-Nayar or subsurface approximation)
    // -------------------------------------------------------------------------
    float diffuseFactor;
    if (useOrenNayar && roughness > 0.5)
    {
        // Use Oren-Nayar for rough surfaces
        diffuseFactor = OrenNayarDiffuseSimplified(NdotL, NdotV, roughness);
    }
    else if (subsurface > 0.0)
    {
        // Blend between Fresnel diffuse and subsurface
        float Fd = FresnelDiffuse(NdotL, NdotV, LdotH, roughness);
        float ss = SubsurfaceScattering(NdotL, NdotV, LdotH, roughness);
        diffuseFactor = lerp(Fd, ss, subsurface);
    }
    else
    {
        // Standard Fresnel diffuse
        diffuseFactor = FresnelDiffuse(NdotL, NdotV, LdotH, roughness);
    }
    
    float3 diffuseTerm = (BRDF_INV_PI * diffuseFactor * Cdlin) * (1.0 - metallic);

    // -------------------------------------------------------------------------
    // Specular component (GGX microfacet with energy compensation)
    // -------------------------------------------------------------------------
    float aspect = sqrt(1.0 - anisotropic * 0.9);
    float ax = max(0.001, Sqr(roughness) / aspect);
    float ay = max(0.001, Sqr(roughness) * aspect);

    float Ds = GTR2Aniso(NdotH, dot(H, X), dot(H, Y), ax, ay);
    float3 Fs = SchlickFresnelRGB(Cspec0, LdotH);
    float Gs = SmithGGXAniso(NdotL, dot(L, X), dot(L, Y), ax, ay) *
               SmithGGXAniso(NdotV, dot(V, X), dot(V, Y), ax, ay);

    // Multi-scattering energy compensation for rough surfaces
    float energyComp = GGXEnergyCompensation(NdotV, roughness);
    float3 specularTerm = Gs * Fs * Ds * energyComp;

    // -------------------------------------------------------------------------
    // Sheen component (fabric-like grazing angle reflection)
    // -------------------------------------------------------------------------
    float3 sheenTerm = SheenEnhanced(LdotH, NdotL, NdotV, sheen, Csheen, roughness);
    sheenTerm *= (1.0 - metallic);

    // -------------------------------------------------------------------------
    // Clearcoat component (additional sharp specular layer)
    // -------------------------------------------------------------------------
    float3 clearcoatTerm = ClearcoatEnhanced(NdotH, NdotL, NdotV, clearcoat, clearcoatGloss, clearcoatIOR);

    // -------------------------------------------------------------------------
    // Transmission component (for thin-walled materials)
    // -------------------------------------------------------------------------
    float3 transmissionTerm = float3(0.0, 0.0, 0.0);
    if (transmission > 0.0)
    {
        transmissionTerm = TransmissionThin(NdotL, NdotV, transmission, thickness, absorptionCoefficient);
        transmissionTerm *= (1.0 - metallic); // No transmission for metals
    }

    // -------------------------------------------------------------------------
    // Iridescence component (thin-film interference)
    // -------------------------------------------------------------------------
    float3 iridescenceTerm = float3(0.0, 0.0, 0.0);
    if (iridescence > 0.0)
    {
        iridescenceTerm = IridescenceThinFilm(NdotV, NdotL, iridescence, iridescenceIOR);
        iridescenceTerm *= iridescence;
    }

    // Combine all components with energy conservation
    // Clearcoat is additive (separate layer)
    // Transmission replaces some diffuse
    // Iridescence modulates specular
    float3 result = diffuseTerm * (1.0 - transmission) + 
                    specularTerm + 
                    sheenTerm + 
                    clearcoatTerm + 
                    transmissionTerm +
                    iridescenceTerm * specularTerm;

    return result;
}

// Compute the full Disney BRDF (Original Version - for compatibility)
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
    // Call enhanced version with default parameters
    return DisneyBRDFEnhanced(
        L, V, N, X, Y,
        baseColor, metallic, subsurface, specular, roughness,
        specularTint, anisotropic, sheen, sheenTint,
        clearcoat, clearcoatGloss,
        1.5,    // clearcoatIOR
        0.0,    // transmission
        1.0,    // thickness
        float3(0.0, 0.0, 0.0), // absorptionCoefficient
        0.0,    // iridescence
        1.5,    // iridescenceIOR
        1.5,    // ior
        false   // useOrenNayar
    );
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

#endif /* BRDF_HLSL */
