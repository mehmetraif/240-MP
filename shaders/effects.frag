#version 440
// The screen's effects (Settings → Effect, or a skin's): one pass over the
// picture the app has drawn, the layer of the item that holds the whole
// screen in Main.qml. Each effect is off at 0 and at its strongest at 1. A
// skin's own shader declares this block too, or any part of it: Main.qml
// sets every member by name.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;  // the screen, in its pixels
    float px;         // screen pixels to an art pixel, a pixel of a 240-line picture
    float time;       // seconds, for what moves
    float scanlines;  // the dark between the picture's lines
    float curvature;  // a tube's face: the picture bulges, its corners round off
    float glow;       // light parts glowing into the dark round them
    float bleed;      // a tape's colour smeared sideways off its picture
    float noise;      // grain, moving
    float vignette;   // the corners darker
};

layout(binding = 1) uniform sampler2D source;

// Where the picture a point of the tube's face shows comes from: further out
// the further it is from the middle, so the picture bulges.
vec2 bulge(vec2 uv)
{
    vec2 c = uv * 2.0 - 1.0;
    c *= 1.0 + curvature * 0.15 * (c.yx * c.yx);
    return c * 0.5 + 0.5;
}

// A number from 0 to 1 for a point, without sin(), whose precision a phone's
// GPU (or a Pi's) may not keep.
float grain(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main()
{
    vec2 uv = bulge(qt_TexCoord0);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
        return;
    }
    // An art pixel, in the picture's coordinates.
    vec2 art = px / resolution;
    vec3 color = texture(source, uv).rgb;
    if (bleed > 0.0) {
        // A tape's colour lags its picture: red from a little to the left,
        // blue from a little to the right, up to an art pixel and a half.
        float d = bleed * 1.5 * art.x;
        color.r = texture(source, uv - vec2(d, 0.0)).r;
        color.b = texture(source, uv + vec2(d, 0.0)).b;
    }
    if (glow > 0.0) {
        // Light spilling over from what is round it, where that is brighter:
        // a halo round light parts, the rest as it was.
        vec2 g = art * 1.5;
        vec3 around = (texture(source, uv + vec2(g.x, 0.0)).rgb + texture(source, uv - vec2(g.x, 0.0)).rgb
                     + texture(source, uv + vec2(0.0, g.y)).rgb + texture(source, uv - vec2(0.0, g.y)).rgb) * 0.25;
        color += max(around - color, 0.0) * glow;
    }
    if (scanlines > 0.0) {
        // Where in its line this pixel is, from 0 at its top to 1 at its
        // foot, the foot the dark between two lines. The screen's lines, not
        // the bulged picture's: curved lines a pixel or two apart would beat
        // against the screen's own into bands.
        float line = fract(qt_TexCoord0.y * resolution.y / px);
        color *= 1.0 - scanlines * 0.7 * smoothstep(0.4, 0.9, line);
    }
    if (curvature > 0.0) {
        // The tube's edge, soft over a pixel or two rather than stepped.
        vec2 w = 1.5 / resolution;
        vec2 edge = smoothstep(vec2(0.0), w, uv) * smoothstep(vec2(0.0), w, 1.0 - uv);
        color *= edge.x * edge.y;
    }
    if (vignette > 0.0) {
        vec2 c = uv - 0.5;
        color *= 1.0 - vignette * smoothstep(0.25, 0.75, dot(c, c) * 2.0);
    }
    if (noise > 0.0) {
        // An art pixel's grain, new at every tick of time.
        color += (grain(floor(uv * resolution / px) + fract(time * 1.618) * 97.0) - 0.5) * (0.3 * noise);
    }
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0) * qt_Opacity;
}
