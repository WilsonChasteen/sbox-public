#ifndef MATERIAL_PRESETS_HLSL
#define MATERIAL_PRESETS_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Material Presets Library for Disney BRDF
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Pre-configured material presets for common real-world materials
// Use these as starting points and customize as needed
//
// Categories:
//   - Metals (Iron, Steel, Aluminum, Gold, Copper, Silver, Bronze, Brass)
//   - Dielectrics (Plastic, Glass, Water, Ceramic, Wood, Stone)
//   - Fabrics (Cotton, Silk, Velvet, Leather)
//   - Organic (Skin, Leaves, Marble)
//   - Special (Car Paint, Pearl, Holographic)
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "BRDF_Material.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Metal Presets
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Metals have high metalness (1.0), colored specular, and no transmission

MaterialExtended Preset_Iron()
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1); // Metal preset
    m.Albedo = float3(0.65, 0.65, 0.65);
    m.Roughness = 0.4;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Steel(float roughness = 0.3)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.70, 0.70, 0.70);
    m.Roughness = roughness;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_StainlessSteel(float roughness = 0.2)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.75, 0.75, 0.75);
    m.Roughness = roughness;
    m.SpecularTint = 1.0;
    m.Anisotropy = 0.3; // Brushed steel
    return m;
}

MaterialExtended Preset_Aluminum(float roughness = 0.35)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.80, 0.80, 0.80);
    m.Roughness = roughness;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Chrome(float roughness = 0.1)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.65, 0.65, 0.65);
    m.Roughness = roughness;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Gold(float roughness = 0.2)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(1.0, 0.85, 0.55); // Characteristic gold color
    m.Roughness = roughness;
    m.Specular = 1.0;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Copper(float roughness = 0.25)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(1.0, 0.60, 0.35); // Characteristic copper color
    m.Roughness = roughness;
    m.Specular = 1.0;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Bronze(float roughness = 0.3)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.80, 0.60, 0.40);
    m.Roughness = roughness;
    m.Specular = 1.0;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Brass(float roughness = 0.25)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.90, 0.75, 0.45);
    m.Roughness = roughness;
    m.Specular = 1.0;
    m.SpecularTint = 1.0;
    return m;
}

MaterialExtended Preset_Silver(float roughness = 0.15)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(1);
    m.Albedo = float3(0.95, 0.95, 0.95);
    m.Roughness = roughness;
    m.Specular = 1.0;
    m.SpecularTint = 1.0;
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Dielectric Presets
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Non-conductive materials with low metalness and possible transmission

MaterialExtended Preset_Plastic(float3 albedo = float3(0.5, 0.5, 0.5), float roughness = 0.3)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.5;
    m.IOR = 1.5;
    return m;
}

MaterialExtended Preset_PVC(float roughness = 0.4)
{
    MaterialExtended m = Preset_Plastic(float3(0.6, 0.6, 0.6), roughness);
    return m;
}

MaterialExtended Preset_Rubber(float3 albedo = float3(0.1, 0.1, 0.1), float roughness = 0.7)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.3;
    m.IOR = 1.5;
    m.UseOrenNayar = true;
    return m;
}

MaterialExtended Preset_Glass(float thickness = 1.0, float3 absorption = float3(0.0, 0.0, 0.0))
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(2); // Glass preset
    m.Albedo = float3(1.0, 1.0, 1.0);
    m.Metalness = 0.0;
    m.Roughness = 0.05;
    m.Specular = 1.0;
    m.IOR = 1.52;
    m.Transmission = 1.0;
    m.Thickness = thickness;
    m.AbsorptionCoefficient = absorption;
    return m;
}

MaterialExtended Preset_Water(float depth = 2.0)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(7); // Water preset
    m.Albedo = float3(1.0, 1.0, 1.0);
    m.Metalness = 0.0;
    m.Roughness = 0.1;
    m.Specular = 1.0;
    m.IOR = 1.33;
    m.Transmission = 0.95;
    m.Thickness = depth;
    m.AbsorptionCoefficient = float3(0.05, 0.1, 0.15); // Blue-green absorption
    return m;
}

MaterialExtended Preset_Diamond()
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(8); // Diamond preset
    m.Albedo = float3(1.0, 1.0, 1.0);
    m.Metalness = 0.0;
    m.Roughness = 0.0;
    m.Specular = 1.0;
    m.IOR = 2.42; // High IOR for diamond sparkle
    m.Transmission = 1.0;
    m.Thickness = 1.0;
    return m;
}

MaterialExtended Preset_Ceramic(float3 albedo = float3(0.9, 0.9, 0.9), float roughness = 0.15)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.5;
    m.IOR = 1.6;
    m.Coat = 0.3; // Slight glaze
    m.CoatRoughness = 0.05;
    return m;
}

