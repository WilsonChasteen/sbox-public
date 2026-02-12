HEADER
{
	Description = "Dazzle GI - Surfel Management";
	DevShader = true;
}

MODES
{
	Default();
}

COMMON
{
	#include "common/shared.hlsl"
	#include "common/Dazzle/DazzleShared.hlsl"
	#include "common/classes/Depth.hlsl"
	#include "common/classes/Normals.hlsl"
}

CS
{
	RWStructuredBuffer<DazzleSurfel> SurfelBuffer < Attribute( "SurfelBuffer" ); >;
	RWByteAddressBuffer SurfelCountBuffer < Attribute( "SurfelCountBuffer" ); >;
	RWTexture3D<uint> SurfelHashGrid < Attribute( "SurfelHashGrid" ); >;

	Texture2D g_tColor < Attribute( "Color" ); >;

	uint MaxSurfels < Attribute( "MaxSurfels" ); >;
	float SurfelRadius < Attribute( "SurfelRadius" ); >;
	float3 VolumeMin < Attribute( "VolumeMin" ); >;
	float3 VolumeMax < Attribute( "VolumeMax" ); >;
	int3 HashGridSize < Attribute( "HashGridSize" ); >;

	[numthreads( 8, 8, 1 )]
	void MainCs( uint2 id : SV_DispatchThreadID )
	{
		// Only sample every Nth pixel to save performance
		if ( ( id.x % 16 != 0 ) || ( id.y % 16 != 0 ) ) return;

		float depth = Depth::Get( id );
		if ( depth >= 1.0f ) return;

		float2 uv = ( (float2)id + 0.5f ) * g_vInvViewportSize.xy;
		float3 posPs = float3( uv * 2.0f - 1.0f, depth );
		posPs.y *= -1.0f;
		float4 posWs4 = mul( g_matProjectionToWorld, float4( posPs, 1.0f ) );
		float3 posWs = posWs4.xyz / posWs4.w;

		if ( any( posWs < VolumeMin ) || any( posWs > VolumeMax ) ) return;

		float3 normalWs = Normals::Sample( id );
		float3 albedo = g_tColor.Load( int3( id, 0 ) ).rgb;

		// Check if covered by existing surfel
		float3 posLocal = ( posWs - VolumeMin ) / ( VolumeMax - VolumeMin );
		int3 hashPos = int3( posLocal * HashGridSize );

		uint cellValue;
		InterlockedCompareExchange( SurfelHashGrid[hashPos], 0, 1, cellValue );

		if ( cellValue == 0 )
		{
			// Spawn new surfel
			uint index;
			SurfelCountBuffer.InterlockedAdd( 0, 1, index );

			if ( index < MaxSurfels )
			{
				DazzleSurfel s;
				s.Position = posWs;
				s.Normal = normalWs;
				s.Albedo = albedo;
				s.Radiance = 0;
				s.Radius = SurfelRadius;
				s.LastUsedFrame = (uint)g_flTime;
				SurfelBuffer[index] = s;

				SurfelHashGrid[hashPos] = index + 1;
			}
		}
	}
}
