#ifndef BRDF_MATERIAL_HLSL
#define BRDF_MATERIAL_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Enhanced Material System for Disney BRDF
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Extended material struct with all Disney BRDF parameters plus advanced features
// Use this for PBR rendering with the enhanced BRDF model
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "common/material.hlsl"
#include "common/BRDF.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Extended Material struct with all BRDF parameters
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
class MaterialExtended : Material
{
    // Enhanced BRDF properties
    float  Specular;              // Specular intensity (0-1, default 0.5)
    float  SpecularTint;          // Tint specular by base color (0-1)
    float  IOR;                   // Index of refraction (default 1.5)
    float  Subsurface;            // Subsurface scattering amount (0-1)
    float  SubsurfaceThickness;   // Thickness for SSS absorption
    float3 SubsurfaceColor;       // Color of subsurface scattering
    
    // Clearcoat layer
    float  Coat;                  // Clearcoat intensity (0-1)
    float  CoatRoughness;         // Clearcoat roughness (0-1)
    float  CoatIOR;               // Clearcoat IOR (default 1.5)
    
    // Sheen layer (fabric)
    float  Sheen;                 // Sheen intensity (0-1)
    float3 SheenColor;            // Sheen color (default white)
    float  SheenRoughness;        // Sheen lobe roughness
    
    // Anisotropy
    float  Anisotropy;            // Anisotropy strength (0-1)
    float  AnisotropyRotation;    // Rotation of anisotropy (0-1, 0-360 degrees)
    float3 AnisotropyDirection;   // World-space direction of anisotropy
    
    // Transmission
    float  Transmission;          // Transmission intensity (0-1)
    float  Thickness;             // Material thickness for absorption
    float3 AbsorptionCoefficient; // RGB absorption per unit thickness
    
    // Iridescence (thin-film)
    float  Iridescence;           // Iridescence intensity (0-1)
    float  IridescenceIOR;        // IOR of thin film (1.3-1.8)
    float  IridescenceThickness;  // Film thickness (0-1, ~0-1000nm)
    
    // Advanced options
    bool   UseOrenNayar;          // Use Oren-Nayar diffuse for rough surfaces
    bool   UseEnergyCompensation; // Enable multi-scattering compensation
    
    // Material preset (for quick setup)
    int    MaterialPreset;        // 0=Default, 1=Metal, 2=Glass, 3=Fabric, 4=Skin, etc.
    
    /// <summary>
    /// Initialize extended material with default values
    /// </summary>
    static MaterialExtended Init(float3 RelativeWorldPosition = 0.0f, float4 ScreenPosition = 0.0f);
    
    /// <summary>
    /// Initialize from base Material
    /// </summary>
    static MaterialExtended FromBase(Material base);
    
    /// <summary>
    /// Lerp between two extended materials
    /// </summary>
    static MaterialExtended lerp(MaterialExtended a, MaterialExtended b, float amount);
    
    /// <summary>
    /// Setup material preset (metal, glass, fabric, etc.)
    /// </summary>
    void SetupPreset(int preset);
    
    /// <summary>
    /// Validate and clamp all parameters to valid ranges
    /// </summary>
    void Validate();
    