MaterialExtended Preset_Porcelain()
{
    return Preset_Ceramic(float3(0.95, 0.93, 0.90), 0.2);
}

MaterialExtended Preset_Wood(float3 albedo = float3(0.4, 0.3, 0.2), float roughness = 0.6)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.3;
    m.IOR = 1.5;
    m.UseOrenNayar = true;
    m.Anisotropy = 0.5; // Wood grain
    return m;
}

MaterialExtended Preset_Stone(float3 albedo = float3(0.5, 0.5, 0.5), float roughness = 0.7)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.3;
    m.IOR = 1.6;
    m.UseOrenNayar = true;
    return m;
}

MaterialExtended Preset_Marble(float3 albedo = float3(0.8, 0.75, 0.7))
{
    MaterialExtended m = Preset_Stone(albedo, 0.3);
    m.IOR = 1.6;
    m.Coat = 0.2; // Polished surface
    m.CoatRoughness = 0.1;
    return m;
}

MaterialExtended Preset_Concrete(float roughness = 0.8)
{
    MaterialExtended m = Preset_Stone(float3(0.5, 0.5, 0.45), roughness);
    m.UseOrenNayar = true;
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Fabric Presets
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Materials with high roughness and sheen

MaterialExtended Preset_Cotton(float3 albedo = float3(0.7, 0.7, 0.7))
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(3); // Fabric preset
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = 0.8;
    m.Specular = 0.3;
    m.Sheen = 0.5;
    m.SheenColor = albedo;
    m.UseOrenNayar = true;
    return m;
}

MaterialExtended Preset_Silk(float3 albedo = float3(0.9, 0.85, 0.8))
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(3);
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = 0.4;
    m.Specular = 0.5;
    m.Sheen = 0.8;
    m.SheenColor = albedo;
    m.Anisotropy = 0.6; // Silk has directional sheen
    return m;
}

MaterialExtended Preset_Velvet(float3 albedo = float3(0.6, 0.2, 0.2))
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(3);
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = 1.0;
    m.Specular = 0.2;
    m.Sheen = 1.0;
    m.SheenColor = albedo;
    m.UseOrenNayar = true;
    return m;
}

MaterialExtended Preset_Leather(float3 albedo = float3(0.3, 0.15, 0.1), float roughness = 0.5)
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = roughness;
    m.Specular = 0.4;
    m.Sheen = 0.3;
    m.UseOrenNayar = true;
    return m;
}

MaterialExtended Preset_Denim(float3 albedo = float3(0.2, 0.3, 0.5))
{
    MaterialExtended m = Preset_Cotton(albedo);
    m.Roughness = 0.7;
    m.Sheen = 0.3;
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Organic Presets
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Materials with subsurface scattering

MaterialExtended Preset_Skin(int skinType = 1)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(4); // Skin preset
    
    // Adjust based on skin type
    if (skinType == 0) // Fair
    {
        m.Albedo = float3(0.9, 0.75, 0.65);
        m.SubsurfaceColor = float3(1.0, 0.6, 0.5);
    }
    else if (skinType == 1) // Medium
    {
        m.Albedo = float3(0.8, 0.6, 0.5);
        m.SubsurfaceColor = float3(0.95, 0.55, 0.45);
    }
    else if (skinType == 2) // Dark
    {
        m.Albedo = float3(0.5, 0.35, 0.28);
        m.SubsurfaceColor = float3(0.85, 0.45, 0.38);
    }
    else if (skinType == 3) // Asian
    {
        m.Albedo = float3(0.85, 0.65, 0.55);
        m.SubsurfaceColor = float3(0.95, 0.58, 0.48);
    }
    
    m.Metalness = 0.0;
    m.Roughness = 0.4;
    m.Specular = 0.5;
    m.Subsurface = 0.7;
    m.SubsurfaceThickness = 0.5;
    return m;
}

MaterialExtended Preset_Leaf(float3 albedo = float3(0.2, 0.5, 0.1))
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = 0.6;
    m.Specular = 0.3;
    m.Subsurface = 0.8;
    m.SubsurfaceThickness = 0.2;
    m.SubsurfaceColor = float3(0.3, 0.7, 0.2); // Green scattering
    m.Transmission = 0.5;
    m.Thickness = 0.1;
    return m;
}

MaterialExtended Preset_Wax(float3 albedo = float3(0.9, 0.85, 0.7))
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = albedo;
    m.Metalness = 0.0;
    m.Roughness = 0.3;
    m.Specular = 0.4;
    m.Subsurface = 0.9;
    m.SubsurfaceThickness = 1.0;
    m.SubsurfaceColor = albedo;
    return m;
}

MaterialExtended Preset_Milk()
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = float3(0.95, 0.93, 0.9);
    m.Metalness = 0.0;
    m.Roughness = 0.4;
    m.Specular = 0.3;
    m.Subsurface = 1.0;
    m.SubsurfaceThickness = 2.0;
    m.SubsurfaceColor = float3(0.95, 0.9, 0.85);
    m.Transmission = 0.3;
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Special/Coated Presets
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

