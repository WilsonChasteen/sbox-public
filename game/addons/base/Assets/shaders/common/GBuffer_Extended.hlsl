#ifndef GBUFFER_EXTENDED_HLSL
#define GBUFFER_EXTENDED_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Extended G-Buffer for Disney BRDF
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Extended G-Buffer layout for deferred rendering with full Disney BRDF parameters
// Provides efficient packing of material properties for deferred lighting passes
//
// G-Buffer Layout (for 4 MRT setup):
//   G0: Albedo RGB + Metalness
//   G1: Normal RGB + Roughness
//   G2: Coat + Sheen + Subsurface + Transmission
//   G3: Emission + IOR + Anisotropy + Flags
//
// For 8 MRT or tiled rendering, additional buffers can be used:
//   G4: Thickness + Iridescence + Reserved
//   G5: Anisotropy direction (XY) + Reserved
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "common/GBuffer.hlsl"
#include "BRDF.hlsl"
#include "BRDF_Material.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// G-Buffer Structure
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
struct GBufferExtended
{
    float4 G0; // Albedo (RGB) + Metalness (A)
    float4 G1; // Normal (RGB) + Roughness (A)
    float4 G2; // Coat (R) + Sheen (G) + Subsurface (B) + Transmission (A)
    float4 G3; // Emission (RGB) + Packaged data (A)
    float4 G4; // Thickness (R) + Iridescence (G) + Anisotropy (B) + Flags (A)
    float4 G5; // Anisotropy Direction (XY) + Reserved (ZW)
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Encoding/Decoding Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Pack material parameters into G3.A
// Bits: [0-1] IOR index, [2-3] Reserved, [4-5] Shading model, [6-7] Flags
float PackG3Alpha(float ior, float anisotropy, float clearcoat, float flags)
{
    // Normalize IOR to 0-2 range (covers most materials)
    float iorPacked = saturate((ior - 1.0) / 2.0);
    
    // Pack into channels
    return iorPacked * 0.25 + anisotropy * 0.5 + clearcoat * 0.125 + flags * 0.0625;
}

// Unpack G3.A
void UnpackG3Alpha(float packed, out float ior, out float anisotropy, out float clearcoat, out float flags)
{
    ior = 1.0 + (packed / 0.25) * 2.0;
    anisotropy = frac(packed / 0.5);
    clearcoat = frac(packed / 0.125);
    flags = frac(packed / 0.0625);
}

// Encode normal for G-Buffer (remap from [-1,1] to [0,1])
float3 EncodeNormal(float3 normal)
{
    return normal * 0.5 + 0.5;
}

// Decode normal from G-Buffer
float3 DecodeNormal(float3 encoded)
{
    return encoded * 2.0 - 1.0;
}

// Octahedral normal encoding (more efficient)
float2 EncodeNormalOct(float3 n)
{
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z >= 0)
        return n.xy;
    else
        return (1.0 - abs(n.yx)) * (n.xy >= 0.0 ? 1.0 : -1.0);
}

