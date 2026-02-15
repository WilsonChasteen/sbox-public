#ifndef DDGI_HLSL
#define DDGI_HLSL

#include "common/classes/Bindless.hlsl"

struct DDGIVolume
{
    float4x4 WorldToProbeTransform;
    float3 BBoxMin;
    float3 BBoxMax;
    float NormalBias;
    float3 ProbeSpacing;
    float BlendDistance;
    float3 ReciprocalSpacing;
    int IrradianceTextureIndex;
    float3 ReciprocalCountsMinusOne;
    int DistanceTextureIndex;
    int3 ProbeCounts;
    int RelocationTextureIndex;
    int Mode;
    int CascadeAtlasIndex;
    int ReservoirBufferIndex;
    int SDFIndex;
    int CascadeLevels;
    int BaseDirections;
    int DazzleDebugMode;

    bool IsValid()
    {
        return IrradianceTextureIndex > 0 || ( Mode == 1 && CascadeAtlasIndex > 0 );
    }

    float3 ToProbeSpace( float3 positionWs )
    {
        return mul( WorldToProbeTransform, float4( positionWs, 1.0f ) ).xyz;
    }

    bool Contains( float3 positionWs )
    {
        float3 probeSpace = ToProbeSpace( positionWs );
        return all( probeSpace >= BBoxMin ) && all( probeSpace <= BBoxMax );
    }
};

StructuredBuffer<DDGIVolume> DDGIVolumes < Attribute( "DDGI_Volumes" ); >;
uint DDGIVolumeCount < Attribute( "DDGI_VolumeCount" ); >;

#define DDGISampler g_sBilinearClamp
#define DDGI_IRRADIANCE_OCT_RESOLUTION 6
#define DDGI_DISTANCE_OCT_RESOLUTION 14
#define DDGI_BORDER 1
#define DAZZLE_ATLAS_HEIGHT 1024u
#define DAZZLE_BASE_PROBE_DIM 16u

class DDGI
{
    static float3 Heatmap( float t )
    {
        float x = saturate( t );
        return saturate(
            float3(
                1.5f - abs( 4.0f * x - 3.0f ),
                1.5f - abs( 4.0f * x - 2.0f ),
                1.5f - abs( 4.0f * x - 1.0f )
            )
        );
    }

    static float3 FibonacciDirection( uint dirIdx, uint totalDirs )
    {
        const float goldenRatio = 1.61803398875f;
        const float PI = 3.14159265359f;
        float i = (float)dirIdx + 0.5f;
        float phi = 2.0f * PI * goldenRatio * i;
        float cosTheta = 1.0f - 2.0f * ( i / max( (float)totalDirs, 1.0f ) );
        float sinTheta = sqrt( saturate( 1.0f - cosTheta * cosTheta ) );
        return float3( cos( phi ) * sinTheta, sin( phi ) * sinTheta, cosTheta );
    }

    static uint RequestedDirCount( uint baseDirections, uint level )
    {
        uint shift = min( level * 2u, 12u );
        return max( 1u, baseDirections << shift );
    }

    static bool GetPackedLevelInfo( uint level, uint totalLevels, uint baseDirections, out uint probeDim, out uint numDirs, out uint2 atlasOffset )
    {
        probeDim = 1u;
        numDirs = 0u;
        atlasOffset = uint2( 0u, 0u );

        uint clampedLevels = clamp( totalLevels, 1u, 8u );
        uint offsetY = 0u;

        [loop]
        for ( uint l = 0u; l < clampedLevels; ++l )
        {
            uint dim = max( 1u, DAZZLE_BASE_PROBE_DIM >> l );
            uint requestedDirs = RequestedDirCount( baseDirections, l );
            uint remainingRows = ( offsetY < DAZZLE_ATLAS_HEIGHT ) ? ( DAZZLE_ATLAS_HEIGHT - offsetY ) : 0u;
            uint maxDirsFit = remainingRows / dim;
            uint dirs = min( requestedDirs, maxDirsFit );

            if ( l == level )
            {
                probeDim = dim;
                numDirs = dirs;
                atlasOffset = uint2( 0u, offsetY );
                return dirs > 0u;
            }

            offsetY += dirs * dim;
        }

        return false;
    }

    static uint2 PackedAtlasCoord( uint2 levelOffset, uint probeDim, uint3 probeCoord, uint dir )
    {
        return uint2(
            levelOffset.x + probeCoord.x + probeCoord.z * probeDim,
            levelOffset.y + probeCoord.y + dir * probeDim
        );
    }

    // Tile size = octahedral resolution + 2 border texels (1 on each side)
    static uint TileSize(uint resolution)
    {
        return resolution + 2;
    }

