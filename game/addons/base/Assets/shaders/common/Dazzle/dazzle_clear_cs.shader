HEADER
{
	Description = "Dazzle GI - Clear UAV";
	DevShader = true;
}

MODES
{
	Default();
}

COMMON
{
	#include "common/shared.hlsl"
}

CS
{
	DynamicCombo( D_UINT, 0..1, Sys( ALL ) );

	RWTexture3D<float> TargetTex < Attribute( "TargetTex" ); >;
	RWTexture3D<uint> TargetTexU < Attribute( "TargetTexU" ); >;
	int3 GridSize < Attribute( "GridSize" ); >;

	[numthreads( 8, 8, 8 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		if ( any( id >= (uint3)GridSize ) ) return;

		#if D_UINT
			TargetTexU[id] = 0;
		#else
			TargetTex[id] = 0;
		#endif
	}
}
