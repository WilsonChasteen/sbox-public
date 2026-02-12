HEADER
{
	DevShader = true;
	Description = "Copy depth to color texture array slice";
}

MODES
{
	Default();
}

COMMON
{
	#include "common.fxc"

    Texture2D SourceDepth < Attribute( "SourceDepth" ); >;
    RWTexture2DArray<float> DestTextureArray < Attribute( "DestTextureArray" ); >;

    uint2 TextureSize < Attribute( "TextureSize" ); >;
    int DestArraySlice < Attribute( "DestArraySlice" ); >;
}

CS
{
    [numthreads(8, 8, 1)]
    void MainCs( uint3 vThreadId : SV_DispatchThreadID )
    {
        if ( any( vThreadId.xy >= TextureSize ) ) return;

        float depth = SourceDepth.Load( uint3( vThreadId.xy, 0 ) ).r;

        // Normalize and linearize depth if needed
        // Assuming standard depth for now

        DestTextureArray[uint3( vThreadId.xy, DestArraySlice )] = depth;
    }
}
