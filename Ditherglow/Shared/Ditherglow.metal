#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Port of ditherglow-reference's gradient (`fmain`) and its Dither texture (`fpost`, case 5),
// fused into one SwiftUI pass: the gradient is evaluated once at each dither block's centre.

static float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

static float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

// OKLab blending keeps mixes vivid instead of going muddy/grey.
static float3 linearToOklab(float3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = pow(l, 1.0 / 3.0); m = pow(m, 1.0 / 3.0); s = pow(s, 1.0 / 3.0);
    return float3(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

static float3 oklabToLinear(float3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3(
         4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// 8x8 Bayer threshold via bit-reversed interleave of (x^y, x).
static float bayer8(uint2 p) {
    uint x = p.x & 7, xy = (p.x ^ p.y) & 7;
    uint v = ((xy & 1) << 5) | ((x & 1) << 4) | ((xy & 2) << 2) | ((x & 2) << 1) | ((xy & 4) >> 1) | ((x & 4) >> 2);
    return (float(v) + 0.5) / 64.0;
}

/// The gradient in OKLab at `uv` (0...1, y down). `colors` holds `n` packed sRGB triples.
static float3 gradientLab(float2 uv, float aspect, float t, float seed, device const float *colors, int n) {
    float2 p = uv;
    p.x *= aspect;

    // Gentle domain warp so the fields swirl rather than just slide.
    float2 w = p;
    w += 0.18 * float2(sin(p.y * 2.3 + t * 0.61 + seed),
                       cos(p.x * 1.9 - t * 0.47 + seed * 1.7));
    w += 0.06 * float2(sin(w.y * 2.7 - t * 0.83),
                       cos(w.x * 2.4 + t * 0.71));

    float3 acc = 0.0;
    float accChroma = 0.0;
    float total = 0.0;
    for (int i = 0; i < n; i++) {
        float fi = float(i) + seed;
        // Each colour source wanders on its own Lissajous path.
        float2 c = float2(
            aspect * (0.5 + 0.48 * sin(t * (0.23 + 0.071 * fi) + fi * 2.399)),
            0.5 + 0.48 * cos(t * (0.19 + 0.053 * fi) + fi * 1.618));
        // Softened distance: plain IDW spikes at each source and leaves a visible pinch.
        float2 dv = w - c;
        float d = sqrt(dot(dv, dv) + 0.03);
        // Low falloff power = long, soft transitions between sources.
        float radius = 0.5 + 0.15 * sin(t * 0.3 + fi * 3.1);
        float wt = pow(radius / d, 2.4);
        float3 rgb = float3(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]);
        float3 lab = linearToOklab(srgbToLinear(rgb));
        acc += wt * lab;
        accChroma += wt * length(lab.yz);
        total += wt;
    }

    // Averaging opposite hues cancels a/b and drifts through grey.
    // Keep the averaged hue but restore the averaged chroma, capped so it can't draw a hard edge.
    float3 lab = acc / total;
    float chroma = length(lab.yz);
    float targetChroma = accChroma / total;
    lab.yz *= targetChroma / max(chroma, max(targetChroma * 0.55, 0.015));
    return lab;
}

/// Soft pixels, Bayer-dithered in lightness only so hues don't fringe.
[[ stitchable ]] half4 ditherglow(float2 position, half4 color,
                                  float2 size, float time, float seed, float blockSize,
                                  device const float *colors, int count) {
    uint2 b = uint2(position / blockSize);
    float2 uv = (float2(b) + 0.5) * blockSize / size;
    float3 lab = gradientLab(uv, size.x / max(size.y, 1.0), time, seed, colors, count / 3);

    // Clamp to sRGB before dithering, as the reference does by going through a texture.
    lab = linearToOklab(srgbToLinear(saturate(linearToSrgb(oklabToLinear(lab)))));
    float step = 0.08;
    lab.x = (floor(lab.x / step + bayer8(b)) + 0.5) * step;
    return half4(half3(saturate(linearToSrgb(oklabToLinear(lab)))), 1.0);
}
