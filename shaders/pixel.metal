#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VSOut fullscreen_vs(uint vid [[vertex_id]]) {
    // Fullscreen triangle (covers entire viewport)
    float2 pos;
    pos.x = (vid == 2) ?  3.0 : -1.0;
    pos.y = (vid == 1) ?  3.0 : -1.0;

    VSOut out;
    out.pos = float4(pos, 0.0, 1.0);
    // Map from clip-space [-1..1] to UV [0..1]
    out.uv = (pos + 1.0) * 0.5;
    return out;
}

fragment float4 fullscreen_fs(VSOut in [[stage_in]]) {
    // Simple per-pixel work demo: gradient + subtle checker.
    float2 uv = in.uv;
    float checker = fmod(floor(uv.x * 80.0) + floor(uv.y * 80.0), 2.0);
    float3 base = float3(uv.x, uv.y, 0.25);
    base += (checker * 0.06);
    return float4(base, 1.0);
}