    // Base coordinate of a probe's tile in the 2D atlas slice
    static uint2 BaseCoordinate(uint2 probeXY, uint resolution)
    {
        uint tile = TileSize(resolution);
        return probeXY * tile;
    }

    // Convert interior texel index [0, octResolution-1] to normalized octahedral coordinate [0, 1]
    // Used by integration shader to determine which direction to store at each texel
    static float2 TexelToOctahedralCoord(uint2 interiorIdx, uint octResolution)
    {
        // Texel center mapping that aligns with edge-to-edge sampling
        return (float2(interiorIdx) + 0.5f) / float(octResolution);
    }

    // Convert normalized octahedral coordinate [0, 1] to texel coordinate within a probe tile
    // Used by sampling functions to compute UV coordinates
    static float2 OctahedralCoordToTexel(float2 octNormalized, uint octResolution)
    {
        // Edge-to-edge mapping: [0,1] -> [1, octResolution+1]
        // Allows bilinear sampling to blend with border texels at the edges
        return 1.0f + octNormalized * octResolution;
    }
    
    // Computes the surfaceBias parameter used by DDGI evaluation
    // The surfaceNormal and cameraDirection arguments are expected to be normalized
    static float3 GetSurfaceBias(float3 surfaceNormal, float3 cameraDirection, DDGIVolume volume)
    {
        float viewBias = 0; // TOOD: expose per-volume?
        return (surfaceNormal * volume.NormalBias) + (-cameraDirection * viewBias);
    }

    static float3 OctahedralDecode(float2 octCoord)
    {
        // Convert from [0,1] to [-1,1] range
        float2 oct = (octCoord * 2.0f) - 1.0f;
        
        float3 direction = float3(oct.xy, 1.0f - abs(oct.x) - abs(oct.y));
        if (direction.z < 0.0f)
        {
            float2 signNotZero = float2((direction.x >= 0.0f) ? 1.0f : -1.0f, (direction.y >= 0.0f) ? 1.0f : -1.0f);
            direction.xy = (1.0f - abs(direction.yx)) * signNotZero;
        }
        return normalize(direction);
    }

    static float2 OctahedralEncode(float3 direction)
    {
        float l1norm = abs(direction.x) + abs(direction.y) + abs(direction.z);
        float2 result = direction.xy * (1.0f / l1norm);
        if (direction.z < 0.0f)
        {
            float2 signNotZero = float2((result.x >= 0.0f) ? 1.0f : -1.0f, (result.y >= 0.0f) ? 1.0f : -1.0f);
            result = (1.0f - abs(result.yx)) * signNotZero;
        }
        
        // Convert from [-1,1] to [0,1] range
        return (result * 0.5f) + 0.5f;
    }

    // Load probe relocation offset and active state from the relocation texture
    // Returns offset in xyz, active state (0 or 1) is written to outActive
    static float3 GetProbeRelocationOffset( in DDGIVolume volume, int3 probeIndex, out bool outActive )
    {
        outActive = true;
        
        if ( volume.RelocationTextureIndex <= 0 )
            return 0;

        Texture3D relocationTex = Bindless::GetTexture3D( volume.RelocationTextureIndex );
        float4 data = relocationTex.Load( int4( probeIndex, 0 ) );
        
        // Alpha channel stores active state
        outActive = data.w > 0.5f;
        return data.xyz;
    }

    static float3 SampleProbeIrradiance( in DDGIVolume volume, Texture3D irradianceTex, int3 probeIndex, float3 direction )
    {
        float2 octNormalized = OctahedralEncode( direction );
        const uint octResolution = DDGI_IRRADIANCE_OCT_RESOLUTION;
        const uint tileSize = TileSize(octResolution);

        // Atlas dimensions in texels
        float2 atlasSize = float2(volume.ProbeCounts.x, volume.ProbeCounts.y) * tileSize;
        atlasSize = max(atlasSize, float2(1.0f, 1.0f));

        // Convert octahedral coordinate to texel position using shared helper
        float2 interiorTexel = OctahedralCoordToTexel(octNormalized, octResolution);

        // Add base offset for this probe's tile
        float2 texelCoord = float2(probeIndex.x, probeIndex.y) * tileSize + interiorTexel;
        
        float3 uvw;
        uvw.xy = texelCoord / atlasSize;
        uvw.z = (float( probeIndex.z ) + 0.5f ) / max( float( volume.ProbeCounts.z ), 1.0f );

        return irradianceTex.SampleLevel( DDGISampler, uvw, 0.0f ).rgb;
    }

