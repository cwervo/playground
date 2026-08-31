#include <metal_stdlib>
using namespace metal;

// NOTE: the three structs below are mirrored byte-for-byte in Swift
// (GPU/GPUTypes.swift). Change one, change the other; GPUTypes.swift asserts
// the strides at startup.

constant uint kMaxRuns = 4;

struct SkinParams {
    float2 mean;        // CbCr centre of the skin ellipse, normalised 0..1
    float3 invCov;      // symmetric 2x2 inverse covariance: (a, b, c) -> [[a,b],[b,c]]
    float  threshold;   // Mahalanobis cut: accept if exp(-0.5 * d) >= threshold
    float  lumaMin;
    float  lumaMax;
    uint   flipX;
    uint   flipY;
};

struct MorphParams {
    uint radius;
    uint dilate;        // 0 = erode (min), 1 = dilate (max)
    uint horizontal;    // 0 = vertical pass, 1 = horizontal pass
    uint _pad;
};

struct RLEParams {
    uint minRunLength;
    uint _pad[3];
};

struct ColumnRuns {
    uint count;
    uint starts[kMaxRuns];
    uint ends[kMaxRuns];
    uint _pad[3];       // -> 48 bytes
};

// ---------------------------------------------------------------------------
// Pass 1: skin likelihood straight off the camera's native biplanar output.
//
// A 420YpCbCr8 buffer hands us chroma already separated from luma, so the
// HSV conversion the OpenCV version needs simply does not exist here. We model
// skin as a 2D Gaussian in CbCr (fitted from the user's own hand during
// calibration) rather than an axis-aligned box, which is both tighter and
// tolerant of the colour cast the mirror introduces.
// ---------------------------------------------------------------------------
kernel void skin_mask(texture2d<float, access::sample> luma    [[texture(0)]],
                      texture2d<float, access::sample> chroma  [[texture(1)]],
                      texture2d<float, access::write>  mask    [[texture(2)]],
                      constant SkinParams &p                   [[buffer(0)]],
                      uint2 gid                                [[thread_position_in_grid]])
{
    const uint w = mask.get_width();
    const uint h = mask.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    const float2 uv = (float2(gid) + 0.5) / float2(w, h);

    const float  y  = luma.sample(s, uv).r;
    const float2 cc = chroma.sample(s, uv).rg;

    const float2 d = cc - p.mean;
    const float  m = p.invCov.x * d.x * d.x
                   + 2.0 * p.invCov.y * d.x * d.y
                   + p.invCov.z * d.y * d.y;
    const float  score = exp(-0.5 * m);

    const bool lit = (y >= p.lumaMin) && (y <= p.lumaMax);
    const float on = (lit && score >= p.threshold) ? 1.0 : 0.0;

    // Fold the mirror's flip into the write address so every downstream stage
    // works in one canonical orientation: +y points away from the glass, i.e.
    // the real finger sits above its reflection.
    const uint2 o = uint2(p.flipX ? (w - 1 - gid.x) : gid.x,
                          p.flipY ? (h - 1 - gid.y) : gid.y);
    mask.write(float4(on), o);
}

// ---------------------------------------------------------------------------
// Pass 2: separable morphology. Two of these back to back is an open (despeckle),
// two more is a close (bridge the specular hole across a knuckle).
// Equivalent to MPSImageAreaMin / MPSImageAreaMax, written out so the pipeline
// stays one readable list of dispatches.
// ---------------------------------------------------------------------------
kernel void morph(texture2d<float, access::read>  src [[texture(0)]],
                  texture2d<float, access::write> dst [[texture(1)]],
                  constant MorphParams &p             [[buffer(0)]],
                  uint2 gid                           [[thread_position_in_grid]])
{
    const int w = int(src.get_width());
    const int h = int(src.get_height());
    if (gid.x >= uint(w) || gid.y >= uint(h)) { return; }

    const int r  = int(p.radius);
    const int2 step = p.horizontal ? int2(1, 0) : int2(0, 1);
    float acc = p.dilate ? 0.0 : 1.0;

    for (int i = -r; i <= r; ++i) {
        const int2 c = clamp(int2(gid) + step * i, int2(0), int2(w - 1, h - 1));
        const float v = src.read(uint2(c)).r;
        acc = p.dilate ? max(acc, v) : min(acc, v);
    }
    dst.write(float4(acc), gid);
}

