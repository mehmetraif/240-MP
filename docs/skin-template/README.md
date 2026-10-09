# Skin template

A skin to copy and make your own. It brings all three things a skin can set, each of its own: its colors, a theme of its own pictures, and an effect drawn by a shader of its own, so each can be seen at work and changed.

![The template skin](../screenshots/skin-template.png)

| File | What it is |
|---|---|
| `skin.json` | The skin: its name, colors, theme and effect |
| `window.png`, `titlebar.png`, `hintbar.png`, `selection.png` | Its theme's pictures, the [theme template](../theme-template/)'s |
| `tube.frag` | Its effect's shader: phosphor stripes, a hum bar rolling down the picture, and scanlines |
| `tube.frag.qsb` | The shader compiled, which is what OSD/OS reads |

## Make it yours

1. **Copy this folder** into the `skins` folder of OSD/OS's data folder, under a name of your own:
   - Linux and the OSD/OS image: `~/.local/share/OSD-OS/skins/<name>/`
   - macOS: `~/Library/Application Support/OSD-OS/skins/<name>/`

   The folder's name is what Settings saves. A folder named like one of OSD/OS's own (`trinitron`, `late-show`, `green-screen`) is used in its place.
2. **Name it.** `"name"` in `skin.json` is what Settings → Skin shows: 28 characters at most, else the folder's name is shown.
3. **Change what you like**, or take a part out: what the skin leaves out is as Settings has it.
4. **Pick it** in Settings → Skin. A new folder is listed the next time Settings opens. While the skin is chosen, Settings hides the rows it sets (Color Scheme, Theme, Effect); None brings them back as they were. The window's frame shows with OSD Background set to Window.

To see a picture or a shader you changed in a skin already in use, restart OSD/OS: one already shown stays in memory.

## skin.json

```json
{
    "name": "Template",
    "colors": { "primary": "#F2E6C9", "surface": "#1B2A4A" },
    "theme": {
        "window":    { "image": "window.png", "border": 4 },
        "titleBar":  { "image": "titlebar.png", "border": [2, 2, 5, 2] },
        "hintBar":   { "image": "hintbar.png", "border": 3, "tile": "repeat" },
        "selection": { "image": "selection.png", "border": 3 }
    },
    "effect": { "shader": "tube.frag.qsb", "animate": true, "scanlines": 0.4 }
}
```

| Key | |
|---|---|
| `name` | What Settings shows |
| `colors` | A color scheme's name, as Settings → Color Scheme lists it (`"Video 1"`, `"Terminal"`), or two colors of its own, each `#rrggbb`: `primary`, the text, the lines and the selection, and `surface`, the background. OSD/OS draws in those two only, like a deck's on-screen display |
| `theme` | A theme's name, its folder's (`"dos"`, `"rounded"`, or one in the data folder's `themes`), or a theme of its own: its parts as in a `theme.json` (see the [theme template](../theme-template/)), its pictures in the skin's folder. `{}` is OSD/OS's own window, without a theme |
| `effect` | An effect's name, as Settings → Effect lists it (`"Scanlines"`, `"CRT"`, `"VHS"`, `"Off"`), or one of its own: the keys below |

### An effect of its own

| Key | |
|---|---|
| `scanlines` | Dark lines between the picture's, 0 (none) to 1 |
| `curvature` | A tube's curved face: the picture bulges, its corners going round, 0 to 1 |
| `glow` | A halo round light parts, 0 to 1 |
| `bleed` | A tape's color smeared sideways, red to the left and blue to the right, 0 to 1 |
| `noise` | Grain, moving, 0 to 1 |
| `vignette` | The corners darker, 0 to 1 |
| `animate` | `true` for a shader of its own that moves: `time` counts up for it, the screen drawn 20 times a second |
| `shader` | A shader of its own, a `.qsb` in the skin's folder, drawn in place of OSD/OS's |

Without `shader`, the numbers drive OSD/OS's own shader, as Settings → Effect's do. Green Screen's is `{ "scanlines": 0.6, "glow": 0.6, "curvature": 0.3, "vignette": 0.5 }`, and CRT is `{ "scanlines": 0.35, "curvature": 0.6, "glow": 0.35, "vignette": 0.5 }`.

With `shader`, the shader draws the whole screen, and does what it likes with the numbers: the template's uses `scanlines` and leaves the rest.

## A shader of its own

A shader is a small program the GPU runs once for every pixel of the screen, each time it is drawn. OSD/OS draws the screen into a picture and gives it to the shader as `source`; the shader says what color each point of the screen gets. `tube.frag` is one, with a comment on every step.

It is written in GLSL for Qt's shader tools (`#version 440`), and it takes:

- **`qt_TexCoord0`**: the point of the screen it runs for, 0 to 1 across and down. It reads `source` there, or anywhere else, and writes `fragColor`.
- **The uniform block** at binding 0. It starts with `mat4 qt_Matrix` and `float qt_Opacity`, in that order, as every one must; after them come any of these, by name, in any order: only those it uses.

| Name | Type | |
|---|---|---|
| `resolution` | `vec2` | The screen, in its pixels |
| `px` | `float` | Screen pixels to an art pixel, a pixel of a 240-line picture: 2 at 480 lines, 4 at 1080 |
| `time` | `float` | Seconds, counting up while `animate` is `true` |
| `scanlines`, `curvature`, `glow`, `bleed`, `noise`, `vignette` | `float` | The effect's numbers, 0 when left out |

- **`source`**, a `sampler2D` at binding 1: the screen as OSD/OS drew it.

**Compile it** after every change, into the `.qsb` that `skin.json` names, for every graphics API Qt draws with (OpenGL and OpenGL ES on the Pi, Metal on a Mac):

```sh
qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o tube.frag.qsb tube.frag
```

`qsb` comes with Qt Shader Tools: `sudo apt install qt6-shader-baker` on Debian and Raspberry Pi OS (it is `/usr/lib/qt6/bin/qsb`), or in the `bin` folder of a Qt from Qt's installer. Use the Qt OSD/OS runs on or an older one: a newer Qt's `.qsb` may not load in an older Qt. The template's is compiled with Qt 6.4, the oldest the releases are built with.

**Keep it light.** It runs for every pixel each time the screen is drawn: two million at 1080p, a sixth of that at a CRT's 480 lines. Each read of `source` costs; OSD/OS's own reads it seven times at most.

## When something is wrong

The log says which skin was read, `[AppCore] skin <folder>: <path>`, and what in it couldn't be used. On the OSD/OS image it is `journalctl -u osdos`; elsewhere see [Debugging & logs](../../BUILDING.md#debugging--logs).

- **Colors that aren't two `#rrggbb`** are drawn as Video 1.
- **A picture or a shader that isn't in the skin's folder** (a path or a link out of it) is refused: that picture's part is drawn as OSD/OS draws it, and the effect without the shader.
- **A shader that won't load**, one not compiled with `qsb`, or by a newer Qt: the log says `[Effect] … can't be used, OSD/OS's own in its place`, and the effect's numbers drive OSD/OS's shader instead. A shader that loads but leaves the screen unreadable: take its `.qsb` out of the skin's folder, or the folder out of `skins`, and restart OSD/OS. Without the file the effect is drawn by OSD/OS's shader; without the folder, there is no skin.
- **A `skin.json` that isn't JSON**: the skin isn't listed in Settings.
- **No Effect in Settings**: the build has no Qt Shader Tools (see [BUILDING.md](../../BUILDING.md)), or Qt draws without a GPU. A skin's colors and theme work all the same.
