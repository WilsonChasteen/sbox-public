#ifndef DAZZLE_LIGHTING_HLSL
#define DAZZLE_LIGHTING_HLSL

#include "common/classes/Bindless.hlsl"

enum DazzleQualityPreset
{
	DazzleQuality_Off = 0,
	DazzleQuality_Performance = 1,
	DazzleQuality_Balanced = 2,
	DazzleQuality_Cinematic = 3
};

bool Dazzle_Enabled < Attribute( "Dazzle_Enabled" ); Default( 0 ); >;
int Dazzle_Quality < Attribute( "Dazzle_Quality" ); Default( 2 ); >;
bool Dazzle_HasHardwareRT < Attribute( "Dazzle_HasHardwareRT" ); Default( 0 ); >;
bool Dazzle_IsVulkan < Attribute( "Dazzle_IsVulkan" ); Default( 0 ); >;
bool Dazzle_GIEnable < Attribute( "Dazzle_GIEnable" ); Default( 1 ); >;
bool Dazzle_GIValid < Attribute( "Dazzle_GIValid" ); Default( 0 ); >;
int Dazzle_GITextureIndex < Attribute( "Dazzle_GITextureIndex" ); Default( 0 ); >;
int Dazzle_GIDebugView < Attribute( "Dazzle_GIDebugView" ); Default( 0 ); >;
int Dazzle_GITraceFlags < Attribute( "Dazzle_GITraceFlags" ); Default( 0 ); >;
int Dazzle_GITraceFrame < Attribute( "Dazzle_GITraceFrame" ); Default( 0 ); >;
int Dazzle_GITraceNearIndex < Attribute( "Dazzle_GITraceNearIndex" ); Default( 0 ); >;
int Dazzle_GITraceFarIndex < Attribute( "Dazzle_GITraceFarIndex" ); Default( 0 ); >;
int Dazzle_GITraceHistoryIndex < Attribute( "Dazzle_GITraceHistoryIndex" ); Default( 0 ); >;
float Dazzle_DirectIntensity < Attribute( "Dazzle_DirectIntensity" ); Default( 1.0f ); >;
float Dazzle_IndirectIntensity < Attribute( "Dazzle_IndirectIntensity" ); Default( 1.0f ); >;
float Dazzle_Stability < Attribute( "Dazzle_Stability" ); Default( 0.90f ); >;
float Dazzle_FallbackStrength < Attribute( "Dazzle_FallbackStrength" ); Default( 0.80f ); >;
float Dazzle_DDGIBlend < Attribute( "Dazzle_DDGIBlend" ); Default( 1.0f ); >;
float Dazzle_GIBounceStrength < Attribute( "Dazzle_GIBounceStrength" ); Default( 0.75f ); >;

enum DazzleGIDebugView
{
	DazzleGIDebug_Off = 0,
	DazzleGIDebug_TraceState = 1,
	DazzleGIDebug_HistoryRadiance = 2,
	DazzleGIDebug_NearCascade = 3,
	DazzleGIDebug_FarCascade = 4
};

class DazzleLighting
{
	static bool IsEnabled()
	{
		return Dazzle_Enabled && Dazzle_Quality > DazzleQuality_Off;
	}

	static float QualityWeight()
	{
		switch ( Dazzle_Quality )
		{
			case DazzleQuality_Performance:
				return 0.65f;
			case DazzleQuality_Balanced:
				return 0.82f;
			case DazzleQuality_Cinematic:
				return 1.0f;
		}

		return 0.0f;
	}

	static float HardwareWeight()
	{
		float hardwareWeight = Dazzle_HasHardwareRT ? 1.0f : Dazzle_FallbackStrength;

		// DX11 fallback path gets a slightly safer budget.
		if ( !Dazzle_IsVulkan )
		{
			hardwareWeight = min( hardwareWeight, 0.9f );
		}

		return saturate( hardwareWeight );
	}

	static float StabilityWeight()
	{
		return saturate( Dazzle_Stability );
	}

	static bool IsGIDebugViewActive()
	{
		return IsEnabled() && Dazzle_GIDebugView != DazzleGIDebug_Off;
	}

	static float2 ScreenUv( float4 screenPosition )
	{
		return saturate( screenPosition.xy * g_vInvViewportSize.xy );
	}

