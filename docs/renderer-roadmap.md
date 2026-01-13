# Renderer Roadmap (friendly, incremental)

This repo already has a clean “two-backend” shell:
- CPU backend: fills a texture on the CPU and presents via SDL renderer.
- GPU backend: initializes SDL GPU and clears the swapchain.

That’s a great starting point. Also: it’s totally reasonable to rewrite pieces as you go—renderers are easiest to build when you keep the *pipeline* simple and correct, then optimize.

---

## Proposed amendments (small, but important)

Your 3-part plan is reasonable. Two tweaks will keep it from getting painful later:

1. **Build a tiny, correct reference renderer first** (CPU or very simple GPU). It’s incredibly useful as a “truth oracle” when you later add chunking, culling, LODs, and splats.
2. **Treat “asset data” and “instance state” separately** from day 1. Mesh bytes, LOD tables, summaries, etc. are asset-side; transforms, animation time, and visibility are instance-side.

Nothing here requires a big rewrite up front—just keep the separation in mind.

---

## Part 1 — Traditional polygon renderer (triangles)

### Goal
Render a basic triangle mesh with a camera, depth testing, and simple shading.

### Choose your first “path”
Pick one and stick to it until you can draw a rotating cube:

- **Path A (recommended for your repo): GPU-first** using SDL GPU (Metal on macOS). Faster to reach realtime, closer to your end goal.
- **Path B (optional): CPU reference rasterizer** for learning + debugging. Slower, but very clarifying.

You can do both: implement Path B as a correctness reference, then build Path A to match.

### Milestones (GPU-first)
1. **Draw a single triangle**
   - Create a graphics pipeline (vertex + fragment shader).
   - Create a vertex buffer with 3 vertices.
   - Issue one draw call.
   - Definition of done: stable triangle, no flicker.

2. **Add transforms (MVP)**
   - Define `mat4` and basic `mul(mat4, vec4)`.
   - Upload `view_proj` and per-object `model`.
   - Definition of done: cube rotates with WASD camera.

3. **Add depth buffer**
   - Create a depth texture.
   - Enable depth test + depth write.
   - Definition of done: cube faces occlude correctly.

4. **Add a basic mesh format (even hard-coded at first)**
   - Start with hard-coded cube/icosphere.
   - Later: load precompiled mesh bytes from disk.

5. **Basic lighting**
   - Lambert (diffuse) with directional light.
   - Optional: simple ambient term.

### Milestones (CPU reference rasterizer)
If you choose CPU, keep it tiny:
- `Vertex { pos, color/normal }`
- `Triangle { i0, i1, i2 }` indices into vertices
- Per-frame:
  - transform to clip space
  - clip (optional initially)
  - perspective divide + viewport transform
  - rasterize triangles into a color buffer
  - z-buffer test

Definition of done: it matches GPU output for the same mesh/camera.

### Practical tips (Part 1)
- Don’t start with GLTF. Start with “a cube”.
- Add features in the order: “draw something” → “move camera” → “depth” → “lighting” → “asset loading”.
- Prefer **indexed triangles** (vertex buffer + index buffer). Storing per-triangle structs duplicates data and costs bandwidth.

---

## Part 2 — Chunking + more optimized culling

### Goal
Scale from “one mesh” to “a world” with many objects, without drowning the GPU/CPU.

### Data model
- **Asset-side (shared)**: mesh LOD payloads + per-LOD summaries.
- **Instance-side (per object)**: transform, mesh id, material id, animation state, visibility.
- **World-side (chunk)**: spatial bin of instances + aggregated summaries.

### Milestones
1. **Introduce bounding volumes**
   - Per mesh: bounding sphere or AABB in model space.
   - Per instance: world-space bounds (transform the sphere center; scale radius).

2. **Frustum culling**
   - Compute camera frustum planes.
   - Skip instances whose bounds are outside.
   - Definition of done: large scene, stable FPS.

3. **Basic LOD selection (screen-space size)**
   - Use projected radius to select LOD.
   - Add hysteresis (don’t thrash LODs).