float3 DecodeNormalOct(float2 encoded)
{
    float3 n = float3(encoded.x, encoded.y, 1.0 - abs(encoded.x) - abs(encoded.y));
    float t = saturate(-n.z);
    n.xy += n.xy >= 0.0 ? -t : t;
    return normalize(n);
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// G-Buffer Output Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Create G-Buffer from MaterialExtended
GBufferExtended CreateGBuffer(MaterialExtended m)
{
    GBufferExtended gbuffer;
    
    // G0: Albedo + Metalness
    gbuffer.G0 = float4(m.Albedo, m.Metalness);
    
    // G1: Normal + Roughness
    gbuffer.G1 = float4(EncodeNormal(m.Normal), m.Roughness);
    
    // G2: Coat + Sheen + Subsurface + Transmission
    gbuffer.G2 = float4(m.Coat, m.Sheen, m.Subsurface, m.Transmission);
    
    // G3: Emission + Packed data
    gbuffer.G3 = float4(m.Emission, PackG3Alpha(m.IOR, m.Anisotropy, m.Coat, 0.0));
    
    // G4: Thickness + Iridescence + Anisotropy + Flags
    gbuffer.G4 = float4(m.Thickness, m.Iridescence, m.Anisotropy, 0.0);
    
    // G5: Anisotropy Direction
    float3 tangentX, tangentY;
    m.ComputeTangentFrame(tangentX, tangentY);
    gbuffer.G5 = float4(tangentX.xy, 0.0, 0.0);
    
    return gbuffer;
}

// Create G-Buffer from standard Material (compatibility)
GBufferExtended CreateGBuffer(Material m)
{
    MaterialExtended ext = MaterialExtended::FromBase(m);
    return CreateGBuffer(ext);
}

// Reconstruct material from G-Buffer
MaterialExtended ReconstructMaterial(GBufferExtended gbuffer)
{
    MaterialExtended m = MaterialExtended::Init();
    
    // Unpack G0
    m.Albedo = gbuffer.G0.rgb;
    m.Metalness = gbuffer.G0.a;
    
    // Unpack G1
    m.Normal = DecodeNormal(gbuffer.G1.rgb);
    m.Roughness = gbuffer.G1.a;
    
    // Unpack G2
    m.Coat = gbuffer.G2.r;
    m.Sheen = gbuffer.G2.g;
    m.Subsurface = gbuffer.G2.b;
    m.Transmission = gbuffer.G2.a;
    
    // Unpack G3
    m.Emission = gbuffer.G3.rgb;
    float ior, anisotropy, clearcoat, flags;
    UnpackG3Alpha(gbuffer.G3.a, ior, anisotropy, clearcoat, flags);
    m.IOR = ior;
    m.Anisotropy = anisotropy;
    
    // Unpack G4
    m.Thickness = gbuffer.G4.r;
    m.Iridescence = gbuffer.G4.g;
    
    // Unpack G5
    m.WorldTangentU = float3(gbuffer.G5.xy, 0.0); // Reconstruct full tangent if needed
    
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Deferred Lighting Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Sample G-Buffer at screen position
GBufferExtended SampleGBuffer(Texture2D gbuffer0, Texture2D gbuffer1, Texture2D gbuffer2, 
                              Texture2D gbuffer3, Texture2D gbuffer4, Texture2D gbuffer5,
                              float2 screenUV)
{
    GBufferExtended gbuffer;
    gbuffer.G0 = gbuffer0.SampleLevel(g_sPointClamp, screenUV, 0.0);
    gbuffer.G1 = gbuffer1.SampleLevel(g_sPointClamp, screenUV, 0.0);
    gbuffer.G2 = gbuffer2.SampleLevel(g_sPointClamp, screenUV, 0.0);
    gbuffer.G3 = gbuffer3.SampleLevel(g_sPointClamp, screenUV, 0.0);
    gbuffer.G4 = gbuffer4.SampleLevel(g_sPointClamp, screenUV, 0.0);
    gbuffer.G5 = gbuffer5.SampleLevel(g_sPointClamp, screenUV, 0.0);
    return gbuffer;
}

// Compute deferred lighting for a single light
float3 ComputeDeferredLighting(GBufferExtended gbuffer, float3 lightDir, float3 lightColor, float lightAttenuation)
{
    MaterialExtended m = ReconstructMaterial(gbuffer);
    
    float NdotL = max(dot(m.Normal, lightDir), 0.0);
    if (NdotL <= 0.0)
        return float3(0.0, 0.0, 0.0);
    
    // View direction (would need position reconstruction for accurate V)
    float3 V = float3(0.0, 0.0, 1.0); // Placeholder
    
    // Compute BRDF
    float3 tangentX, tangentY;
    m.ComputeTangentFrame(tangentX, tangentY);
    
    float3 brdf = DisneyBRDFEnhanced(
        lightDir, V, m.Normal, tangentX, tangentY,
        m.Albedo, m.Metalness, m.Subsurface, m.Specular, m.Roughness,
        m.SpecularTint, m.Anisotropy, m.Sheen, m.SheenRoughness,
        m.Coat, m.CoatRoughness, m.CoatIOR,
        m.Transmission, m.Thickness, m.AbsorptionCoefficient,
        m.Iridescence, m.IridescenceIOR, m.IOR, m.UseOrenNayar
    );
    
    return brdf * lightColor * lightAttenuation * NdotL;
}

// Position reconstruction from depth
float3 ReconstructPosition(float2 screenUV, float depth, float4x4 invProjection, float4x4 invView)
{
    float4 clipPos = float4(screenUV * 2.0 - 1.0, depth, 1.0);
    float4 viewPos = mul(clipPos, invProjection);
    viewPos /= viewPos.w;
    float4 worldPos = mul(viewPos, invView);
    return worldPos.xyz / worldPos.w;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Compressed G-Buffer (for bandwidth-constrained scenarios)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// 2-buffer layout (reduced quality, lower bandwidth)
struct GBufferCompressed
{
    float4 G0; // Albedo (RGB) + Roughness/Metalness packed
    float4 G1; // Normal (octahedral) + Emission/Flags packed
};

GBufferCompressed CreateGBufferCompressed(MaterialExtended m)
{
    GBufferCompressed gbuffer;
    
    // G0: Albedo + packed roughness/metalness
    float packedRM = m.Roughness * 0.5 + m.Metalness * 0.5;
    gbuffer.G0 = float4(m.Albedo, packedRM);
    
    // G1: Octahedral normal + packed emission/flags
    float2 normalOct = EncodeNormalOct(m.Normal);
    float packedEmission = (m.Emission.r + m.Emission.g + m.Emission.b) / 3.0;
    gbuffer.G1 = float4(normalOct, packedEmission, m.Coat);
    
    return gbuffer;
}

MaterialExtended ReconstructMaterialCompressed(GBufferCompressed gbuffer)
{
    MaterialExtended m = MaterialExtended::Init();
    
    // Unpack G0
    m.Albedo = gbuffer.G0.rgb;
    float packedRM = gbuffer.G0.a;
    m.Roughness = packedRM * 2.0;
    m.Metalness = saturate((packedRM - 0.5) * 2.0);
    
    // Unpack G1
    m.Normal = DecodeNormalOct(gbuffer.G1.xy);
    float emissionAvg = gbuffer.G1.z;
    m.Emission = float3(emissionAvg, emissionAvg, emissionAvg);
    m.Coat = gbuffer.G1.w;
    
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Depth Prepass with G-Buffer
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Output for depth prepass with normal/roughness
float4 DepthNormalsOutput(float3 normal, float roughness, float opacity)
{
    // Remap normal from [-1, 1] to [0, 1]
    normal = 0.5f * (normal + 1.0f);
    
    #if (S_ALPHA_TEST)
        return float4(normal, opacity);
    #endif
    
    return float4(normal, roughness);
}

// Check if depth normals mode is active
bool WantsDepthNormalsExtended()
{
#ifdef S_MODE_DEPTH
    return S_MODE_DEPTH > 0;
#endif
    return false;
}

#endif /* GBUFFER_EXTENDED_HLSL */
