# Dazzle Global Illumination

Dazzle GI is a state-of-the-art real-time Global Illumination system implemented for the s&box engine. It is based on the principles of **Radiance Cascades** and **Persistent World-Space Reservoirs**, providing deterministic, high-quality indirect lighting without the typical artifacts associated with temporal accumulation or neural reconstruction.

## Technical Overview

### 1. Radiance Cascades
The core of Dazzle GI is a multi-scale representation of the radiance field. It exploits the distance-dependent trade-off between linear (spatial) and angular resolution:
- **Near Field:** High spatial resolution with low angular resolution (captured in lower cascade levels).
- **Far Field:** Low spatial resolution with high angular resolution (captured in higher cascade levels).

Radiance is stored in a 2D atlas where each level represents a specific range interval. These intervals are traced and then recursively merged using a closed-form composition:
\[ L_{merged} = L_{near} + T_{near} \cdot L_{far} \]

### 2. Software Raytracing (Global SDF)
To support hardware without raytracing units, Dazzle implements a high-performance software raytracing backend:
- **Voxelization:** Scene geometry is voxelized into a clipmapped volume every frame.
- **Jump Flood Algorithm (JFA):** A Signed Distance Field (SDF) is generated from the voxel grid in $O(\log N)$ passes.
- **Raymarching:** The Radiance Cascades trace intervals by marching through this global SDF.

### 3. Persistent World-Space Reservoirs
Dazzle uses world-space ReSTIR-style reservoirs to achieve view-independent reuse:
- **Hashing:** Reservoirs are stored in a sparse, spatially hashed grid.
- **Persistence:** High-value samples are maintained across frames, decoupled from the camera viewport.
- **Invalidation:** An epoch-tagging system ensures that stale lighting data is quickly replaced when geometry changes.

### 4. Surfel-Based GI Fallback
For highly dynamic scenes or constrained hardware, a surfel cache is maintained:
- **Management:** Surfels are spawned from the G-buffer based on coverage.
- **Lighting:** Surfels accumulate direct irradiance and feed back into the reservoir/cascade system, enabling multi-bounce GI.

## File Structure

### C# Logic (`engine/Sandbox.Engine/Scene/Components/IndirectLighting/`)
- `DazzleGISystem.cs`: Main engine system that manages resource allocation, compute dispatching, and integration with the renderer.
- `IndirectLightVolume.cs`: Extended to include Dazzle mode and relevant user-facing settings (Cascade Levels, Reservoir Cell Size, etc.).

### HLSL Shaders (`game/addons/base/Assets/shaders/common/Dazzle/`)
- `DazzleShared.hlsl`: Shared data structures for surfels and reservoirs.
- `dazzle_voxelize.shader`: Vertex/Pixel shader for scene voxelization.
- `dazzle_sdf_seed.shader`, `dazzle_sdf_jfa.shader`, `dazzle_sdf_finalize.shader`: JFA pipeline for SDF generation.
- `dazzle_cascades_trace_cs.shader`: Interval tracing for radiance levels.
- `dazzle_cascades_merge_cs.shader`: Recursive merging of cascade levels.
- `dazzle_reservoir_update_cs.shader`: Spatiotemporal resampling for reservoirs.
- `dazzle_surfel_manage_cs.shader`, `dazzle_surfel_lighting_cs.shader`, `dazzle_surfel_fixup_cs.shader`: Surfel GI pipeline.
- `dazzle_clear_cs.shader`: Utility shader for clearing UAVs.

### Integration
- `game/addons/base/Assets/shaders/common/DDGI/DDGI.hlsl`: Updated evaluation logic to support Dazzle sampling.
- `game/addons/base/Assets/shaders/common/classes/AmbientLight.hlsl`: Added `AmbientLightKind::Dazzle` to the shading pipeline.

## Usage

In the s&box editor, add an **Indirect Light Volume** to your scene and set the **Mode** to `Dazzle`. Adjust the **Dazzle Settings** to balance quality and performance for your specific needs.