4. **Chunk your world**
   - Fixed grid (e.g. 16×16×16) or sparse hash map of chunk coords.
   - Each chunk holds a list of instance ids.

5. **Chunk-level coarse culling**
   - Chunk bounds frustum test first.
   - Only then test instances.

6. **Batching & sorting**
   - Build a per-frame render list of “draw packets”:
     - pipeline/material
     - mesh + LOD
     - instance data index
   - Sort by pipeline/material to reduce state changes.

### Definition of done
- Thousands of instances can be present.
- Render list is built quickly.
- You can toggle frustum culling / LOD and see the effect.

---

## Part 3 — Distant summarization + polygon (or surfel) splatting

### Goal
Represent far-away objects cheaply while preserving stable appearance (less shimmer) and providing meaningful inputs for lighting.

### Core idea
At distance, don’t load or draw full meshes. Use **summaries** and **proxy representations** that are cheap to read and cheap to aggregate at the chunk level.

### What to store in per-LOD summaries
For each LOD entry, store a small fixed-size `LodSummary` that can be read without touching heavy payloads:
- bounds (sphere/AABB)
- average/base color (+ maybe emissive)
- alpha coverage (if needed)
- geometric error / recommended switch distance
- representation kind: `Dot`, `VoxelProxy`, `DecimatedMesh`, `FullMesh`, `Splats`

### Splatting: how to think about it
- **Coverage/reconstruction**: the splat kernel answers “how much does this primitive contribute to nearby pixels?” (anti-aliasing).
- **Shading**: normals/material/light answer “what color does it contribute?”

Keep those separate: don’t use `N·V` as “coverage”. Use it in shading.

### Milestones
1. **Dot impostor LOD**
   - If projected radius < ~0.5 px: draw a tiny billboard/dot using average color.

2. **Voxel proxy LOD**
   - Store a coarse occupancy (brick mask + optional per-brick coverage/color).
   - Chunk aggregates many objects’ occupancy into fewer draw calls.

3. **Splat LOD (recommended as an intermediate)**
   - Represent the surface as surfels or micro-polygons.
   - Render as instanced camera-facing quads with a kernel in the fragment shader.
   - Depth test against the opaque depth buffer.

4. **Chunk summarization**
   - Chunk computes:
     - “is there any meaningful coverage in this chunk at this distance?”
     - coarse average color / emissive
     - max projected error
   - Chunk can decide: skip / draw proxy / request higher LOD.

### Definition of done
- Far geometry is stable (less shimmer) when moving the camera.
- GPU work drops at distance (fewer vertices/pixels shaded).
- The chunk can cull proxies that wouldn’t contribute to visible pixels.

---

## Suggested resources

### Fundamentals (triangles, transforms, depth)
- LearnOpenGL (even if you’re not using OpenGL, the concepts translate): https://learnopengl.com/
- Real-Time Rendering (book): https://www.realtimerendering.com/

### Rasterization details / performance intuition
- Fabian Giesen (triangle rasterization & performance essays): https://fgiesen.wordpress.com/

### Ray tracing / sampling (useful background, even for splats)
- Scratchapixel: https://www.scratchapixel.com/

### Geometry LOD / simplification / proxies
- “Level of Detail for 3D Graphics” (Luebke et al.)
- Meshlet/clustering talks (search terms): “meshlets cluster culling”

### SDL3 GPU / Metal pipeline building blocks
- SDL3 repo + `SDL_gpu.h` examples/docs (browse in your vendored SDL source under `vendor/SDL`).

---

## Quick “next action” checklist (what I’d do this week)
1. Upgrade the GPU backend from “clear” to “draw a triangle”.
2. Add MVP matrices + depth buffer.
3. Hard-code a cube mesh and render 100 instances.
4. Add frustum culling + basic LOD based on projected size.

If you want, I can also generate a follow-up doc that’s **repo-specific**: which files to edit in which order (GPU pipeline creation, shader loading, vertex formats), and a minimal “draw triangle” implementation plan using SDL GPU on macOS.
