#ifndef BRDF_SHADING_MODELS_HLSL
#define BRDF_SHADING_MODELS_HLSL

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Enhanced Shading Models for Disney BRDF
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// New shading models that leverage the enhanced BRDF system
// Includes: PBR, Layered, Skin, Fabric, Hair models
//
// These models replace and extend ShadingModelStandard with physically-based
// rendering using the full Disney BRDF parameter set.
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#include "common/shadingmodel.hlsl"
#include "common/BRDF.hlsl"
#include "common/BRDF_Extended.hlsl"
#include "common/BRDF_Material.hlsl"
#include "common/classes/Decals.hlsl"

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// ShadingModelPBR - Full Physically-Based Rendering
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Uses the complete Disney BRDF with all features enabled
// Best quality for general-purpose PBR materials

class ShadingModelPBR
{
    // Convert MaterialExtended to CombinerInput
    static CombinerInput MaterialToCombinerInput(MaterialExtended m)
    {
        CombinerInput o = PS_InitFinalCombiner();
        
        // Position and geometric data
        o.vPositionWithOffsetWs = m.WorldPositionWithOffset;
        o.vPositionWs = m.WorldPosition;
        o.vPositionSs = m.ScreenPosition;
        
        // Normal and tangent space
        o.vNormalWs = m.Normal;
        o.vNormalTs = NormalWorldToTangent(m.Normal, m.WorldTangentU, m.WorldTangentV);
        o.vTangentUWs = m.WorldTangentU;
        o.vTangentVWs = m.WorldTangentV;
        
        // Material properties
        o.vRoughness = m.Roughness.xx;
        o.vEmissive = m.Emission;
        o.flAmbientOcclusion = m.AmbientOcclusion;
        o.vTransmissiveMask = float3(m.Transmission, m.Transmission, m.Transmission);
        o.flOpacity = m.Opacity;
        
        // Lighting and UV coordinates
        o.vLightmapUV = m.LightmapUV;
        o.vTextureCoords = m.TextureCoords;
        
        // Adjustments
        o = CalculateDiffuseAndSpecularFromAlbedoAndMetalness(o, m.Albedo.rgb, m.Metalness);
        o.vRoughness.xy = AdjustRoughnessByGeometricNormal(o.vRoughness.xy, o.vNormalWs.xyz);
        
        return o;
    }
    
