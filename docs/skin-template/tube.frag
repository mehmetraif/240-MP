#version 440
// The skin template's own effect: a picture tube's phosphor stripes, a hum
// bar rolling slowly down the picture, and the effect's scanlines.
//
// After a change, compile it again into the .qsb that skin.json names:
//
//     qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o tube.frag.qsb tube.frag
//
// qsb comes with Qt Shader Tools: qt6-shader-baker on Debian and Raspberry
// Pi OS, in the bin folder of a Qt from Qt's installer.

// The point of the screen this runs for, 0 to 1 across and down, and the
// colour it shows there.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// What OSD/OS gives a shader. Every one starts with qt_Matrix and qt_Opacity,
// in that order; after them come any of the rest, by name, in any order:
// those it uses.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;  // the screen, in its pixels
    float px;         // screen pixels to an art pixel, a pixel of a 240-line picture
    float time;       // seconds, counting up while the effect's "animate" is true
    float scanlines;  // the effect's "scanlines", 0 to 1
};

// The screen as OSD/OS drew it.
layout(binding = 1) uniform sampler2D source;

void main()
{
    vec3 color = texture(source, qt_TexCoord0).rgb;
    vec2 pixel = qt_TexCoord0 * resolution;

    // Phosphor stripes: the screen's columns of pixels red, green and blue in
    // turn, a little brighter all over to make up for it.
    float stripe = mod(floor(pixel.x), 3.0);
    vec3 mask = vec3(stripe < 0.5 ? 1.0 : 0.7, abs(stripe - 1.0) < 0.5 ? 1.0 : 0.7, stripe > 1.5 ? 1.0 : 0.7);
    color *= mask * 1.2;

    // A hum bar: a band a little brighter, rolling down the picture once
    // every 20 seconds.
    float fromBar = abs(fract(qt_TexCoord0.y - time * 0.05) - 0.5);
    color *= 1.0 + 0.08 * smoothstep(0.35, 0.5, fromBar);

    // Scanlines: the foot of every line of art pixels darker.
    color *= 1.0 - scanlines * 0.7 * step(0.5, fract(pixel.y / px));

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0) * qt_Opacity;
}