MaterialExtended Preset_CarPaint(float3 baseColor, float metallic = 0.8)
{
    MaterialExtended m = MaterialExtended::Init();
    m.SetupPreset(5); // Car paint preset
    m.Albedo = baseColor;
    m.Metalness = metallic;
    m.Roughness = 0.2;
    m.Specular = 1.0;
    m.SpecularTint = metallic > 0.5;
    m.Coat = 1.0;
    m.CoatRoughness = 0.05;
    m.CoatIOR = 1.5;
    return m;
}

MaterialExtended Preset_CarPaintMetallic(float3 baseColor)
{
    return Preset_CarPaint(baseColor, 0.9);
}

MaterialExtended Preset_CarPaintSolid(float3 baseColor)
{
    return Preset_CarPaint(baseColor, 0.0);
}

MaterialExtended Preset_Pearl(float3 baseColor = float3(1.0, 0.95, 0.9))
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = baseColor;
    m.Metalness = 0.0;
    m.Roughness = 0.2;
    m.Specular = 0.8;
    m.Iridescence = 1.0;
    m.IridescenceIOR = 1.6;
    m.IridescenceThickness = 0.5;
    m.Coat = 0.5;
    m.CoatRoughness = 0.1;
    return m;
}

MaterialExtended Preset_OilSlick()
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = float3(0.1, 0.1, 0.1);
    m.Metalness = 0.0;
    m.Roughness = 0.1;
    m.Specular = 1.0;
    m.Iridescence = 1.0;
    m.IridescenceIOR = 1.45; // Oil IOR
    m.IridescenceThickness = 0.3; // Thin film
    m.Transmission = 0.1;
    return m;
}

MaterialExtended Preset_Holographic()
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = float3(0.8, 0.8, 0.8);
    m.Metalness = 0.5;
    m.Roughness = 0.2;
    m.Specular = 1.0;
    m.Iridescence = 1.0;
    m.IridescenceIOR = 2.0;
    m.IridescenceThickness = 0.7;
    return m;
}

MaterialExtended Preset_FrostedGlass(float3 albedo = float3(1.0, 1.0, 1.0))
{
    MaterialExtended m = Preset_Glass(1.0, float3(0.0, 0.0, 0.0));
    m.Albedo = albedo;
    m.Roughness = 0.6; // Frosted
    m.Transmission = 0.7;
    return m;
}

MaterialExtended Preset_Ice()
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = float3(0.95, 0.98, 1.0);
    m.Metalness = 0.0;
    m.Roughness = 0.3;
    m.Specular = 0.8;
    m.IOR = 1.31;
    m.Transmission = 0.8;
    m.Thickness = 2.0;
    m.AbsorptionCoefficient = float3(0.02, 0.05, 0.1);
    return m;
}

MaterialExtended Preset_Snow()
{
    MaterialExtended m = MaterialExtended::Init();
    m.Albedo = float3(0.95, 0.95, 0.98);
    m.Metalness = 0.0;
    m.Roughness = 1.0;
    m.Specular = 0.5;
    m.Subsurface = 0.8;
    m.SubsurfaceColor = float3(0.9, 0.95, 1.0); // Blue-ish scattering
    m.UseOrenNayar = true;
    return m;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Preset Helper Functions
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

// Get preset by name/index
MaterialExtended GetMaterialPreset(int presetIndex)
{
    switch (presetIndex)
    {
        case 0: return Preset_Iron();
        case 1: return Preset_Steel();
        case 2: return Preset_Aluminum();
        case 3: return Preset_Chrome();
        case 4: return Preset_Gold();
        case 5: return Preset_Copper();
        case 6: return Preset_Silver();
        case 7: return Preset_Plastic();
        case 8: return Preset_Glass();
        case 9: return Preset_Water();
        case 10: return Preset_Cotton();
        case 11: return Preset_Silk();
        case 12: return Preset_Velvet();
        case 13: return Preset_Leather();
        case 14: return Preset_Skin(1);
        case 15: return Preset_Wood();
        case 16: return Preset_Stone();
        case 17: return Preset_Marble();
        case 18: return Preset_CarPaintMetallic(float3(1.0, 0.0, 0.0));
        case 19: return Preset_Pearl();
        default: return MaterialExtended::Init();
    }
}

// Interpolate between two presets
MaterialExtended InterpolatePresets(int presetA, int presetB, float t)
{
    MaterialExtended a = GetMaterialPreset(presetA);
    MaterialExtended b = GetMaterialPreset(presetB);
    return MaterialExtended::lerp(a, b, saturate(t));
}

#endif /* MATERIAL_PRESETS_HLSL */