	static float3 SampleBindlessTextureRgb( int textureIndex, float2 uv )
	{
		if ( textureIndex <= 0 )
		{
			return 0.0f;
		}

		Texture2D sourceTexture = Bindless::GetTexture2D( textureIndex );
		int2 dimensions = TextureDimensions2D( sourceTexture, 0 ).xy;
		int2 samplePixel = int2( uv * max( dimensions - 1, 1 ) );
		return sourceTexture.Load( int3( samplePixel, 0 ) ).rgb;
	}

	static float3 VisualizeRadiance( int textureIndex, float2 uv )
	{
		if ( textureIndex <= 0 )
		{
			return float3( 1.0f, 0.1f, 0.1f );
		}

		float3 radiance = SampleBindlessTextureRgb( textureIndex, uv );
		return saturate( 1.0f - exp( -radiance * 2.5f ) );
	}

	static float3 VisualizeTraceState( float2 uv )
	{
		const int TraceBit_AddLayers = 1 << 0;
		const int TraceBit_GIEnabled = 1 << 1;
		const int TraceBit_TexturesReady = 1 << 2;
		const int TraceBit_PublishedValid = 1 << 3;
		const int TraceBit_OnRender = 1 << 4;
		const int TraceBit_PassNear = 1 << 5;
		const int TraceBit_PassFar = 1 << 6;
		const int TraceBit_PassTemporal = 1 << 7;
		const int TraceBit_HistoryValidBefore = 1 << 8;
		const int TraceBit_HistoryValidAfter = 1 << 9;
		const int TraceBit_Disabled = 1 << 10;
		const int TraceBit_MissingTargets = 1 << 11;
		const int TraceBit_DiagnosticFailures = 1 << 12;

		int flags = Dazzle_GITraceFlags;

		float3 stageColor = 0.0f;
		if ( (flags & TraceBit_AddLayers) != 0 ) stageColor.r += 0.10f;
		if ( (flags & TraceBit_GIEnabled) != 0 ) stageColor.r += 0.20f;
		if ( (flags & TraceBit_TexturesReady) != 0 ) stageColor.r += 0.30f;
		if ( (flags & TraceBit_OnRender) != 0 ) stageColor.g += 0.25f;
		if ( (flags & TraceBit_PassNear) != 0 ) stageColor.g += 0.15f;
		if ( (flags & TraceBit_PassFar) != 0 ) stageColor.g += 0.15f;
		if ( (flags & TraceBit_PassTemporal) != 0 ) stageColor.g += 0.20f;
		if ( (flags & TraceBit_PublishedValid) != 0 ) stageColor.b += 0.35f;
		if ( (flags & TraceBit_HistoryValidBefore) != 0 ) stageColor.b += 0.15f;
		if ( (flags & TraceBit_HistoryValidAfter) != 0 ) stageColor.b += 0.15f;
		if ( (flags & TraceBit_DiagnosticFailures) != 0 ) stageColor.r += 0.30f;

		float framePulse = 0.6f + 0.4f * frac( (float)Dazzle_GITraceFrame * 0.03125f + uv.x * 0.5f + uv.y * 0.25f );
		stageColor *= framePulse;

		if ( (flags & TraceBit_Disabled) != 0 || !Dazzle_GIEnable )
		{
			return float3( 1.0f, 0.0f, 1.0f ) * 0.85f + stageColor * 0.15f;
		}

		if ( (flags & TraceBit_MissingTargets) != 0 )
		{
			return float3( 1.0f, 0.45f, 0.0f ) * 0.85f + stageColor * 0.15f;
		}

		if ( (flags & TraceBit_DiagnosticFailures) != 0 )
		{
			return float3( 1.0f, 0.3f, 0.05f ) * 0.75f + stageColor * 0.25f;
		}

		if ( !Dazzle_GIValid || Dazzle_GITextureIndex <= 0 )
		{
			return float3( 1.0f, 0.1f, 0.1f ) * 0.85f + stageColor * 0.15f;
		}

		float3 history = VisualizeRadiance( Dazzle_GITextureIndex, uv );
		return saturate( stageColor + history * 0.6f );
	}

	static float3 ComposeGIDebugView( float4 screenPosition )
	{
		float2 uv = ScreenUv( screenPosition );

		switch ( Dazzle_GIDebugView )
		{
			case DazzleGIDebug_TraceState:
				return VisualizeTraceState( uv );
			case DazzleGIDebug_HistoryRadiance:
				return VisualizeRadiance( Dazzle_GITraceHistoryIndex, uv );
			case DazzleGIDebug_NearCascade:
				return VisualizeRadiance( Dazzle_GITraceNearIndex, uv );
			case DazzleGIDebug_FarCascade:
				return VisualizeRadiance( Dazzle_GITraceFarIndex, uv );
		}

		return 0.0f;
	}

