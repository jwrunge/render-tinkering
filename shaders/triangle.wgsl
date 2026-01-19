// Minimal WGSL shader pair:
// - Vertex: passthrough clip-space position from a vertex buffer @location(0)
// - Fragment: solid color output

struct VSIn {
    @location(0) pos: vec2f,
};

struct VSOut {
    @builtin(position) pos: vec4f,
};

@vertex
fn vs_main(in: VSIn) -> VSOut {
    var out: VSOut;
    out.pos = vec4f(in.pos, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main() -> @location(0) vec4f {
    return vec4f(0.10, 0.75, 0.95, 1.0);
}
