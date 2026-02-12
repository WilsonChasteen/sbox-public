HEADER
{
	DevShader = true;
	Description = "Fill RTXGI RayData from cubemap capture";
}

MODES
{
	Default();
}

COMMON
{
	#include "common.fxc"

    TextureCube SourceProbe < Attribute( "SourceProbe" ); >;
    TextureCube SourceDepth < Attribute( "SourceDepth" ); >;

    RWTexture2DArray<float4> RayData < Attribute( "RayData" ); >;

    int ProbeIndex < Attribute( "ProbeIndex" ); >;
    int3 ProbeCounts < Attribute( "ProbeCounts" ); >;
    int NumRays < Attribute( "NumRays" ); >;
    float MaxDistance < Attribute( "MaxDistance" ); >;

    #define ProbeSampler g_sTrilinearClamp

    float3 FibonacciDirection( uint index, uint count )
	{
		const float goldenRatio = 1.61803398874989484820459;
		const float PI = 3.14159265358979323846264;
		float i = (index + 0.5f);
		float phi = 2.0f * PI * goldenRatio * i;
		float cosTheta = 1.0f - 2.0f * (i / count);
		float sinTheta = sqrt( saturate( 1.0f - cosTheta * cosTheta ) );
		return float3( cos( phi ) * sinTheta, sin( phi ) * sinTheta, cosTheta );
	}

    float GetDepthDistance( float3 direction )
	{
		float depth = SourceDepth.SampleLevel( ProbeSampler, direction, 0.0f ).r;

        // Assuming depth is already linear from the depth copy shader or captured as R32F

		// Convert to perpendicular distance if needed, but usually cubemap depth is radial distance if captured that way
        // Actually SceneCamera.RenderToCubeTexture usually renders standard depth.
        // The old DDGIVolumeUpdater.cs used a DepthCopyShader which linearized it.

		return depth;
	}
}

CS
{
    [numthreads(64, 1, 1)]
    void MainCs( uint3 vThreadId : SV_DispatchThreadID )
    {
        uint rayIndex = vThreadId.x;
        if ( rayIndex >= (uint)NumRays ) return;

        float3 direction = FibonacciDirection( rayIndex, NumRays );

        float3 radiance = SourceProbe.SampleLevel( ProbeSampler, direction, 0.0f ).rgb;
        float distance = GetDepthDistance( direction );

        // RTXGI RayData format: X=radiance, Y=probesPerPlane index, Z=plane index
        int probesPerPlane = ProbeCounts.x * ProbeCounts.y;
        uint3 coords = uint3( rayIndex, ProbeIndex % probesPerPlane, ProbeIndex / probesPerPlane );

        RayData[coords] = float4( radiance, distance );
    }
}
