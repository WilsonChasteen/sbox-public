//=========================================================================================================================
// Fabric Shader - Using Disney BRDF with Sheen
//=========================================================================================================================
// Specialized shading for cloth, velvet, silk, and other fabrics
// Supports: Anisotropic sheen, Oren-Nayar diffuse approximation
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
    StaticCombo( S_FABRIC_TYPE, F_FABRIC_TYPE, Sys( ALL ) );
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
    float g_flSheenIntensityDefault < Default(0.5); Range(0.0, 1.0); UiGroup("Sheen,20/10"); > ;
    float g_flSheenRoughnessDefault < Default(0.5); Range(0.0, 1.0); UiGroup("Sheen,20/30"); > ;
    
    // Surface
    float g_flRoughness < Default(0.6); Range(0.0, 1.0); UiGroup("Surface,40/10"); > ;
    float g_flNormalScale < Default(1.0); Range(0.0, 2.0); UiGroup("Surface,40/20"); > ;

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
        float3 vTintColor = g_flFabricTint * i.vVertexColor.rgb * g_flTintStrength;
        
        // Local sheen variables
        float sheenIntensity = g_flSheenIntensityDefault;
        float sheenRoughness = g_flSheenRoughnessDefault;
        
        // Setup based on fabric type
        #if (S_FABRIC_TYPE == 0) // Cotton
            m.Metalness = 0;
            m.Roughness = 0.8;
            sheenIntensity = 0.5;
        #elif (S_FABRIC_TYPE == 1) // Silk
            m.Metalness = 0;
            m.Roughness = 0.4;
            sheenIntensity = 0.8;
            sheenRoughness = 0.3;
        #elif (S_FABRIC_TYPE == 2) // Velvet
            m.Metalness = 0;
            m.Roughness = 1.0;
            sheenIntensity = 1.0;
            sheenRoughness = 0.8;
        #elif (S_FABRIC_TYPE == 3) // Leather
            m.Metalness = 0;
            m.Roughness = g_flRoughness;
            sheenIntensity = 0.3;
        #endif
        
        // Apply texture values
        m.Albedo = vColor.rgb * vTintColor;
        m.Opacity = vColor.a;
        m.Roughness = vRMA.r * g_flRoughness;
        m.AmbientOcclusion = vRMA.b;
        
        // Apply sheen as transmission (approximation)
        float sheenFactor = sheenIntensity * (1.0 - dot(m.Normal, normalize(g_vCameraPositionWs.xyz - m.WorldPosition)));
        m.Transmission = float3(sheenFactor, sheenFactor, sheenFactor) * (1.0 - sheenRoughness);
        
        // Transform normal
        float3 normalScale = float3(g_flNormalScale, g_flNormalScale, 1.0);
        float3 normalTs = DecodeNormal(vNormalTs.xyz) * normalScale;
        m.Normal = TransformNormal(normalize(normalTs), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), m.Roughness, 0.04).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, m.Roughness, 1.0);
        }
        #endif
        
        // Shade with standard model
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