	static float3 ComposeAmbient( float3 primaryIndirect, float3 fallbackIndirect )
	{
		if ( !IsEnabled() )
		{
			return primaryIndirect;
		}

		float blendWeight = saturate( Dazzle_DDGIBlend * QualityWeight() * HardwareWeight() );
		float3 blended = lerp( fallbackIndirect, primaryIndirect, blendWeight );
		return max( blended, 0.0f );
	}

	static float3 SampleRadianceCascade( float4 screenPosition, float3 normalWs, float roughness )
	{
		if ( !Dazzle_GIEnable || !Dazzle_GIValid || Dazzle_GITextureIndex <= 0 )
		{
			return 0.0f;
		}

		float2 uv = ScreenUv( screenPosition );
		float3 giRadiance = SampleBindlessTextureRgb( Dazzle_GITextureIndex, uv );

		// Preserve coherence with BRDF response.
		float normalFacing = saturate( normalWs.z * 0.5f + 0.5f );
		float roughnessAttenuation = lerp( 1.0f, 0.7f, saturate( roughness ) );
		float cascadeWeight = max( Dazzle_GIBounceStrength, 0.0f ) * (0.5f + 0.5f * normalFacing) * roughnessAttenuation;
		cascadeWeight *= lerp( 1.0f, 1.6f, QualityWeight() );

		return max( giRadiance * cascadeWeight, 0.0f );
	}

	static void ApplyDirect( inout float3 diffuse, inout float3 specular, inout float3 transmissive )
	{
		if ( !IsEnabled() )
		{
			return;
		}

		float quality = QualityWeight();
		float scale = max( Dazzle_DirectIntensity, 0.0f );
		scale *= lerp( 0.90f, 1.10f, quality );

		// Keep highlights physically plausible when artists overdrive intensity.
		float energyNormalization = rcp( 1.0f + max( scale - 1.0f, 0.0f ) * 0.5f );
		float directScale = scale * energyNormalization;

		diffuse *= directScale;
		specular *= directScale;
		transmissive *= directScale;
	}

	static float3 ComposeIndirectDiffuse( float3 primaryIndirect, float3 fallbackIndirect, float dynamicAO, float4 screenPosition, float3 normalWs, float roughness )
	{
		if ( !IsEnabled() )
		{
			return primaryIndirect;
		}

		if ( IsGIDebugViewActive() )
		{
			return ComposeGIDebugView( screenPosition );
		}

		float3 radianceCascade = SampleRadianceCascade( screenPosition, normalWs, roughness );
		float3 dazzlePrimary = primaryIndirect + radianceCascade;
		dazzlePrimary = max( dazzlePrimary, primaryIndirect * 0.5f );

		float blendWeight = saturate( Dazzle_DDGIBlend * QualityWeight() * HardwareWeight() );
		float stability = StabilityWeight();
		float aoWeight = saturate( dynamicAO );

		float3 blended = lerp( fallbackIndirect, dazzlePrimary, blendWeight );
		blended = lerp( fallbackIndirect, blended, lerp( stability, 1.0f, aoWeight ) );
		blended *= max( Dazzle_IndirectIntensity, 0.0f );

		return max( blended, 0.0f );
	}

	static void ApplyGIDebugOverride( inout float3 diffuse, inout float3 specular, inout float3 indirectDiffuse, inout float3 indirectSpecular, inout float3 transmissive )
	{
		if ( !IsGIDebugViewActive() )
		{
			return;
		}

		float3 debugColor = max( indirectDiffuse, 0.0f );
		diffuse = 0.0f;
		specular = 0.0f;
		indirectDiffuse = 0.0f;
		indirectSpecular = debugColor * 2.0f;
		transmissive = 0.0f;
	}

	static float3 ComposeIndirectSpecular( float3 primarySpecular, float roughness )
	{
		if ( !IsEnabled() )
		{
			return primarySpecular;
		}

		float quality = QualityWeight();
		float roughnessAttenuation = lerp( 1.0f, 0.85f, saturate( roughness * roughness ) );
		float scale = max( Dazzle_IndirectIntensity, 0.0f ) * lerp( 0.80f, 1.0f, quality ) * roughnessAttenuation;
		return max( primarySpecular * scale, 0.0f );
	}
};

#endif // DAZZLE_LIGHTING_HLSL
