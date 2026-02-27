//=========================================================================================================================
// Skin Shader - Using Disney BRDF with Subsurface Scattering
//=========================================================================================================================
// Realistic human skin shading with epidermis/dermis layers
// Supports: All skin tones, subsurface scattering, specular control
//=========================================================================================================================
HEADER
{
    Description = "Realistic Skin Shader with Subsurface Scattering";
    Version = 1;
}

//=========================================================================================================================
FEATURES
{
    #include "common/features.hlsl"
    Feature( F_SKIN_TYPE, 0..4( 0 = "Fair", 1 = "Medium", 2 = "Dark", 3 = "Asian", 4 = "African" ), "Skin Type");
    Feature( F_SKIN_QUALITY, 0..1( 0 = "High Quality (Full SSS)", 1 = "Fast (Approximate SSS)" ), "Quality");
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
        return FinalizeVertex(o);
    }
}

//=========================================================================================================================

PS
{
    // Combos
    StaticCombo( S_SKIN_TYPE, F_SKIN_TYPE, Sys( ALL ) );
    StaticCombo( S_SKIN_QUALITY, F_SKIN_QUALITY, Sys( ALL ) );
    StaticCombo( S_MODE_DEPTH, 0..1, Sys(ALL) );

    // Attributes
    #include "common/utils/Material.CommonInputs.hlsl"
    #include "common/pixel.hlsl"
    #include "common/classes/Depth.hlsl"

    //=========================================================================================================================
    // Skin Parameters
    //=========================================================================================================================
    
    // Base color tint
    float3 g_flSkinTint < Default3(1.0, 1.0, 1.0); UiType(Color); UiGroup("Skin,10/10"); > ;
    float g_flTintStrength < Default(1.0); Range(0.0, 2.0); UiGroup("Skin,10/20"); > ;
    
    // Subsurface scattering
    float g_flSubsurfaceStrength < Default(0.7); Range(0.0, 1.0); UiGroup("Subsurface,20/10"); > ;
    float g_flSubsurfaceThickness < Default(0.5); Range(0.0, 2.0); UiGroup("Subsurface,20/20"); > ;
    float3 g_flSubsurfaceColor < Default3(1.0, 0.7, 0.6); UiType(Color); UiGroup("Subsurface,20/30"); > ;
    
    // Specular
    float g_flSpecularWeight < Default(0.5); Range(0.0, 1.0); UiGroup("Specular,30/10"); > ;
    float g_flSpecularRoughness < Default(0.4); Range(0.0, 1.0); UiGroup("Specular,30/20"); > ;
    float3 g_flSpecularTint < Default3(1.0, 1.0, 1.0); UiType(Color); UiGroup("Specular,30/30"); > ;
    
    // Detail
    float g_flDetailNormalScale < Default(1.0); Range(0.0, 2.0); UiGroup("Detail,40/10"); > ;
    float g_flRoughnessVariation < Default(0.2); Range(0.0, 1.0); UiGroup("Detail,40/20"); > ;
    
    // Blood flow (for dynamic reddening)
    float g_flBloodFlow < Default(0.0); Range(0.0, 1.0); UiGroup("Advanced,50/10"); > ;

    //=========================================================================================================================
    // Helper Functions
    //=========================================================================================================================
    
    MaterialExtended GetSkinMaterial(PixelInput i)
    {
        MaterialExtended m = MaterialExtended::FromBase(Material::Init(i));
        
        // Sample textures
        float4 vColor = g_tColor.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vNormalTs = g_tNormal.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vRMA = g_tRma.Sample(TextureFiltering, i.vTextureCoords.xy);
        float3 vTintColor = g_flSkinTint * i.vVertexColor.rgb * g_flTintStrength;
        
        // Setup skin material using preset based on skin type
        m = Preset_Skin(S_SKIN_TYPE);
        
        // Apply sampled albedo
        m.Albedo = vColor.rgb * vTintColor;
        m.Opacity = vColor.a;
        
        // Apply roughness from texture with variation
        float baseRoughness = vRMA.r;
        m.Roughness = baseRoughness + g_flRoughnessVariation * (vColor.r - 0.5);
        m.Roughness = saturate(m.Roughness);
        
        // Apply subsurface parameters
        m.Subsurface = g_flSubsurfaceStrength;
        m.SubsurfaceThickness = g_flSubsurfaceThickness;
        m.SubsurfaceColor = g_flSubsurfaceColor;
        
        // Apply specular
        m.Specular = g_flSpecularWeight;
        m.SpecularTint = 0.0; // Skin has achromatic specular
        m.SpecularTint = length(g_flSpecularTint) > 0.01 ? 1.0 : 0.0;
        
        // Blood flow affects subsurface color (reddening)
        m.SubsurfaceColor = lerp(m.SubsurfaceColor, float3(1.0, 0.3, 0.3), g_flBloodFlow);
        
        // Transform normal
        m.Normal = TransformNormal(DecodeNormal(vNormalTs.xyz), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        // Apply detail normal if available
        #ifdef g_tNormalDetail
            float2 detailUV = i.vTextureCoords.xy * 2.0; // Tiled detail
            float4 vDetailNormal = g_tNormalDetail.Sample(TextureFiltering, detailUV);
            float3 detailNormalTs = DecodeNormal(vDetailNormal.xy);
            m.TangentNormal = detailNormalTs * g_flDetailNormalScale;
            m.Normal = TransformNormal(detailNormalTs, i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        #endif
        
        m.WorldTangentU = i.vTangentUWs;
        m.WorldTangentV = i.vTangentVWs;
        m.LightmapUV = i.vLightmapUV;
        m.TextureCoords = i.vTextureCoords.xy;
        
        return m;
    }

    //=========================================================================================================================
    // Main Pixel Shader
    //=========================================================================================================================
    float4 MainPs(PixelInput i) : SV_Target0
    {
        MaterialExtended m = GetSkinMaterial(i);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), m.Roughness, 0.04).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, m.Roughness, 1.0);
        }
        #endif
        
        // Shade with appropriate model based on quality
        float4 color;
        
        #if (S_SKIN_QUALITY == 0)
            // High quality - Full skin BRDF
            color = ShadingModelSkin::Shade(m, S_SKIN_TYPE);
        #else
            // Fast - Simplified skin BRDF
            color = ShadingModelSkin::ShadeSimple(m);
        #endif
        
        // Tools visualization
        if (ToolsVis::WantsToolsVis())
        {
            LightingTerms_t lightingTerms = InitLightingTerms();
            lightingTerms.vDiffuse = m.Albedo;
            lightingTerms.vSpecular = float3(m.Specular, m.Specular, m.Specular);
            
            ToolsVis toolVis = ToolsVis::Init(color, lightingTerms.vDiffuse, lightingTerms.vSpecular, 
                                              lightingTerms.vDiffuse, lightingTerms.vSpecular, float3(0,0,0));
            
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
