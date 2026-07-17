// Shaders.metal — FolkBoy's two pipelines: solid color geometry
// (page, fills, outlines, circles) and textured quads (labels/titles
// rasterized on CPU via CoreText).

#include <metal_stdlib>
using namespace metal;

struct SolidVertex {
    packed_float2 position;   // pixels, origin top-left
    packed_float4 color;
};

struct TexVertex {
    packed_float2 position;   // pixels, origin top-left
    packed_float2 uv;
};

struct SolidVSOut {
    float4 position [[position]];
    float4 color;
};

struct TexVSOut {
    float4 position [[position]];
    float2 uv;
};

static inline float4 toClip(float2 p, float2 viewport) {
    float2 ndc = p / viewport * 2.0 - 1.0;
    return float4(ndc.x, -ndc.y, 0.0, 1.0);
}

vertex SolidVSOut solid_vertex(uint vid [[vertex_id]],
                               const device SolidVertex *verts [[buffer(0)]],
                               constant float2 &viewport [[buffer(1)]]) {
    SolidVSOut out;
    out.position = toClip(float2(verts[vid].position), viewport);
    out.color = float4(verts[vid].color);
    return out;
}

fragment float4 solid_fragment(SolidVSOut in [[stage_in]]) {
    return in.color;
}

vertex TexVSOut tex_vertex(uint vid [[vertex_id]],
                           const device TexVertex *verts [[buffer(0)]],
                           constant float2 &viewport [[buffer(1)]]) {
    TexVSOut out;
    out.position = toClip(float2(verts[vid].position), viewport);
    out.uv = float2(verts[vid].uv);
    return out;
}

// Text textures are premultiplied-alpha (UIGraphicsImageRenderer);
// the pipeline uses (one, oneMinusSourceAlpha) blending.
fragment float4 tex_fragment(TexVSOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    return tex.sample(s, in.uv);
}
