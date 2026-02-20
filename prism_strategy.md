# The Prism Framework: Architectural Strategy for Deep Engine Modification in S&box

## 1. Overview
The **Prism Framework** is a non-invasive, high-performance augmentation layer for the Source 2 engine in S&box. It operates by intercepting the engine's managed abstractions (C#) and asset pipelines rather than patching native binaries. It enables modern rendering techniques (RTGI, SDF tracing, custom lighting) by creating a "Shadow Pipeline" that runs alongside the engine's standard renderer.

## 2. Core Pillars

### A. The Orchestrator (Managed Interception)
The core of Prism is a C# system that hooks into the engine's `IRenderThread` interface. By implementing `OnRenderStage`, Prism gains access to the GPU command stream at critical execution points (e.g., `AfterDepthPrepass`, `AfterOpaque`, `BeforePostProcess`).
- **Resilience**: Since it uses public/internal C# interfaces provided by s&box, it is immune to changes in C++ memory layouts or private function signatures.
- **Control**: It uses the `CommandList` API to inject compute shaders, ray tracing dispatches, and custom draw calls.

### B. The Shadow VFS (Virtual File System Layer)
Prism implements a virtual filesystem overlay using `AggregateFileSystem`.
- **Interception**: When the engine requests a `.shader` or `.vfx` file, the Prism VFS provides a dynamically "patched" version of the source file.
- **Mixins**: Instead of full replacement, Prism performs string-based injection on `.shader` files to insert `#include "prism/header.hlsl"` and `#define PRISM_ENABLED`. This allows engine shaders to support custom features (like Fat G-Buffers) while maintaining compatibility with engine updates.

### C. The Fat G-Buffer (FGB) Extension
By patching the engine's standard shaders (e.g., `complex.shader`, `vr_standard.shader`), Prism forces the material system to output supplemental data to custom render targets.
- **Data Injection**: Roughness, Metalness, SDF distances, and motion vectors are written to "Fat" targets.
- **Global Bindings**: These targets are bound as global textures via `RenderAttributes`, making them accessible to any Prism Compute pass.

### D. The Custom Lighting Pipeline (The "Miracle")
Prism effectively "mutes" the engine's lighting by either:
1.  **Tag Exclusion**: Using `SceneCamera.ExcludeTags` to hide objects from the engine's opaque pass, then rendering them manually via a Prism `ProceduralRenderLayer`.
2.  **Screen Overwrite**: Letting the engine render, then performing a full-screen lighting pass in `AfterOpaque` that reads the G-Buffer and writes the final lit result, bypassing the engine's lighting calculations.

## 3. GPU Injection Strategy

### Hardware Raytracing (RTX/RTGI)
Prism leverages the engine's built-in `RayQuery` support. 
- **Scene Sync**: Prism iterates over `SceneObject`s to maintain a high-level representation of the scene for its own acceleration structures if the global one is insufficient.
- **Compute RT**: RTGI and Raytraced Shadows are implemented as Compute Shaders that query the acceleration structure and the Fat G-Buffer.

### Asset Redirection
Using the `Filesystem.Mount` priority system, Prism can redirect:
- **Materials**: Swapping `.vmat` files to use Prism-enabled shaders.
- **Models**: Dynamically injecting Mesh Shader variants or LODs.

## 4. Stability & Maintainability

### Resilience to Engine Updates
The Prism Framework is designed to be "future-proof" by adhering to the following principles:
- **Managed Abstraction**: By operating entirely within the C# layer (`Sandbox.Rendering`), Prism relies on the stable public API surface provided by Facepunch. When the underlying C++ engine changes, Facepunch updates the C# interop layer, which Prism automatically inherits.
- **Source-to-Source Transformation**: Patching `.shader` files is significantly more stable than binary patching. S&box's own shader compiler (`vfx_vulkan.dll`) handles the complexities of hardware variations and engine-specific optimizations. Prism only provides the "intent" (HLSL code), while the engine handles the "execution" (SPIR-V/Bytecode).
- **No Fragile Offsets**: Prism avoids memory-scanning or hardcoded offsets into Source 2 binaries. This eliminates the "cat-and-mouse" game typical of traditional engine hooks.

### Long-Term Maintainability
- **Modular Pass System**: Each Prism pass is a self-contained C# object, making it easy to add or remove features (e.g., swapping a Probe-based GI for a Ray-Traced GI) without affecting the rest of the engine.
- **Native Interop Utilization**: Prism uses the official `NativeEngine` generated bindings where possible, ensuring that even low-level calls (like `ResourceBarrierTransition`) are performed using the engine's intended mechanisms.

## 5. Implementation Steps

### Phase 1: The Foundation (Interception)
1. **Bootstrap**: Create a `PrismSystem` inheriting from `GameObjectSystem`.
2. **Hooking**: Register a global `IRenderThread` listener.
3. **Stage Logic**: Implement `OnRenderStage` for `AfterDepthPrepass` (to grab depth) and `AfterOpaque` (to inject lighting).

### Phase 2: The Shadow VFS (Injection & Asset Redirection)
1. **Mounting**: Create a `MemoryFileSystem` and mount it to `EngineFileSystem.Mounted` with priority. This acts as our "Virtual File System Layer".
2. **Dynamic Shader Patcher**: 
   - Intercept requested `.shader` files.
   - Inject `#include "prism/common.hlsl"` into the `COMMON` section.
   - **Shader Override Capability**: Replace specific material functions (e.g., `EvaluateLighting`) with Prism-variants.
   - **Fat G-Buffer**: Override the `PS` (Pixel Shader) outputs to include extra render targets (SV_Target1, SV_Target2, etc.) for data like Roughness, Metalness, and World-Space Normals.
3. **Asset Redirector**: 
   - Intercept `.vmat` (Material) requests.
   - Dynamically swap the "Shader" field to our Prism-augmented versions if a "Prism-Enabled" flag is detected in the material metadata.
4. **Binding**: Use `Graphics.Attributes.Set` to bind the custom RTs globally so they are visible to both engine and Prism shaders.

### Phase 3: GPU-Side Injection & Custom Pipeline (The Miracle)
1. **Resource Setup**: Initialize `GpuBuffer` for light data and `RenderTarget` for the Fat G-Buffer.
2. **Acceleration Structure**: Leverage `Raytracing::GetAccelerationStructure()` in HLSL to perform hardware-accelerated intersection tests for RTGI.
3. **Compute Lighting Pass**: 
   - Implement `prism_lighting.shader` (Compute Shader).
   - This pass evaluates a fully custom lighting model (e.g., Stochastic Screen-Space Reflections combined with Ray-Traced GI).
   - Read from the Fat G-Buffer and the engine's Depth/Normal buffers.
   - Use `CommandList.DispatchCompute` to evaluate lighting across the screen.
4. **Integration**: 
   - Use `CommandList.ResourceBarrierTransition` to ensure targets are in the correct state for reading/writing.
   - Use `CommandList.Blit` or a full-screen `DrawScreenQuad` to composite the final lit result into the engine's main viewport, effectively replacing the Source 2 lighting evaluation.

## 6. Limitations & Mitigations
- **Compiler Latency**: Dynamic shader patching can cause hitches during initial load. *Mitigation*: Background pre-compilation and persistent shader caching.
- **Opaque Pass Access**: Some engine passes are baked into native code. *Mitigation*: Use `ProceduralRenderLayer` to replace large chunks of the pipeline if necessary.