    // Shade a pixel using the full PBR model
    static float4 Shade(MaterialExtended m)
    {
        // Apply decals
        Decals::Apply(m.WorldPosition, ToBaseMaterial(m));
        
        // Alpha to coverage adjustment
        AdjustAlphaToCoverage(ToBaseMaterial(m));
        
        // Validate material parameters
        m.Validate();
        
        // Compute tangent frame for anisotropy
        float3 tangentX, tangentY;
        m.ComputeTangentFrame(tangentX, tangentY);
        
        // Lighting setup
        LightingTerms_t lightingTerms = InitLightingTerms();
        CombinerInput combinerInput = MaterialToCombinerInput(m);
        
        // Calculate direct and indirect lighting
        ComputeDirectLighting(lightingTerms, combinerInput);
        CalculateIndirectLighting(lightingTerms, combinerInput);
        
        // AO application
        float3 vDiffuseAO = CalculateDiffuseAmbientOcclusion(combinerInput, lightingTerms);
        lightingTerms.vIndirectDiffuse.rgb *= vDiffuseAO.rgb;
        lightingTerms.vDiffuse.rgb *= lerp(float3(1.0, 1.0, 1.0), vDiffuseAO.rgb, combinerInput.flAmbientOcclusionDirectDiffuse);
        
        float3 vSpecularAO = CalculateSpecularAmbientOcclusion(combinerInput, lightingTerms);
        lightingTerms.vIndirectSpecular.rgb *= vSpecularAO.rgb;
        lightingTerms.vSpecular.rgb *= lerp(float3(1.0, 1.0, 1.0), vSpecularAO.rgb, combinerInput.flAmbientOcclusionDirectSpecular);
        
        // Compute view direction
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        
        // Compute lighting direction (simplified - would need proper light loop in production)
        float3 L = normalize(g_vCameraDirWs.xyz); // Placeholder
        
        // Evaluate Disney BRDF
        float3 brdfResult = DisneyBRDFEnhanced(
            L, V, m.Normal, tangentX, tangentY,
            m.Albedo,
            m.Metalness,
            m.Subsurface,
            m.Specular,
            m.Roughness,
            m.SpecularTint,
            m.Anisotropy,
            m.Sheen,
            m.SheenRoughness, // Using SheenRoughness as sheenTint approximation
            m.Coat,
            m.CoatRoughness,
            m.CoatIOR,
            m.Transmission,
            m.Thickness,
            m.AbsorptionCoefficient,
            m.Iridescence,
            m.IridescenceIOR,
            m.IOR,
            m.UseOrenNayar
        );
        
        // Combine with lighting
        float3 vDiffuse = (lightingTerms.vDiffuse.rgb + lightingTerms.vIndirectDiffuse.rgb) * brdfResult;
        float3 vSpecular = lightingTerms.vSpecular.rgb + lightingTerms.vIndirectSpecular.rgb;
        
        // Add emission
        float3 finalColor = vDiffuse + vSpecular * m.Specular + m.Emission;
        
        float4 color = float4(finalColor, m.Opacity);
        
        // DepthNormals output
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        // Tools visualization
        if (ToolsVis::WantsToolsVis())
            return DoToolsVis(color, m, lightingTerms);
        
        // Wireframe mode
        if (g_bWireframeMode)
            return g_vWireframeColor;
        
        // Atmospherics
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
    
    // Tools visualization for PBR
    static float4 DoToolsVis(inout float4 color, MaterialExtended m, LightingTerms_t lightingTerms)
    {
        ToolsVis toolVis = ToolsVis::Init(color, lightingTerms.vDiffuse.rgb, lightingTerms.vSpecular.rgb, 
                                          lightingTerms.vIndirectDiffuse.rgb, lightingTerms.vIndirectSpecular.rgb, 
                                          lightingTerms.vTransmissive.rgb);
        
        toolVis.HandleFlatOverlayColor(m.Albedo, color);
        toolVis.HandleFullbright(color, m.Albedo, m.WorldPosition, m.Normal);
        toolVis.HandleDiffuseLighting(color);
        toolVis.HandleSpecularLighting(color);
        toolVis.HandleAlbedo(color, m.Albedo);
        toolVis.HandleRoughness(color, float2(m.Roughness, m.Roughness));
        toolVis.HandleNormalWs(color, m.Normal);
        
        // Disable bloom
        color.rgb = saturate(color.rgb);
        
        return color;
    }
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// ShadingModelLayered - Layered Material Composition
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Stack multiple BRDF layers for complex materials
// Examples: dirt on metal, paint on clearcoat, snow on ground

class ShadingModelLayered
{
    static float4 Shade(MaterialExtended topLayer, MaterialExtended bottomLayer, float blendAmount)
    {
        // Validate both materials
        topLayer.Validate();
        bottomLayer.Validate();
        
        // Compute tangent frames
        float3 tangentX1, tangentY1;
        topLayer.ComputeTangentFrame(tangentX1, tangentY1);
        
        float3 tangentX2, tangentY2;
        bottomLayer.ComputeTangentFrame(tangentX2, tangentY2);
        
        // View direction
        float3 V = normalize(g_vCameraPositionWs.xyz - topLayer.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz); // Placeholder
        
        // Evaluate both BRDFs
        float3 brdfTop = DisneyBRDFEnhanced(
            L, V, topLayer.Normal, tangentX1, tangentY1,
            topLayer.Albedo, topLayer.Metalness, topLayer.Subsurface,
            topLayer.Specular, topLayer.Roughness, topLayer.SpecularTint,
            topLayer.Anisotropy, topLayer.Sheen, topLayer.SheenRoughness,
            topLayer.Coat, topLayer.CoatRoughness, topLayer.CoatIOR,
            topLayer.Transmission, topLayer.Thickness, topLayer.AbsorptionCoefficient,
            topLayer.Iridescence, topLayer.IridescenceIOR, topLayer.IOR, topLayer.UseOrenNayar
        );
        
        float3 brdfBottom = DisneyBRDFEnhanced(
            L, V, bottomLayer.Normal, tangentX2, tangentY2,
            bottomLayer.Albedo, bottomLayer.Metalness, bottomLayer.Subsurface,
            bottomLayer.Specular, bottomLayer.Roughness, bottomLayer.SpecularTint,
            bottomLayer.Anisotropy, bottomLayer.Sheen, bottomLayer.SheenRoughness,
            bottomLayer.Coat, bottomLayer.CoatRoughness, bottomLayer.CoatIOR,
            bottomLayer.Transmission, bottomLayer.Thickness, bottomLayer.AbsorptionCoefficient,
            bottomLayer.Iridescence, bottomLayer.IridescenceIOR, bottomLayer.IOR, bottomLayer.UseOrenNayar
        );
        
        // Layer blending with absorption through top layer
        float3 transmission = exp(-topLayer.AbsorptionCoefficient * topLayer.Thickness);
        float3 result = lerp(brdfBottom, brdfTop, blendAmount);
        result *= (1.0 - transmission * blendAmount);
        
        // Add emission from both layers
        float3 emission = lerp(bottomLayer.Emission, topLayer.Emission, blendAmount);
        result += emission;
        
        float4 color = float4(result, lerp(bottomLayer.Opacity, topLayer.Opacity, blendAmount));
        
        // DepthNormals output
        if (DepthNormals::WantsDepthNormals())
        {
            float3 blendedNormal = normalize(lerp(bottomLayer.Normal, topLayer.Normal, blendAmount));
            float blendedRoughness = lerp(bottomLayer.Roughness, topLayer.Roughness, blendAmount);
            return DepthNormals::Output(blendedNormal, blendedRoughness, color.a);
        }
        
        // Atmospherics
        color = DoAtmospherics(topLayer.WorldPosition, topLayer.ScreenPosition.xy, color);
        
        return color;
    }
    
    // Convenience function for clearcoat over base
    static float4 ShadeClearcoat(MaterialExtended base, float coatAmount, float coatRoughness, float coatIOR)
    {
        MaterialExtended coatLayer = MaterialExtended::Init();
        coatLayer.Albedo = float3(1.0, 1.0, 1.0);
        coatLayer.Metalness = 0.0;
        coatLayer.Roughness = coatRoughness;
        coatLayer.Coat = coatAmount;
        coatLayer.CoatRoughness = coatRoughness;
        coatLayer.CoatIOR = coatIOR;
        coatLayer.WorldPosition = base.WorldPosition;
        coatLayer.Normal = base.Normal;
        
        return Shade(coatLayer, base, coatAmount);
    }
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// ShadingModelSkin - Specialized Skin Shading
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Optimized for realistic human skin rendering
// Uses subsurface scattering with epidermis/dermis layers

class ShadingModelSkin
{
    static float4 Shade(MaterialExtended m, int skinType)
    {
        // Setup skin-specific parameters
        SkinBRDFParams skinParams = GetSkinParams(skinType);
        
        // Override with material values where appropriate
        skinParams.roughness = m.Roughness;
        skinParams.specular_weight = m.Specular;
        skinParams.epidermis_albedo = m.Albedo;
        skinParams.dermis_albedo = m.SubsurfaceColor;
        skinParams.scattering_strength = m.Subsurface;
        
        // View and light directions
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz); // Placeholder
        
        // Evaluate skin BRDF
        float3 skinResult = SkinBRDF(L, V, m.Normal, skinParams);
        
        // Add emission (for self-illumination if needed)
        skinResult += m.Emission;
        
        float4 color = float4(skinResult, m.Opacity);
        
        // DepthNormals output
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        // Atmospherics
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
    
    // Simplified skin shader (faster)
    static float4 ShadeSimple(MaterialExtended m)
    {
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz);
        
        float3 skinResult = SkinBRDFSimplified(L, V, m.Normal, m.Albedo, m.Roughness, m.Subsurface);
        skinResult += m.Emission;
        
        float4 color = float4(skinResult, m.Opacity);
        
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// ShadingModelFabric - Specialized Cloth/Fabric Shading
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Optimized for velvet, silk, cotton, and other fabrics
// Uses anisotropic sheen and Oren-Nayar diffuse

class ShadingModelFabric
{
    static float4 Shade(MaterialExtended m)
    {
        // Setup fabric parameters
        FabricBRDFParams fabricParams;
        fabricParams.base_color = m.Albedo;
        fabricParams.roughness = m.Roughness;
        fabricParams.sheen_intensity = m.Sheen;
        fabricParams.sheen_color = m.SheenColor;
        fabricParams.anisotropy = m.Anisotropy;
        
        // Compute tangent frame
        float3 tangentX, tangentY;
        m.ComputeTangentFrame(tangentX, tangentY);
        
        // View and light directions
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz);
        
        // Evaluate fabric BRDF
        float3 fabricResult = FabricBRDF(L, V, m.Normal, tangentX, fabricParams);
        
        // Add emission
        fabricResult += m.Emission;
        
        float4 color = float4(fabricResult, m.Opacity);
        
        // DepthNormals output
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        // Atmospherics
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
    
    // Simplified cloth shader (faster)
    static float4 ShadeSimple(MaterialExtended m)
    {
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz);
        
        float3 clothResult = ClothBRDFSimplified(L, V, m.Normal, m.Albedo, m.Roughness, m.Sheen);
        clothResult += m.Emission;
        
        float4 color = float4(clothResult, m.Opacity);
        
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
};

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// ShadingModelHair - Specialized Hair Shading
//-------------------------------------------------------------------------------------------------------------------------------------------------------------
// Uses Marschner hair BRDF model with primary, secondary, and transmission lobes

class ShadingModelHair
{
    static float4 Shade(MaterialExtended m, float3 hairDir)
    {
        // Setup hair parameters from material
        HairBRDFParams hairParams = GetHairParams(0); // Default to black
        
        // Override with material values
        hairParams.roughness_longitudinal = m.Roughness;
        hairParams.roughness_azimuthal = m.Roughness * 2.0;
        hairParams.sigma_a = m.Albedo * 2.0; // Absorption based on color
        hairParams.specular_weight = m.Specular;
        
        // View and light directions
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz);
        
        // Evaluate hair BRDF
        float3 hairResult = HairBRDF(L, V, m.Normal, hairDir, hairParams);
        
        // Add emission
        hairResult += m.Emission;
        
        float4 color = float4(hairResult, m.Opacity);
        
        // DepthNormals output
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        // Atmospherics
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
    
    // Simplified anisotropic hair shader (faster)
    static float4 ShadeSimple(MaterialExtended m, float3 hairDir)
    {
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        float3 L = normalize(g_vCameraDirWs.xyz);
        
        float3 hairResult = HairBRDFSimplified(L, V, m.Normal, hairDir, m.Albedo, m.Roughness);
        hairResult += m.Emission;
        
        float4 color = float4(hairResult, m.Opacity);
        
        if (DepthNormals::WantsDepthNormals())
            return DepthNormals::Output(m.Normal, m.Roughness, color.a);
        
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color);
        
        return color;
    }
};

#endif /* BRDF_SHADING_MODELS_HLSL */