// ---------------------------------------------------------------------------
// Pass 3: vertical run-length encoding — this replaces contour finding entirely.
//
// One thread owns one column and walks it top to bottom, recording up to
// kMaxRuns spans of set pixels. In this camera geometry a finger and its
// reflection in the glass are, by construction, two vertically adjacent runs in
// the same column, so the run table already *is* the feature we want. It costs
// one pass, produces ~60 KB the CPU can parse in microseconds, and is fully
// deterministic — no contour hierarchy, no allocation, no frame-to-frame
// ordering surprises.
//
// The per-column ROI clips to the calibrated screen quad, which is what keeps
// the user's forearm, the keyboard and the bezel out of the run table.
// ---------------------------------------------------------------------------
kernel void column_rle(texture2d<float, access::read> mask [[texture(0)]],
                       device ColumnRuns *out              [[buffer(0)]],
                       device const uint2 *roi              [[buffer(1)]],
                       constant RLEParams &p                [[buffer(2)]],
                       uint x                               [[thread_position_in_grid]])
{
    const uint w = mask.get_width();
    const uint h = mask.get_height();
    if (x >= w) { return; }

    ColumnRuns cr;
    cr.count = 0;
    for (uint i = 0; i < kMaxRuns; ++i) { cr.starts[i] = 0; cr.ends[i] = 0; }

    const uint y0 = min(roi[x].x, h);
    const uint y1 = min(roi[x].y, h);

    bool inRun = false;
    uint start = 0;

    for (uint y = y0; y < y1; ++y) {
        const bool on = mask.read(uint2(x, y)).r > 0.5;
        if (on && !inRun) {
            inRun = true;
            start = y;
        } else if (!on && inRun) {
            inRun = false;
            if (y - start >= p.minRunLength) {
                // Keep the *lowest* kMaxRuns runs: the finger and its reflection
                // are always the bottom-most pair, so shifting on overflow
                // discards sleeve and arm rather than the thing we care about.
                if (cr.count == kMaxRuns) {
                    for (uint i = 0; i + 1 < kMaxRuns; ++i) {
                        cr.starts[i] = cr.starts[i + 1];
                        cr.ends[i]   = cr.ends[i + 1];
                    }
                    cr.count = kMaxRuns - 1;
                }
                cr.starts[cr.count] = start;
                cr.ends[cr.count]   = y - 1;
                cr.count += 1;
            }
        }
    }
    if (inRun && (y1 - start) >= p.minRunLength && cr.count < kMaxRuns) {
        cr.starts[cr.count] = start;
        cr.ends[cr.count]   = y1 - 1;
        cr.count += 1;
    }

    out[x] = cr;
}

// ---------------------------------------------------------------------------
// HUD compositing: camera luma underneath, mask tinted, CoreGraphics-drawn
// vector overlay on top. Metal only has to blend; all the text and geometry is
// drawn once per frame into a CGBitmapContext.
// ---------------------------------------------------------------------------
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut hud_vertex(uint vid [[vertex_id]])
{
    const float2 quad[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    VertexOut o;
    o.position = float4(quad[vid], 0, 1);
    o.uv = float2((quad[vid].x + 1) * 0.5, 1.0 - (quad[vid].y + 1) * 0.5);
    return o;
}

fragment float4 hud_fragment(VertexOut in                            [[stage_in]],
                             texture2d<float> camera                 [[texture(0)]],
                             texture2d<float> mask                   [[texture(1)]],
                             texture2d<float> overlay                [[texture(2)]],
                             constant float &panelAlpha              [[buffer(0)]])
{
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    const float y = camera.sample(s, in.uv).r;
    const float m = mask.sample(s, in.uv).r;

    // Cyan, deliberately: the HUD is inside the camera's own field of view, so
    // anything drawn on screen can be re-detected as a hand. Cyan sits at the
    // opposite end of CbCr from every skin tone, so the mask overlay can never
    // feed itself.
    float3 rgb = mix(float3(y), float3(0.05, 0.95, 0.85), m * 0.55);

    // Premultiplied output: the overlay window is non-opaque, and CAMetalLayer
    // composites premultiplied alpha.
    const float3 pre = rgb * panelAlpha;
    const float4 ov = overlay.sample(s, in.uv);   // already premultiplied by CoreGraphics
    return float4(ov.rgb + pre * (1.0 - ov.a),
                  ov.a + panelAlpha * (1.0 - ov.a));
}

/// Full-screen pass for the CoreGraphics-drawn layer alone: calibration targets,
/// crosshairs, readouts. Vector work and text belong in CoreGraphics; Metal's
/// job here is only to get the result on screen without a compositing round trip.
fragment float4 overlay_fragment(VertexOut in              [[stage_in]],
                                 texture2d<float> overlay  [[texture(0)]])
{
    constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
    return overlay.sample(s, in.uv);
}
