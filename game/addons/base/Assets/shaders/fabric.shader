//=========================================================================================================================
// Fabric Shader - Using Disney BRDF with Sheen
//=========================================================================================================================
// Specialized shading for cloth, velvet, silk, and other fabrics
// Supports: Anisotropic sheen, Oren-Nayar diffuse, fiber direction
//=========================================================================================================================
HEADER
{
    Description = "Fabric Shader with Anisotropic Sheen";
    Version = 1;
}

//=========================================================================================================================
FEATURES
{
    #include "common/features.hlsl"
    Feature( F_FABRIC_TYPE, 0..3( 0 = "Cotton", 1 = "Silk", 2 = "Velvet", 3 = "Leather" ), "Fabric Type");
    Feature( F_FABRIC_QUALITY, 0..1( 0 = "High Quality (Full Anisotropy)", 1 = "Fast (Isotropic)" ), "Quality");
}

//=========================================================================================================================
MODES
{
    Forward();
    ToolsShadingComplexity("tools_shading_complexity.shader");
    Depth( S_MODE_DEPTH );
}

//=========================================================================================================================
COMMON
{
    #include "common/shared.hlsl"
    #include "common/BRDF.hlsl"
    #include "common/BRDF_Extended.hlsl"
    #include "common/BRDF_Material.hlsl"
    #include "common/BRDF_ShadingModels.hlsl"
}

//=========================================================================================================================

struct VertexInput
{
    #include "common/vertexinput.hlsl"
};

//=========================================================================================================================

struct PixelInput
{
    #include "common/pixelinput.hlsl"
};

//=========================================================================================================================

VS
{
    #include "common/vertex.hlsl"
    
    PixelInput MainVs(VS_INPUT i)
    {
        PixelInput o = ProcessVertex(i);
        
        // Pass fabric direction through vertex colors or UVs if needed
        // For now, we'll compute it in pixel shader from tangents
        
        return FinalizeVertex(o);
    }
}

//=========================================================================================================================

