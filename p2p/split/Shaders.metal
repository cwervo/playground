// Shaders.metal — SwiftUI color effects for SplitCam.
// Compiled headlessly by build.sh into default.metallib.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Gold light orbiting the border of the tapped element: a hotspot travels
// around a rounded-rect edge glow, fading out over ~0.9s.
[[ stitchable ]] half4 goldOrbit(float2 position, half4 color, float2 size, float time) {
    float2 halfSize = size * 0.5;
    float2 p = position - halfSize;

    // Signed distance to a rounded rect inset just inside the bounds.
    float corner = 14.0;
    float2 d = abs(p) - (halfSize - corner);
    float sdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 2.0;

    // Glow hugging the border (±~6px), brightest right on the edge.
    float edgeGlow = exp(-sdf * sdf / 18.0);

    // Orbiting hotspot: 1.2 revolutions per second.
    float angle = atan2(p.y, p.x);
    float theta = fmod(time * 6.2831853 * 1.2, 6.2831853) - 3.14159265;
    float dAng = angle - theta;
    dAng = atan2(sin(dAng), cos(dAng));
    float spot = exp(-dAng * dAng * 6.0);

    float fade = clamp(1.0 - time / 0.9, 0.0, 1.0);
    float glow = edgeGlow * (0.22 + 1.4 * spot) * fade;

    half3 gold = half3(1.0, 0.84, 0.35);
    return half4(gold * half(glow), half(glow));
}