    /// <summary>
    /// Compute tangent frame for anisotropic shading
    /// </summary>
    void ComputeTangentFrame(out float3 tangentX, out float3 tangentY);
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Implementation
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

MaterialExtended MaterialExtended::Init(float3 RelativeWorldPosition, float4 ScreenPosition)
{
    MaterialExtended m = (MaterialExtended)Material::Init(RelativeWorldPosition, ScreenPosition);
    
    // Enhanced BRDF properties
    m.Specular = 0.5;
    m.SpecularTint = 0.0;
    m.IOR = 1.5;
    m.Subsurface = 0.0;
    m.SubsurfaceThickness = 1.0;
    m.SubsurfaceColor = float3(1.0, 1.0, 1.0);
    
    // Clearcoat
    m.Coat = 0.0;
    m.CoatRoughness = 0.0;
    m.CoatIOR = 1.5;
    
    // Sheen
    m.Sheen = 0.0;
    m.SheenColor = float3(1.0, 1.0, 1.0);
    m.SheenRoughness = 0.5;
    
    // Anisotropy
    m.Anisotropy = 0.0;
    m.AnisotropyRotation = 0.0;
    m.AnisotropyDirection = float3(1.0, 0.0, 0.0);
    
    // Transmission
    m.Transmission = 0.0;
    m.Thickness = 1.0;
    m.AbsorptionCoefficient = float3(0.0, 0.0, 0.0);
    
    // Iridescence
    m.Iridescence = 0.0;
    m.IridescenceIOR = 1.5;
    m.IridescenceThickness = 0.5;
    
    // Advanced options
    m.UseOrenNayar = false;
    m.UseEnergyCompensation = true;
    m.MaterialPreset = 0;
    
    return m;
}

MaterialExtended MaterialExtended::FromBase(Material base)
{
    MaterialExtended m = Init(base.WorldPositionWithOffset, base.ScreenPosition);
    
    // Copy base properties
    m.Albedo = base.Albedo;
    m.Metalness = base.Metalness;
    m.Roughness = base.Roughness;
    m.Emission = base.Emission;
    m.Normal = base.Normal;
    m.TintMask = base.TintMask;
    m.AmbientOcclusion = base.AmbientOcclusion;
    m.Transmission = length(base.Transmission);
    m.Opacity = base.Opacity;
    
    m.WorldPosition = base.WorldPosition;
    m.WorldPositionWithOffset = base.WorldPositionWithOffset;
    m.ScreenPosition = base.ScreenPosition;
    
    m.TangentNormal = base.TangentNormal;
    m.WorldTangentU = base.WorldTangentU;
    m.WorldTangentV = base.WorldTangentV;
    m.LightmapUV = base.LightmapUV;
    m.TextureCoords = base.TextureCoords;
    
    return m;
}

MaterialExtended MaterialExtended::lerp(MaterialExtended a, MaterialExtended b, float amount)
{
    MaterialExtended o = a;
    
    // Base material lerp
    o.Albedo = ::lerp(a.Albedo, b.Albedo, amount);
    o.Emission = ::lerp(a.Emission, b.Emission, amount);
    o.Opacity = ::lerp(a.Opacity, b.Opacity, amount);
    o.TintMask = ::lerp(a.TintMask, b.TintMask, amount);
    o.Normal = normalize(::lerp(a.Normal, b.Normal, amount));
    o.Roughness = ::lerp(a.Roughness, b.Roughness, amount);
    o.Metalness = ::lerp(a.Metalness, b.Metalness, amount);
    o.AmbientOcclusion = ::lerp(a.AmbientOcclusion, b.AmbientOcclusion, amount);
    
    // Extended properties
    o.Specular = ::lerp(a.Specular, b.Specular, amount);
    o.SpecularTint = ::lerp(a.SpecularTint, b.SpecularTint, amount);
    o.IOR = ::lerp(a.IOR, b.IOR, amount);
    o.Subsurface = ::lerp(a.Subsurface, b.Subsurface, amount);
    o.SubsurfaceThickness = ::lerp(a.SubsurfaceThickness, b.SubsurfaceThickness, amount);
    o.SubsurfaceColor = ::lerp(a.SubsurfaceColor, b.SubsurfaceColor, amount);
    
    o.Coat = ::lerp(a.Coat, b.Coat, amount);
    o.CoatRoughness = ::lerp(a.CoatRoughness, b.CoatRoughness, amount);
    o.CoatIOR = ::lerp(a.CoatIOR, b.CoatIOR, amount);
    
    o.Sheen = ::lerp(a.Sheen, b.Sheen, amount);
    o.SheenColor = ::lerp(a.SheenColor, b.SheenColor, amount);
    o.SheenRoughness = ::lerp(a.SheenRoughness, b.SheenRoughness, amount);
    
    o.Anisotropy = ::lerp(a.Anisotropy, b.Anisotropy, amount);
    o.AnisotropyRotation = ::lerp(a.AnisotropyRotation, b.AnisotropyRotation, amount);
    o.AnisotropyDirection = normalize(::lerp(a.AnisotropyDirection, b.AnisotropyDirection, amount));
    
    o.Transmission = ::lerp(a.Transmission, b.Transmission, amount);
    o.Thickness = ::lerp(a.Thickness, b.Thickness, amount);
    o.AbsorptionCoefficient = ::lerp(a.AbsorptionCoefficient, b.AbsorptionCoefficient, amount);
    
    o.Iridescence = ::lerp(a.Iridescence, b.Iridescence, amount);
    o.IridescenceIOR = ::lerp(a.IridescenceIOR, b.IridescenceIOR, amount);
    o.IridescenceThickness = ::lerp(a.IridescenceThickness, b.IridescenceThickness, amount);
    
    // Boolean flags (use step function for smooth transition)
    o.UseOrenNayar = (a.UseOrenNayar && b.UseOrenNayar) || amount > 0.5;
    o.UseEnergyCompensation = (a.UseEnergyCompensation && b.UseEnergyCompensation) || amount > 0.5;
    
    return o;
}

void MaterialExtended::SetupPreset(int preset)
{
    MaterialPreset = preset;
    
    if (preset == 1) // Metal
    {
        Metalness = 1.0;
        Roughness = 0.3;
        Specular = 1.0;
        SpecularTint = 1.0;
        Coat = 0.0;
        Sheen = 0.0;
        Transmission = 0.0;
        Iridescence = 0.0;
    }
    else if (preset == 2) // Glass
    {
        Metalness = 0.0;
        Roughness = 0.05;
        Specular = 1.0;
        IOR = 1.52;
        Transmission = 1.0;
        Thickness = 0.5;
        AbsorptionCoefficient = float3(0.1, 0.1, 0.1);
        Coat = 0.0;
        Sheen = 0.0;
        Iridescence = 0.0;
    }
    else if (preset == 3) // Fabric
    {
        Metalness = 0.0;
        Roughness = 0.8;
        Specular = 0.3;
        Sheen = 0.8;
        SheenColor = Albedo;
        Coat = 0.0;
        Transmission = 0.0;
        Iridescence = 0.0;
        UseOrenNayar = true;
    }
    else if (preset == 4) // Skin
    {
        Metalness = 0.0;
        Roughness = 0.4;
        Specular = 0.5;
        Subsurface = 0.8;
        SubsurfaceThickness = 0.5;
        SubsurfaceColor = Albedo * float3(1.0, 0.7, 0.6); // Reddish scattering
        Coat = 0.0;
        Sheen = 0.0;
        Transmission = 0.0;
        Iridescence = 0.0;
    }
    else if (preset == 5) // Car Paint
    {
        Metalness = 0.8;
        Roughness = 0.2;
        Specular = 1.0;
        Coat = 1.0;
        CoatRoughness = 0.05;
        CoatIOR = 1.5;
        Sheen = 0.0;
        Transmission = 0.0;
        Iridescence = 0.0;
    }
    else if (preset == 6) // Iridescent
    {
        Metalness = 0.5;
        Roughness = 0.3;
        Specular = 1.0;
        Iridescence = 1.0;
        IridescenceIOR = 1.5;
        IridescenceThickness = 0.5;
        Coat = 0.0;
        Sheen = 0.0;
        Transmission = 0.0;
    }
    else if (preset == 7) // Water
    {
        Metalness = 0.0;
        Roughness = 0.1;
        Specular = 1.0;
        IOR = 1.33;
        Transmission = 0.9;
        Thickness = 2.0;
        AbsorptionCoefficient = float3(0.05, 0.1, 0.15); // Blue-green absorption
        Coat = 0.0;
        Sheen = 0.0;
        Iridescence = 0.0;
    }
    else if (preset == 8) // Diamond
    {
        Metalness = 0.0;
        Roughness = 0.0;
        Specular = 1.0;
        IOR = 2.42;
        Transmission = 1.0;
        Thickness = 1.0;
        AbsorptionCoefficient = float3(0.0, 0.0, 0.0);
        Coat = 0.0;
        Sheen = 0.0;
        Iridescence = 0.0;
    }
    // Default preset (0) uses manual settings
}

void MaterialExtended::Validate()
{
    // Clamp all parameters to valid ranges
    Albedo = saturate(Albedo);
    Metalness = saturate(Metalness);
    Roughness = saturate(Roughness);
    Specular = saturate(Specular);
    SpecularTint = saturate(SpecularTint);
    IOR = clamp(IOR, 1.0, 3.0);
    Subsurface = saturate(Subsurface);
    SubsurfaceThickness = max(SubsurfaceThickness, 0.0);
    SubsurfaceColor = saturate(SubsurfaceColor);
    
    Coat = saturate(Coat);
    CoatRoughness = saturate(CoatRoughness);
    CoatIOR = clamp(CoatIOR, 1.0, 2.5);
    
    Sheen = saturate(Sheen);
    SheenColor = saturate(SheenColor);
    SheenRoughness = saturate(SheenRoughness);
    
    Anisotropy = saturate(Anisotropy);
    AnisotropyRotation = frac(AnisotropyRotation);
    AnisotropyDirection = normalize(AnisotropyDirection);
    
    Transmission = saturate(Transmission);
    Thickness = max(Thickness, 0.0);
    AbsorptionCoefficient = max(AbsorptionCoefficient, float3(0, 0, 0));
    
    Iridescence = saturate(Iridescence);
    IridescenceIOR = clamp(IridescenceIOR, 1.0, 2.5);
    IridescenceThickness = saturate(IridescenceThickness);
    
    Opacity = saturate(Opacity);
    AmbientOcclusion = saturate(AmbientOcclusion);
}

void MaterialExtended::ComputeTangentFrame(out float3 tangentX, out float3 tangentY)
{
    // Get base tangents
    tangentX = WorldTangentU;
    tangentY = WorldTangentV;
    
    // Apply anisotropy rotation
    if (AnisotropyRotation > 0.0)
    {
        float angle = AnisotropyRotation * 2.0 * BRDF_PI;
        float c = cos(angle);
        float s = sin(angle);
        
        float3 rotatedX = tangentX * c + tangentY * s;
        float3 rotatedY = cross(Normal, rotatedX);
        
        tangentX = rotatedX;
        tangentY = rotatedY;
    }
    
    // Use anisotropy direction if provided
    if (length(AnisotropyDirection) > 0.001)
    {
        tangentX = CreateAnisotropicTangent(Normal, AnisotropyDirection);
        tangentY = cross(Normal, tangentX);
    }
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Convert MaterialExtended to base Material (for compatibility)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
Material ToBaseMaterial(MaterialExtended extended)
{
    Material m = Material::Init(extended.WorldPositionWithOffset, extended.ScreenPosition);
    
    m.Albedo = extended.Albedo;
    m.Metalness = extended.Metalness;
    m.Roughness = extended.Roughness;
    m.Emission = extended.Emission;
    m.Normal = extended.Normal;
    m.TintMask = extended.TintMask;
    m.AmbientOcclusion = extended.AmbientOcclusion;
    m.Transmission = extended.Transmission * extended.AbsorptionCoefficient;
    m.Opacity = extended.Opacity;
    
    m.WorldPosition = extended.WorldPosition;
    m.WorldPositionWithOffset = extended.WorldPositionWithOffset;
    m.ScreenPosition = extended.ScreenPosition;
    
    m.TangentNormal = extended.TangentNormal;
    m.WorldTangentU = extended.WorldTangentU;
    m.WorldTangentV = extended.WorldTangentV;
    m.LightmapUV = extended.LightmapUV;
    m.TextureCoords = extended.TextureCoords;
    
    return m;
}

#endif /* BRDF_MATERIAL_HLSL */
