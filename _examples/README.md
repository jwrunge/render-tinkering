# Examples

This folder contains self-contained reference implementations that are *not* wired into the main app in `src/`.

- `sdl_gpu_triangle_wgsl/`: Minimal SDL3 GPU triangle that compiles WGSL using `naga` and renders it.

## Running

From the repo root:

- Build + run the triangle example: `zig build run-example-triangle`
- Compile shaders only: `zig build example-triangle-shaders`

Notes:

- You need the `naga` CLI available (or pass `-Dnaga_bin=/path/to/naga`).
- This example prefers `MSL` on Metal and falls back to `SPIR-V` on Vulkan.
- `naga` writes Metal output with a `.metal` extension here.
- The build step compiles every `.wgsl` file in `_examples/sdl_gpu_triangle_wgsl/shaders/`.