PS
{
    // Combos
    StaticCombo( S_FABRIC_TYPE, F_FABRIC_TYPE, Sys( ALL ) );
    StaticCombo( S_FABRIC_QUALITY, F_FABRIC_QUALITY, Sys( ALL ) );
    StaticCombo( S_MODE_DEPTH, 0..1, Sys(ALL) );

    // Attributes
    #include "common/utils/Material.CommonInputs.hlsl"
    #include "common/pixel.hlsl"
    #include "common/classes/Depth.hlsl"

    //=========================================================================================================================
    // Fabric Parameters
    //=========================================================================================================================
    
    // Base color
    float3 g_flFabricTint < Default3(1.0, 1.0, 1.0); UiType(Color); UiGroup("Fabric,10/10"); > ;
    float g_flTintStrength < Default(1.0); Range(0.0, 2.0); UiGroup("Fabric,10/20"); > ;
    
    // Sheen
    float g_flSheenIntensity < Default(0.5); Range(0.0, 1.0); UiGroup("Sheen,20/10"); > ;
    float3 g_flSheenColor < Default3(1.0, 1.0, 1.0); UiType(Color); UiGroup("Sheen,20/20"); > ;
    float g_flSheenRoughness < Default(0.5); Range(0.0, 1.0); UiGroup("Sheen,20/30"); > ;
    
    // Anisotropy (fiber direction)
    float g_flAnisotropy < Default(0.5); Range(0.0, 1.0); UiGroup("Anisotropy,30/10"); > ;
    float g_flAnisotropyRotation < Default(0.0); Range(0.0, 1.0); UiGroup("Anisotropy,30/20"); > ;
    float2 g_vAnisotropyDirection < Default2(1.0, 0.0); UiGroup("Anisotropy,30/30"); > ;
    
    // Surface
    float g_flRoughness < Default(0.6); Range(0.0, 1.0); UiGroup("Surface,40/10"); > ;
    float g_flNormalScale < Default(1.0); Range(0.0, 2.0); UiGroup("Surface,40/20"); > ;
    
    // Velvet-specific
    float g_flVelvetSoftness < Default(0.8); Range(0.0, 1.0); UiGroup("Velvet,50/10"); > ;

    //=========================================================================================================================
    // Helper Functions
    //=========================================================================================================================
    
    MaterialExtended GetFabricMaterial(PixelInput i)
    {
        MaterialExtended m = MaterialExtended::FromBase(Material::Init(i));
        
        // Sample textures
        float4 vColor = g_tColor.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vNormalTs = g_tNormal.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vRMA = g_tRma.Sample(TextureFiltering, i.vTextureCoords.xy);
        float3 vTintColor = g_flFabricTint * i.vVertexColor.rgb * g_flTintStrength;
        
        // Setup based on fabric type
        if (S_FABRIC_TYPE == 0) // Cotton
        {
            m = Preset_Cotton(vColor.rgb * vTintColor);
        }
        else if (S_FABRIC_TYPE == 1) // Silk
        {
            m = Preset_Silk(vColor.rgb * vTintColor);
        }
        else if (S_FABRIC_TYPE == 2) // Velvet
        {
            m = Preset_Velvet(vColor.rgb * vTintColor);
            m.Sheen *= g_flVelvetSoftness;
        }
        else if (S_FABRIC_TYPE == 3) // Leather
        {
            m = Preset_Leather(vColor.rgb * vTintColor, g_flRoughness);
        }
        
        // Override with texture values
        m.Albedo = vColor.rgb * vTintColor;
        m.Opacity = vColor.a;
        m.Roughness = vRMA.r * g_flRoughness;
        
        // Apply sheen parameters
        m.Sheen = g_flSheenIntensity;
        m.SheenColor = g_flSheenColor;
        m.SheenRoughness = g_flSheenRoughness;
        
        // Apply anisotropy
        m.Anisotropy = g_flAnisotropy;
        m.AnisotropyRotation = g_flAnisotropyRotation;
        m.AnisotropyDirection = float3(g_vAnisotropyDirection, 0.0);
        
        // Transform normal
        float3 normalScale = float3(g_flNormalScale, g_flNormalScale, 1.0);
        float3 normalTs = DecodeNormal(vNormalTs.xyz) * normalScale;
        m.Normal = TransformNormal(normalize(normalTs), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        m.WorldTangentU = i.vTangentUWs;
        m.WorldTangentV = i.vTangentVWs;
        m.LightmapUV = i.vLightmapUV;
        m.TextureCoords = i.vTextureCoords.xy;
        
        return m;
    }

    // Compute fabric direction from vertex tangents and anisotropy rotation
    float3 ComputeFabricDirection(float3 tangentU, float3 tangentV, float rotation)
    {
        float c = cos(rotation * 2.0 * BRDF_PI);
        float s = sin(rotation * 2.0 * BRDF_PI);
        return normalize(tangentU * c + tangentV * s);
    }

    //=========================================================================================================================
    // Main Pixel Shader
    //=========================================================================================================================
    float4 MainPs(PixelInput i) : SV_Target0
    {
        MaterialExtended m = GetFabricMaterial(i);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), m.Roughness, 0.04).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, m.Roughness, 1.0);
        }
        #endif
        
        // Compute fabric direction
        float3 fabricDir = ComputeFabricDirection(i.vTangentUWs, i.vTangentVWs, m.AnisotropyRotation);
        
        // Shade with appropriate model based on quality
        float4 color;
        
        #if (S_FABRIC_QUALITY == 0)
            // High quality - Full fabric BRDF with anisotropy
            color = ShadingModelFabric::Shade(m);
        #else
            // Fast - Simplified cloth BRDF
            color = ShadingModelFabric::ShadeSimple(m);
        #endif
        
        // Tools visualization
        if (ToolsVis::WantsToolsVis())
        {
            LightingTerms_t lightingTerms = InitLightingTerms();
            lightingTerms.vDiffuse = m.Albedo;
            lightingTerms.vSpecular = float3(m.Sheen, m.Sheen, m.Sheen);
            
            ToolsVis toolVis = ToolsVis::Init(color, lightingTerms.vDiffuse, lightingTerms.vSpecular,
                                              lightingTerms.vDiffuse, lightingTerms.vSpecular, float3(0, 0, 0));
            
            toolVis.HandleAlbedo(color, m.Albedo);
            toolVis.HandleNormalWs(color, m.Normal);
            toolVis.HandleRoughness(color, float2(m.Roughness, m.Roughness));
            
            color.rgb = saturate(color.rgb);
            return color;
        }
        
        // Wireframe
        if (g_bWireframeMode)
            return g_vWireframeColor;
        
        // Atmospherics
        color = DoAtmospherics(m.WorldPosition, m.ScreenPosition.xy, color, false);
        
        return color;
    }
}
