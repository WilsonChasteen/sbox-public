# Dazzle Lighting

Dazzle is a modular direct + indirect lighting subsystem layered on top of the engine's existing lighting pipeline.

## What It Adds

- Direct lighting modulation with energy-aware scaling.
- Indirect lighting composition that blends existing GI paths with Dazzle controls.
- Real-time radiance cascade GI updated in a procedural compute layer.
- Runtime capability handling for low-end hardware tiers (RT and API aware).
- Scene-level authoring controls through the `DazzleLighting` component.

## Radiance Cascade GI

The radiance cascade module is a 3-pass incremental compute update:

1. Near cascade build:
- Inputs: scene color, depth, normals, AO.
- Produces a stable first-bounce estimate in a low-resolution cache.

2. Cascade propagation:
- Reads near cascade and performs low-bandwidth multi-bounce spread.
- Bounce gain is controlled by `Dazzle_GIBounceStrength`.

3. Temporal resolve:
- Blends propagated radiance with history.
- Uses reactive depth-based blending to remain stable during scene changes.

The result is stored in a persistent per-view history texture and sampled by Dazzle shading on the next frame.

## Data Flow

- Per-scene config:
`DazzleLighting` -> `DazzleLightingSystem` -> scene `RenderAttributes`.

- Per-view runtime setup:
`DazzleRenderExtension` stamps runtime capability flags and publishes the previous-frame GI texture index.

- GI update:
`DazzleRadianceCascadeLayer` runs at pipeline end and refreshes caches incrementally.

- Shading consumption:
`DazzleLighting.hlsl` samples `Dazzle_GITextureIndex` and injects radiance in `ComposeIndirectDiffuse`.

## Integration Points

- Shader controls: `game/addons/base/Assets/shaders/common/classes/DazzleLighting.hlsl`
- Ambient route: `game/addons/base/Assets/shaders/common/classes/AmbientLight.hlsl`
- Core lighting hook: `game/core/shaders/vr_lighting.fxc`
- Cascade compute shader: `game/addons/base/Assets/shaders/common/Dazzle/dazzle_radiance_cascade_cs.shader`
- Render extension: `engine/Sandbox.Engine/Systems/Render/Extensions/DazzleRenderExtension.cs`
- GI update layer: `engine/Sandbox.Engine/Systems/Render/Extensions/DazzleRadianceCascadeLayer.cs`
- Scene config/system:
`engine/Sandbox.Engine/Scene/Components/IndirectLighting/DazzleLighting.cs`
`engine/Sandbox.Engine/Scene/Components/IndirectLighting/DazzleLightingSystem.cs`

## Hardware Tier Fallbacks

- No hardware RT:
lower cascade resolution, reduced update fraction, stronger temporal stabilization.

- Non-Vulkan paths:
more conservative cascade update budget to protect GPU cost.

- Dazzle GI disabled:
shaders read no cascade texture and continue with existing DDGI/lightprobe/envmap coherence paths.

## GI Pipeline Trace Debug

Use the `DazzleLighting` component debug controls to trace GI end-to-end:

- `Enable GI Pipeline Trace`:
enables per-frame pipeline state tracking.

- `GI Debug View`:
selects an in-frame visualization mode.
1. `TraceState`: color-coded pipeline stage status.
2. `HistoryRadiance`: current GI history texture.
3. `NearCascade`: near-pass radiance texture.
4. `FarCascade`: propagated far-pass radiance texture.

- `GI Pipeline Trace Log`:
prints periodic trace snapshots to log with frame, flags, and texture indices.

### Automated Diagnostics

When `Enable GI Pipeline Trace` is enabled, Dazzle automatically runs a low-overhead diagnostics tracer inside the radiance cascade compute stages.

- Stage coverage:
near update, propagation, and temporal resolve are each instrumented in-shader.

- Automatic checks:
invalid/NaN radiance, zero-energy cascades, propagation failures, missing AO/normal/depth inputs, temporal instability spikes, and clamped factors.

- Per-cell capture:
sampled cells from each stage are logged with stage tags, cell coordinates, flags, and stage-specific metrics.

- Summary per frame:
the engine logs structured counters for total/updated pixels and all failure classes.

- Runtime overhead:
diagnostics uses a tiny structured GPU buffer with async readback and is disabled in retail builds.

Trace flags (`Dazzle_GITraceFlags`) bit layout:

- `1<<0`: layer setup ran
- `1<<1`: GI enabled for this view
- `1<<2`: cascade/history textures ready
- `1<<3`: GI texture published valid for shading
- `1<<4`: OnRender executed
- `1<<5`: near pass dispatched
- `1<<6`: far pass dispatched
- `1<<7`: temporal pass dispatched
- `1<<8`: history valid before update
- `1<<9`: history valid after update
- `1<<10`: GI disabled path
- `1<<11`: missing required render targets/textures
- `1<<12`: automated diagnostics detected failures

Console output format:

- Summary:
`[DazzleGI.Diagnostic][Summary] frame=... stageMask=... pixels=... invalid=...`

- Sample entry:
`[DazzleGI.Diagnostic][Near|Far|Temporal][Frame ...][Cell x,y] flags=... ...metrics...`
