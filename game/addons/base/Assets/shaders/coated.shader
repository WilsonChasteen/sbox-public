//=========================================================================================================================
// Coated Material Shader - Using Disney BRDF with Clearcoat
//=========================================================================================================================
// Materials with a clear protective coating (car paint, varnished wood, lacquer)
// Supports: Multiple coat layers, metallic base, anisotropic coating
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
    Feature( F_COAT_QUALITY, 0..1( 0 = "High Quality (Full Clearcoat)", 1 = "Fast (Approximate)" ), "Quality");
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
    StaticCombo( S_COAT_TYPE, F_COAT_TYPE, Sys( ALL ) );
    StaticCombo( S_COAT_QUALITY, F_COAT_QUALITY, Sys( ALL ) );
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
    float g_flCoatAmount < Default(1.0); Range(0.0, 1.0); UiGroup("Clearcoat,20/10"); > ;
    float g_flCoatRoughness < Default(0.05); Range(0.0, 0.5); UiGroup("Clearcoat,20/20"); > ;
    float g_flCoatIOR < Default(1.5); Range(1.0, 2.0); UiGroup("Clearcoat,20/30"); > ;
    float g_flCoatThickness < Default(1.0); Range(0.0, 2.0); UiGroup("Clearcoat,20/40"); > ;
    
    // Coat color (for tinted clearcoats)
    float3 g_flCoatColor < Default3(1.0, 1.0, 1.0); UiType(Color); UiGroup("Clearcoat,20/50"); > ;
    float3 g_flCoatAbsorption < Default3(0.0, 0.0, 0.0); UiGroup("Clearcoat,20/60"); > ;
    
    // Anisotropy (for brushed metals)
    float g_flAnisotropy < Default(0.0); Range(0.0, 1.0); UiGroup("Anisotropy,30/10"); > ;
    float g_flAnisotropyRotation < Default(0.0); Range(0.0, 1.0); UiGroup("Anisotropy,30/20"); > ;
    
    // Flakes (for metallic paint)
    float g_flFlakeDensity < Default(0.0); Range(0.0, 1.0); UiGroup("Flakes,40/10"); > ;
    float g_flFlakeSize < Default(0.5); Range(0.0, 1.0); UiGroup("Flakes,40/20"); > ;
    float3 g_flFlakeColor < Default3(1.0, 1.0, 1.0); UiGroup("Flakes,40/30"); > ;
    
    // Aging/Weathering
    float g_flWeathering < Default(0.0); Range(0.0, 1.0); UiGroup("Weathering,50/10"); > ;
    float g_flScratches < Default(0.0); Range(0.0, 1.0); UiGroup("Weathering,50/20"); > ;

    //=========================================================================================================================
    // Helper Functions
    //=========================================================================================================================
    
    MaterialExtended GetCoatedMaterial(PixelInput i)
    {
        MaterialExtended m = MaterialExtended::FromBase(Material::Init(i));
        
        // Sample textures
        float4 vColor = g_tColor.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vNormalTs = g_tNormal.Sample(TextureFiltering, i.vTextureCoords.xy);
        float4 vRMA = g_tRma.Sample(TextureFiltering, i.vTextureCoords.xy);
        
        // Setup based on coat type
        if (S_COAT_TYPE == 0) // Car Paint
        {
            float metallic = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m = Preset_CarPaint(g_flBaseColor * vColor.rgb, metallic);
        }
        else if (S_COAT_TYPE == 1) // Varnished Wood
        {
            m = Preset_Wood(g_flBaseColor * vColor.rgb, g_flBaseRoughness);
            m.Coat = g_flCoatAmount;
            m.CoatRoughness = g_flCoatRoughness;
            m.CoatIOR = g_flCoatIOR;
        }
        else if (S_COAT_TYPE == 2) // Lacquer
        {
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m.Roughness = g_flBaseRoughness;
            m.Coat = g_flCoatAmount;
            m.CoatRoughness = g_flCoatRoughness * 0.5; // Lacquer is smoother
            m.CoatIOR = 1.6; // Higher IOR for lacquer
        }
        else if (S_COAT_TYPE == 3) // Ceramic Coating
        {
            m.Albedo = g_flBaseColor * vColor.rgb;
            m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : 0.0;
            m.Roughness = g_flBaseRoughness;
            m.Coat = g_flCoatAmount;
            m.CoatRoughness = 0.02; // Very smooth
            m.CoatIOR = 1.7; // Ceramic has higher IOR
        }
        
        // Override with texture values
        m.Albedo = g_flBaseColor * vColor.rgb;
        m.Opacity = vColor.a;
        m.Roughness = vRMA.r * g_flBaseRoughness;
        m.Metalness = S_BASE_TYPE == 0 ? g_flMetallic : vRMA.g;
        
        // Apply coat parameters
        m.Coat = g_flCoatAmount;
        m.CoatRoughness = g_flCoatRoughness;
        m.CoatIOR = g_flCoatIOR;
        
        // Apply anisotropy
        m.Anisotropy = g_flAnisotropy;
        m.AnisotropyRotation = g_flAnisotropyRotation;
        
        // Apply coat color/absorption
        m.AbsorptionCoefficient = g_flCoatAbsorption * g_flCoatThickness;
        
        // Weathering effects
        if (g_flWeathering > 0.0)
        {
            // Reduce coat amount with weathering
            m.Coat *= (1.0 - g_flWeathering);
            m.CoatRoughness *= (1.0 + g_flWeathering);
            
            // Add some surface discoloration
            m.Albedo = lerp(m.Albedo, m.Albedo * 0.8, g_flWeathering * 0.3);
        }
        
        // Transform normal
        m.Normal = TransformNormal(DecodeNormal(vNormalTs.xyz), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        m.WorldTangentU = i.vTangentUWs;
        m.WorldTangentV = i.vTangentVWs;
        m.LightmapUV = i.vLightmapUV;
        m.TextureCoords = i.vTextureCoords.xy;
        
        return m;
    }

    // Add metallic flakes to material (simplified screen-space approximation)
    float3 AddMetallicFlakes(float3 baseColor, float2 uv, float3 viewDir, float3 normal)
    {
        if (g_flFlakeDensity <= 0.0)
            return baseColor;
        
        // Procedural flake pattern (in production, use noise texture)
        float2 flakeUV = uv * 100.0 * (1.0 / g_flFlakeSize);
        float flakeNoise = frac(sin(dot(flakeUV, float2(12.9898, 78.233))) * 43758.5453);
        
        // Flake specular highlight
        float3 halfDir = normalize(viewDir + float3(0, 0, 1)); // Simplified light dir
        float NdotH = max(dot(normal, halfDir), 0.0);
        float flakeSpec = pow(NdotH, 500.0 * (1.0 - g_flFlakeSize));
        
        // Add flakes where noise threshold is met
        float flakeMask = step(1.0 - g_flFlakeDensity, flakeNoise);
        baseColor += g_flFlakeColor * flakeSpec * flakeMask;
        
        return baseColor;
    }

    //=========================================================================================================================
    // Main Pixel Shader
    //=========================================================================================================================
    float4 MainPs(PixelInput i) : SV_Target0
    {
        MaterialExtended m = GetCoatedMaterial(i);
        
        // Depth pass
        #if S_MODE_DEPTH
        {
            float flOpacity = CalcBRDFReflectionFactor(dot(-i.vNormalWs.xyz, g_vCameraDirWs.xyz), m.CoatRoughness, ComputeF0FromIOR(m.CoatIOR).r).x;
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return DepthNormals::Output(m.Normal, min(m.Roughness, m.CoatRoughness), 1.0);
        }
        #endif
        
        // Compute view direction
        float3 V = normalize(g_vCameraPositionWs.xyz - m.WorldPosition.xyz);
        
        // Add metallic flakes to emission (simplified)
        if (g_flFlakeDensity > 0.0)
        {
            m.Emission += AddMetallicFlakes(float3(0,0,0), m.TextureCoords.xy, V, m.Normal);
        }
        
        // Shade with layered BRDF
        float4 color;
        
        #if (S_COAT_QUALITY == 0)
            // High quality - Full layered BRDF with clearcoat
            color = ShadingModelLayered::ShadeClearcoat(m, m.Coat, m.CoatRoughness, m.CoatIOR);
        #else
            // Fast - Simplified clearcoat approximation
            // Use standard PBR and add clearcoat Fresnel
            color = ShadingModelPBR::Shade(m);
            
            // Add approximate clearcoat
            float3 coatF0 = ComputeF0FromIOR(m.CoatIOR);
            float NdotV = max(dot(m.Normal, V), 0.0);
            float coatFresnel = coatF0 + (1.0 - coatF0) * SchlickFresnel(NdotV);
            color.rgb += coatFresnel * m.Coat;
        #endif
        
        // Tools visualization
        if (ToolsVis::WantsToolsVis())
        {
            LightingTerms_t lightingTerms = InitLightingTerms();
            lightingTerms.vDiffuse = m.Albedo;
            lightingTerms.vSpecular = float3(m.Coat, m.Coat, m.Coat);
            
            ToolsVis toolVis = ToolsVis::Init(color, lightingTerms.vDiffuse, lightingTerms.vSpecular,
                                              lightingTerms.vDiffuse, lightingTerms.vSpecular, float3(0, 0, 0));
            
            toolVis.HandleAlbedo(color, m.Albedo);
            toolVis.HandleNormalWs(color, m.Normal);
            toolVis.HandleRoughness(color, float2(m.Roughness, m.CoatRoughness));
            
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