    static float2 SampleProbeDistance( in DDGIVolume volume, Texture3D distanceTex, int3 probeIndex, float3 direction )
    {
        float2 octNormalized = OctahedralEncode( direction );
        const uint octResolution = DDGI_DISTANCE_OCT_RESOLUTION;
        const uint tileSize = TileSize(octResolution);

        // Atlas dimensions in texels
        float2 atlasSize = float2(volume.ProbeCounts.x, volume.ProbeCounts.y) * tileSize;
        atlasSize = max(atlasSize, float2(1.0f, 1.0f));

        // Convert octahedral coordinate to texel position using shared helper
        float2 interiorTexel = OctahedralCoordToTexel(octNormalized, octResolution);

        // Add base offset for this probe's tile
        float2 texelCoord = float2(probeIndex.x, probeIndex.y) * tileSize + interiorTexel;
        
        float3 uvw;
        uvw.xy = texelCoord / atlasSize;
        uvw.z = (float(probeIndex.z) + 0.5f ) / max( float( volume.ProbeCounts.z ), 1.0f );

        return distanceTex.SampleLevel( DDGISampler, uvw, 0.0f ).rg;
    }

    static float ComputeVisibility(float distanceToSample, float2 meanVariance)
    {
        float mean = meanVariance.x;           // Mean distance
        float variance = meanVariance.y;        // Variance of distance

        // Minimum variance threshold to prevent numerical instability
        // and overly harsh shadows from low-variance regions
        const float minVariance = 0.001f;
        variance = max(variance, minVariance);

        // If we're clearly in front of the mean surface, fully visible
        // Small epsilon to handle grazing angles
        if (distanceToSample <= mean * 1.01f)
            return 1.0f;

        float delta = distanceToSample - mean;
        float chebyshev = variance / (variance + delta * delta);

        // Sharpen the curve to reduce light leaking
        chebyshev = chebyshev * chebyshev * chebyshev; // pow(chebyshev, 3)
        
        // Apply a smooth threshold to cut off very low visibility values
        // This helps eliminate residual light leak from the tail of the distribution
        const float visibilityThreshold = 0.05f;
        chebyshev = smoothstep(0.0f, visibilityThreshold * 2.0f, chebyshev) * chebyshev;

        return chebyshev;
    }

    static bool IsEnabled()
    {
        return DDGIVolumeCount > 0;
    }

    static DDGIVolume GetVolume( float3 positionWs )
    {
        [loop]
        for ( uint volumeIdx = 0u; volumeIdx < DDGIVolumeCount; ++volumeIdx )
        {
            DDGIVolume candidate = DDGIVolumes[volumeIdx];

            if ( candidate.Contains( positionWs ) )
                return candidate;
        }

        return (DDGIVolume)0;
    }

