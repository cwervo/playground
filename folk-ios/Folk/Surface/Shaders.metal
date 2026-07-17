// Shaders.metal
// Two pipelines for the Surface:
//  - a flat-color 2D pipeline (lines/rects/circles are tessellated on the CPU)
//  - a metaball field pipeline (full-screen pass, analytic field in the
//    fragment shader) — the showpiece instruction, mirroring the app icon.

#include <metal_stdlib>
using namespace metal;

struct ShapeVertexIn {
    float2 position;   // in points, origin top-left
    float4 color;
};

struct ShapeVertexOut {
    float4 position [[position]];
    float4 color;
};

struct SurfaceUniforms {
    float2 viewport;   // in points
};

vertex ShapeVertexOut shape_vertex(const device ShapeVertexIn *vertices [[buffer(0)]],
                                   constant SurfaceUniforms &uniforms [[buffer(1)]],
                                   uint vid [[vertex_id]]) {
    ShapeVertexIn in = vertices[vid];
    float2 ndc = in.position / uniforms.viewport * 2.0 - 1.0;
    ndc.y = -ndc.y;
    ShapeVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 shape_fragment(ShapeVertexOut in [[stage_in]]) {
    return in.color;
}

// --- Metaballs -------------------------------------------------------------

struct MetaballUniforms {
    float2 centers[8];   // in points
    float2 viewport;     // in points
    float4 color;
    float radius;
    int count;
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenOut metaball_vertex(uint vid [[vertex_id]]) {
    // Single full-screen triangle.
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    FullscreenOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

fragment float4 metaball_fragment(FullscreenOut in [[stage_in]],
                                  constant MetaballUniforms &u [[buffer(0)]]) {
    float2 p = in.uv * u.viewport;
    float field = 0.0;
    float r2 = u.radius * u.radius;
    for (int i = 0; i < u.count; i++) {
        float2 d = p - u.centers[i];
        float dist2 = max(dot(d, d), 1e-4);
        field += r2 / dist2;
    }
    // Threshold with a soft edge; slight highlight where the field is dense.
    float alpha = smoothstep(1.0, 1.12, field);
    float sheen = smoothstep(2.5, 7.0, field) * 0.22;
    float3 rgb = mix(u.color.rgb, float3(1.0, 0.97, 0.85), sheen);
    return float4(rgb, alpha * u.color.a);
}
