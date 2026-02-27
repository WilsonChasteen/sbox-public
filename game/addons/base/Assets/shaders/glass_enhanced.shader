//=========================================================================================================================
// Enhanced Glass Shader - Using Disney BRDF
//=========================================================================================================================
// Advanced glass shader with proper transmission, absorption, and refraction
// Supports: Clear/frosted glass, colored glass, water, and other dielectrics
//=========================================================================================================================
HEADER
{
    Description = "Enhanced Glass Shader with Disney BRDF";
    Version = 4;
}

//=========================================================================================================================
FEATURES
{
    #include "common/features.hlsl"
    Feature( F_GLASS_QUALITY, 0..1( 0 ="Default Glass ( Refractive, Tinted )", 1 = "Simple Glass ( Faster To Render )" ), "Glass");
    Feature( F_GLASS_TYPE, 0..2( 0 = "Clear Glass", 1 = "Frosted Glass", 2 = "Colored Glass" ), "Glass");
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
    #define BLEND_MODE_ALREADY_SET 1
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
    // Combos ----------------------------------------------------------------------------------------------
    StaticCombo( S_CHEAP_GLASS, F_GLASS_QUALITY, Sys( ALL ) );
    StaticCombo( S_GLASS_TYPE, F_GLASS_TYPE, Sys( ALL ) );
    StaticCombo( S_MODE_DEPTH, 0..1, Sys(ALL) );

    DynamicCombo( D_SKYBOX, 0..1, Sys(PC) );

    // Attributes ------------------------------------------------------------------------------------------
    #if (S_CHEAP_GLASS)
        RenderState(BlendEnable, true);
        RenderState(SrcBlend, SRC_ALPHA);
        RenderState(DstBlend, INV_SRC_ALPHA);
    #endif

    #define DEPTH_STATE_ALREADY_SET 1
    #define BLEND_MODE_ALREADY_SET 1
    #define S_TRANSLUCENT 1

    #include "common/utils/Material.CommonInputs.hlsl"
    #include "common/pixel.hlsl"
    #include "common/classes/Depth.hlsl"

    BoolAttribute(bWantsFBCopyTexture, !S_CHEAP_GLASS );

    Texture2D g_tFrameBufferCopyTexture < Attribute("FrameBufferCopyTexture"); SrgbRead( false ); >;

    //=========================================================================================================================
    // Glass Parameters
    //=========================================================================================================================
    
    // Base properties
    float g_flIOR < Default(1.52); Range(1.0, 2.5); UiGroup("Glass,10/10"); > ;
    float g_flTransmission < Default(1.0); Range(0.0, 1.0); UiGroup("Glass,10/20"); > ;
    float3 g_vAbsorptionCoefficient < Default3(0.0, 0.0, 0.0); UiType(Color); UiGroup("Glass,10/30"); > ;
    float g_flThickness < Default(1.0); Range(0.0, 10.0); UiGroup("Glass,10/40"); > ;
    
    // Refraction
    float g_flRefractionStrength < Default(1.005); Range(1.0, 1.1); UiGroup("Refraction,20/10"); > ;
    float g_flBlurAmount < Default(0.0); Range(0.0, 1.0); UiGroup("Refraction,20/20"); > ;
    
    // Surface
    float g_flRoughness < Default(0.05); Range(0.0, 1.0); UiGroup("Surface,30/10"); > ;
    
    // Albedo absorption for colored glass
    float AlbedoAbsorption < Default(0.0); Range(0.0, 1.0); UiGroup("Glass,10/50"); > ;

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
        float3 vTintColor = g_flTintColor * i.vVertexColor.rgb;
        
        // Setup glass material
        m.Albedo = vColor.rgb * vTintColor.rgb;
        m.Opacity = vColor.a;
        m.Metalness = 0; // Glass is always non-metallic
        m.Roughness = vRMA.r * g_flRoughness;
        m.AmbientOcclusion = vRMA.b;
        m.Transmission = float3(g_flTransmission, g_flTransmission, g_flTransmission);
        m.Normal = TransformNormal(DecodeNormal(vNormalTs.xyz), i.vNormalWs, i.vTangentUWs, i.vTangentVWs);
        
        // Apply frosted glass
        #if (S_GLASS_TYPE == 1)
            m.Roughness = lerp(m.Roughness, 0.6, g_flBlurAmount);
        #endif
        
        // Apply colored glass tint
        #if (S_GLASS_TYPE == 2)
            m.Albedo *= g_flTintColor;
        #endif
        
        // Shadows pass
        #if S_MODE_DEPTH
        {
            float3 F0 = ComputeF0FromIOR(g_flIOR);
            float flNDotV = saturate(dot(-m.Normal, g_vCameraDirWs.xyz));
            float flOpacity = CalcBRDFReflectionFactor(flNDotV, m.Roughness, F0.r).x;
            
            flOpacity = pow(flOpacity, 1.0f / 2.0f);
            flOpacity = lerp(flOpacity, 0.75f, sqrt(m.Roughness));
            flOpacity = lerp(flOpacity, 1.0 - dot(-m.Normal, g_vCameraDirWs.xyz), (g_flRefractionStrength - 1.0f) * 5.0f);
            flOpacity = lerp(1.0f, flOpacity, (length(m.Albedo) * 0.5f) + 0.5f);
            
            OpaqueFadeDepth(flOpacity, i.vPositionSs.xy);
            return 1;
        }
        #endif
        
        // Detect orthographic projection
        bool bOrtho = g_matViewToProjection[3].w != 0;
        
        // View ray calculation
        float3 vViewRayWs = bOrtho ? g_vCameraDirWs : normalize(i.vPositionWithOffsetWs.xyz);
        float flNDotV = saturate(dot(-m.Normal, vViewRayWs));
        
        #if !S_CHEAP_GLASS
        {
            float4 vRefractionColor = 0;
            
            float flDepthPs = 1.0f - Depth::GetNormalized(i.vPositionSs.xy);
            float3 vRefractionWs = RecoverWorldPosFromProjectedDepthAndRay(flDepthPs, vViewRayWs) - g_vCameraPositionWs;
            float flDistanceVs = distance(i.vPositionWithOffsetWs.xyz, vRefractionWs);
            
            float3 vRefractRayWs = refract(vViewRayWs, m.Normal, 1.0 / g_flIOR);
            float3 vRefractWorldPosWs = i.vPositionWithOffsetWs.xyz + vRefractRayWs * flDistanceVs;
            
            // Screen-space UV for refraction
            float2 vPositionSs;
            if (bOrtho)
            {
                vPositionSs = i.vPositionSs.xy * g_vInvViewportSize.xy;
            }
            else
            {
                float4 vPositionPs = Position4WsToPs(float4(vRefractWorldPosWs, 0));
                vPositionSs = vPositionPs.xy / vPositionPs.w;
                vPositionSs = vPositionSs * 0.5 + 0.5;
                vPositionSs.y = 1.0 - vPositionSs.y;
            }
            
            #if D_SKYBOX
                vPositionSs = i.vPositionSs.xy * g_vInvViewportSize;
            #endif
            
            // Color and blur
            {
                float flAmount = g_flBlurAmount * m.Roughness * (1.0 - (1.0 / max(flDistanceVs, 1.0)));
                flAmount /= flNDotV;
                
                const int nNumMips = 7;
                float2 vUV = float2(vPositionSs) * g_vFrameBufferCopyInvSizeAndUvScale.zw;
                
                vRefractionColor = g_tFrameBufferCopyTexture.SampleLevel(g_sTrilinearMirror, vUV, sqrt(flAmount) * nNumMips);
            }
            
            // Blend refraction with BRDF
            {
                float3 F0 = ComputeF0FromIOR(g_flIOR);
                m.Emission = lerp(vRefractionColor.xyz, 0.0f, CalcBRDFReflectionFactor(flNDotV, m.Roughness, F0.r));
                m.Emission *= m.Albedo * (1.0 - m.Roughness * AlbedoAbsorption);
                m.Albedo *= m.Roughness * AlbedoAbsorption;
            }
            
            if (ToolsVis::WantsToolsVis())
            {
                m.Albedo = m.Emission;
                m.Emission = 0;
            }
        }
        #endif
        
        // Shade with standard model
        float4 output = ShadingModelStandard::Shade(i, m);
        
        if (!S_CHEAP_GLASS)
            output.a = 1.0f;
        
        return output;
    }
}