    static float3 Evaluate( DDGIVolume volume, float3 positionWs, float3 normalWs, float3 cameraDirection = float3(0,0,1) )
    {
        if ( volume.Mode == 1 ) // Dazzle
        {
             if ( volume.CascadeAtlasIndex <= 0 )
                return 0.0f.xxx;

             Texture2D cascadeAtlas = Bindless::GetTexture2D( volume.CascadeAtlasIndex );
             float3 positionPs = volume.ToProbeSpace( positionWs );

             uint probeDim = 0u;
             uint numDirs = 0u;
             uint2 levelOffset = uint2( 0u, 0u );
             uint totalLevels = max( (uint)volume.CascadeLevels, 1u );
             uint baseDirections = max( (uint)volume.BaseDirections, 1u );

             if ( !GetPackedLevelInfo( 0u, totalLevels, baseDirections, probeDim, numDirs, levelOffset ) )
                return 0.0f.xxx;

             int maxProbeIndex = max( (int)probeDim - 1, 0 );
             int3 probeIdx = clamp( int3( (positionPs - volume.BBoxMin) * volume.ReciprocalSpacing ), 0, maxProbeIndex );
             float3 normal = normalize( normalWs );

             // Sample Level 0 directions with cosine weighting so indirect light responds to surface normal.
             float3 accumulatedIrradiance = 0.0f;
             float accumulatedWeight = 0.0f;
             for ( uint d = 0u; d < numDirs; ++d )
             {
                 uint2 atlasPos = PackedAtlasCoord( levelOffset, probeDim, (uint3)probeIdx, d );
                 float3 radiance = cascadeAtlas.Load( int3(atlasPos, 0) ).rgb;
                 float3 dir = FibonacciDirection( d, numDirs );
                 float w = saturate( dot( normal, dir ) );
                 accumulatedIrradiance += radiance * w;
                 accumulatedWeight += w;
             }

             float3 irradiance = 0.0f;
             if ( accumulatedWeight > 1e-5f )
             {
                irradiance = 3.14159265f * ( accumulatedIrradiance / accumulatedWeight );
             }

             // Dazzle debug views:
             // 0 = Off, 1 = IrradianceHeatmap, 2 = ProbeIndex
             if ( volume.DazzleDebugMode == 1 )
             {
                float luminance = dot( irradiance, float3( 0.2126f, 0.7152f, 0.0722f ) );
                return Heatmap( luminance * 0.25f ) * 2.0f;
             }

             if ( volume.DazzleDebugMode == 2 )
             {
                float3 probeColor = (float3( probeIdx ) + 0.5f) / max( (float)probeDim, 1.0f );
                return max( probeColor * 2.0f, float3( 0.2f, 0.2f, 0.2f ) );
             }

             return irradiance;
        }

        Texture3D irradianceTex = Bindless::GetTexture3D( volume.IrradianceTextureIndex );
        Texture3D distanceTex = Bindless::GetTexture3D( volume.DistanceTextureIndex );

        // Apply surface bias to reduce light leaking
        float3 surfaceBias = GetSurfaceBias( normalWs, cameraDirection, volume );
        float3 biasedPosition = positionWs + surfaceBias;

        float3 probeSpacePosition = volume.ToProbeSpace( biasedPosition );

        if ( any( probeSpacePosition < volume.BBoxMin ) || any( probeSpacePosition > volume.BBoxMax ) )
            return 0;

        // Unbiased position in probe space for distance/direction calculations
        float3 positionPs = volume.ToProbeSpace( positionWs );

        int3 baseGridCoord = clamp( int3( (probeSpacePosition - volume.BBoxMin) * volume.ReciprocalSpacing ),
                                    int3( 0, 0, 0 ),
                                    volume.ProbeCounts - int3( 1, 1, 1 ) );

        float3 baseProbePos = volume.ProbeSpacing * float3(baseGridCoord) + volume.BBoxMin;

        // Alpha is how far from the floor(currentVertex) position. on [0, 1] for each axis.
        float3 alpha = clamp( (probeSpacePosition - baseProbePos) / volume.ProbeSpacing, 0.0f.xxx, 1.0f.xxx );

        float3 accumulatedIrradiance = 0.0f.xxx;
        float accumulatedWeight = 0.0f;

        [unroll]
        for ( int i = 0; i < 8; ++i )
        {
            int3 offset = int3( i, i >> 1, i >> 2 ) & int3( 1, 1, 1 );
            int3 probeGridCoord = clamp( baseGridCoord + offset, int3( 0, 0, 0 ), volume.ProbeCounts - int3( 1, 1, 1 ) );

            // Base probe position in probe space
            float3 probePos = volume.ProbeSpacing * float3( probeGridCoord ) + volume.BBoxMin;

            // Apply relocation offset (offset is already in local/probe space)
            bool probeActive = true;
            float3 relocationOffset = GetProbeRelocationOffset( volume, probeGridCoord, probeActive );
            
            // Skip inactive probes (inside geometry)
            if ( !probeActive )
                continue;

            float3 relocatedProbePos = probePos + relocationOffset;

            // Use relocated probe position for distance calculations
            float3 probeToPoint = (positionPs - relocatedProbePos) + (normalWs * volume.NormalBias);
            float distanceToProbe = length( probeToPoint );
            if ( distanceToProbe < 1e-5f )
                continue;

            float3 direction = -probeToPoint / distanceToProbe;

            float3 trilinear = lerp( 1.0f - alpha, alpha, float3( offset ) );
            float weight = 1.0f;

            float3 trueDirectionToProbe = normalize( relocatedProbePos - positionPs );
            

            float2 distanceMoments = SampleProbeDistance( volume, distanceTex, probeGridCoord, direction );
            float visibility = ComputeVisibility( distanceToProbe, distanceMoments );
            weight *= visibility;

            float3 irradiance = SampleProbeIrradiance( volume, irradianceTex, probeGridCoord, -normalWs );

            // Aggressively crush low weights to reduce light leaking
            // Probes with very low visibility/backface weight are likely leaking
            const float crushThreshold = 0.25f;
            if ( weight < crushThreshold )
            {
                // Cubic falloff for smooth but aggressive crushing
                float t = weight / crushThreshold;
                weight = crushThreshold * t * t * t;
            }

            // Backface weight: aggressively reduce contribution from probes behind the surface
            // Using a tighter wrap that doesn't add a constant offset
            float backfaceDot = dot(trueDirectionToProbe, normalWs);

            // Smooth falloff that reaches zero at 90 degrees from normal
            // This prevents probes on the other side of walls from contributing
            weight *= saturate(backfaceDot) + 0.01;

            weight *= trilinear.x * trilinear.y * trilinear.z;

            accumulatedIrradiance += weight * irradiance;
            accumulatedWeight += weight;
        }

        if ( accumulatedWeight <= 1e-5f )
            return 0;

        return (0.5f * 3.14159265f) * (accumulatedIrradiance / accumulatedWeight);
    }
};

#endif // DDGI_HLSL
