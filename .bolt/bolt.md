2025-05-14 - Consolidate Per-Frame Stats Collection
Learning: Using LINQ and multiple enumerations in per-frame statistics collection (TickSceneStats) causes significant heap allocations and CPU overhead. Consolidating into a single pass and using low-allocation patterns like scene.Components.Execute<T> and direct HashSet access eliminates this overhead.
Action: Always prefer single-pass iteration and non-allocating execution patterns (Execute<T>) over LINQ and GetAllComponents<T> in hot loops.
