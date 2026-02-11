## 2025-05-15 - Render Pass Early-Outs and Resource Safety
**Learning:** In Source 2-based engines, skipping a render pass that normally sets global or view-level texture attributes can cause native crashes in the Vulkan backend (e.g., in `PurgeFencedResources`) if the native side attempts to access a stale or invalid resource handle from a previous frame.
**Action:** Always ensure that if a pass is skipped, its expected output attributes are set to a safe default (like `Texture.Black`) to maintain consistent state for subsequent passes or native cleanup logic.

## 2025-05-15 - Hotloading and Static Registration
**Learning:** Static constructors in s&box can run multiple times during hotloading, leading to duplicate registrations if a static list is used without type-checking.
**Action:** Use `extensions.Any( x => x.GetType() == extension.GetType() )` in registration methods to prevent duplicate extension instances.
