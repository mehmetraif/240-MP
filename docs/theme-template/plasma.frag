#version 440
// The template theme's background effect: a plasma, the old demos' favourite,
// drifting slowly behind the menus in the colour scheme's colour. Faint, so
// the menus stay easy to read, on art pixels, and dithered as an old
// computer would: a pixel is lit or not, more of them where the plasma is
// brighter.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // the area it draws, in art pixels
    vec2 origin;      // where that is on the screen, in art pixels
    float time;       // seconds
    vec4 ink;         // the colour scheme's colour
    vec4 paper;       // its background
};

// A 4×4 ordered dither's threshold for an art pixel, 0 to 1.
float bayer2(vec2 a)
{
    a = floor(a);
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 a)
{
    return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void main()
{
    // The screen's art pixel, the same wherever on the screen this is
    // drawn: a dialog's ground (OsdGround) shows the same plasma as the
    // window's under it.
    vec2 p = floor(qt_TexCoord0 * size) + origin;
    float t = time * 0.4;
    vec2 centre = vec2(160.0, 120.0) + 60.0 * vec2(sin(t * 0.7), cos(t * 0.9));
    float v = sin(p.x * 0.05 + t) + sin(p.y * 0.07 - t * 1.3)
            + sin((p.x + p.y) * 0.04 + t * 0.6) + sin(length(p - centre) * 0.08 - t);
    // The plasma's brightness here, 0 to 1, and a pixel lit or not by it.
    float level = 0.5 + 0.125 * v;
    float lit = step(bayer4(p), level * level * 0.5);
    float alpha = 0.4 * lit;
    fragColor = vec4(ink.rgb * alpha, alpha) * qt_Opacity;
}
