//=========================================================================================================================
// Coated Material Shader - Using Disney BRDF with Clearcoat
//=========================================================================================================================
// Materials with a clear protective coating (car paint, varnished wood, lacquer)
// Supports: Metallic base, clearcoat layer
//=========================================================================================================================
HEADER
{
    Description = "Coated Material Shader with Clearcoat";
    Version = 1;
}

//=========================================================================================================================
FEATURES
{
    #include "common/features.hlsl"
    Feature( F_COAT_TYPE, 0..3( 0 = "Car Paint", 1 = "Varnished Wood", 2 = "Lacquer", 3 = "Ceramic Coating" ), "Coat Type");
    Feature( F_BASE_TYPE, 0..1( 0 = "Metallic", 1 = "Non-Metallic" ), "Base");
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
    StaticCombo( S_COAT_TYPE, F_COAT_TYPE, Sys( ALL ) );
    StaticCombo( S_BASE_TYPE, F_BASE_TYPE, Sys( ALL ) );
    StaticCombo( S_MODE_DEPTH, 0..1, Sys(ALL) );

    // Attributes
    #include "common/utils/Material.CommonInputs.hlsl"
    #include "common/pixel.hlsl"
    #include "common/classes/Depth.hlsl"

    //=========================================================================================================================
    // Coated Material Parameters
    //=========================================================================================================================
    
    // Base color
    float3 g_flBaseColor < Default3(1.0, 0.0, 0.0); UiType(Color); UiGroup("Base,10/10"); > ;
    float g_flMetallic < Default(0.8); Range(0.0, 1.0); UiGroup("Base,10/20"); > ;
    float g_flBaseRoughness < Default(0.2); Range(0.0, 1.0); UiGroup("Base,10/30"); > ;
    
    // Clearcoat
    float g_flCoatAmountDefault < Default(1.0); Range(0.0, 1.0); UiGroup("Clearcoat,20/10"); > ;
    float g_flCoatRoughnessDefault < Default(0.05); Range(0.0, 0.5); UiGroup("Clearcoat,20/20"); > ;
    float g_flCoatIORDefault < Default(1.5); Range(1.0, 2.0); UiGroup("Clearcoat,20/30"); > ;

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
        
        // Local coat variables
        float coatAmount = g_flCoatAmountDefault;
        float coatRoughness = g_flCoatRoughnessDefault;
        float coatIOR = g_flCoatIORDefault;
        
        // Setup based on coat type
        #if (S_COAT_TYPE == 0) // Car Paint
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m.Roughness = vRMA.r * g_flBaseRoughness;
            coatAmount = 1.0;
            coatRoughness = 0.05;
        #elif (S_COAT_TYPE == 1) // Varnished Wood
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = 0;
            m.Roughness = 0.6;
            coatAmount = 0.8;
            coatRoughness = 0.1;
        #elif (S_COAT_TYPE == 2) // Lacquer
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m.Roughness = vRMA.r * g_flBaseRoughness;
            coatAmount = 0.9;
            coatRoughness = 0.03;
            coatIOR = 1.6;
        #elif (S_COAT_TYPE == 3) // Ceramic Coating
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m.Roughness = vRMA.r * g_flBaseRoughness;
            coatAmount = 1.0;
            coatRoughness = 0.02;
            coatIOR = 1.7;
        #endif
        
        // Apply texture values
        m.Opacity = vColor.a;
        m.AmbientOcclusion = vRMA.b;
        
        // Clearcoat approximation using specular boost
        float3 F0 = ComputeF0FromIOR(coatIOR);
        float NdotV = saturate(dot(m.Normal, normalize(g_vCameraPositionWs.xyz - m.WorldPosition)));
        float coatFresnel = F0.r + (1.0 - F0.r) * SchlickFresnel(NdotV);
        m.Emission = float3(coatFresnel * coatAmount * 0.3, coatFresnel * coatAmount * 0.3, coatFresnel * coatAmount * 0.3);
        
        // Transform normal
        m.Normal = TransformNormal(DecodeNormal(vNormalTs.xyz), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), min(m.Roughness, coatRoughness), F0.r).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, min(m.Roughness, coatRoughness), 1.0);
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
