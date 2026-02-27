//=========================================================================================================================
// Skin Shader - Using Disney BRDF with Subsurface Scattering
//=========================================================================================================================
// Realistic human skin shading with subsurface scattering approximation
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
    float3 g_flSubsurfaceColorDefault < Default3(1.0, 0.7, 0.6); UiType(Color); UiGroup("Subsurface,20/30"); > ;
    
    // Specular
    float g_flSpecularWeight < Default(0.5); Range(0.0, 1.0); UiGroup("Specular,30/10"); > ;
    float g_flSpecularRoughness < Default(0.4); Range(0.0, 1.0); UiGroup("Specular,30/20"); > ;

    //=========================================================================================================================
    // Main Pixel Shader
    //=========================================================================================================================
    float4 MainPs(PixelInput i) : SV_Target0
    {
        Material m = Material::From(i);
        
        // Sample textures
        float4 vColor = g_tColor.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vNormalTs = g_tNormal.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vRMA = g_tRma.Sample(TextureFiltering, i.vTextureCoords.xy);
        float3 vTintColor = g_flSkinTint * i.vVertexColor.rgb * g_flTintStrength;
        
        // Local subsurface color variable
        float3 subsurfaceColor = g_flSubsurfaceColorDefault;
        
        // Setup skin material
        m.Albedo = vColor.rgb * vTintColor;
        m.Opacity = vColor.a;
        m.Metalness = 0; // Skin is non-metallic
        m.Roughness = vRMA.r;
        m.AmbientOcclusion = vRMA.b;
        m.Normal = TransformNormal(DecodeNormal(vNormalTs.xyz), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        // Apply subsurface color based on skin type
        #if (S_SKIN_TYPE == 0) // Fair
            m.Albedo = lerp(m.Albedo, float3(0.9, 0.75, 0.65), 0.3);
            subsurfaceColor = float3(1.0, 0.6, 0.5);
        #elif (S_SKIN_TYPE == 1) // Medium
            m.Albedo = lerp(m.Albedo, float3(0.8, 0.6, 0.5), 0.3);
            subsurfaceColor = float3(0.95, 0.55, 0.45);
        #elif (S_SKIN_TYPE == 2) // Dark
            m.Albedo = lerp(m.Albedo, float3(0.5, 0.35, 0.28), 0.3);
            subsurfaceColor = float3(0.85, 0.45, 0.38);
        #elif (S_SKIN_TYPE == 3) // Asian
            m.Albedo = lerp(m.Albedo, float3(0.85, 0.65, 0.55), 0.3);
            subsurfaceColor = float3(0.95, 0.58, 0.48);
        #elif (S_SKIN_TYPE == 4) // African
            m.Albedo = lerp(m.Albedo, float3(0.5, 0.35, 0.28), 0.3);
            subsurfaceColor = float3(0.85, 0.45, 0.38);
        #endif
        
        // Apply subsurface parameters
        m.Transmission = subsurfaceColor * g_flSubsurfaceStrength;
        m.Roughness = lerp(m.Roughness, g_flSpecularRoughness, 0.5);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), m.Roughness, 0.04).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, m.Roughness, 1.0);
        }
        #endif
        
        // Shade with standard model (subsurface is handled via transmission)
        float4 color = ShadingModelStandard::Shade(i, m);
        
        // Tools visualization
        if (ToolsVis::WantsToolsVis())
        {
            color.rgb = m.Albedo;
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
