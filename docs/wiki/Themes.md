# Themes

Settings → **Theme** sets the whole look at once: the color scheme, the skin, the effects and the menu music. Each of those has its row under Theme, saying THEME while it is the theme's: change one, or turn it Off, and it stays as you set it until another theme is picked. Eight come with OSD/OS:

| Theme | Colors | Skin | Effects | Music |
|---|---|---|---|---|
| **Trinitron** | Video 1 | Rounded | a CRT tube; Cube | a calm arpeggio |
| **Late Show** | Late Night | DOS | a VHS tape, flickering text; Fade | a slow, swung tune with a record's crackle |
| **Green Screen** | phosphor green | DOS | a glowing tube, glowing text; Wave | none |
| **Matrix** | green on black | DOS | Matrix rain, glowing text, Lightning; Ripple | a pulsing minor tune |
| **Inferno** | amber on brown | Rounded | Fire under the window, Welding; Cube | a driving tune |
| **Arcade** | Synthwave | Rounded | Stars, Rainbow text, a Rainbow drip; Cube | a bouncy chiptune |
| **Winter** | ice on night blue | Rounded | Snow, Shimmer, Sparkles; Drop | a music box |
| **Demoscene** | gold on purple | DOS | Stars, glowing text, Sparkles; Cube Left | a tracker's XM |

<table>
<tr><th width="50%">Trinitron</th><th width="50%">Late Show</th></tr>
<tr><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-trinitron.gif" width="100%" alt="Theme: Trinitron" /></td><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-late-show.gif" width="100%" alt="Theme: Late Show" /></td></tr>
<tr><td>Video 1 in Rounded windows on a tube's curved face: scanlines, glow and darker corners. Windows turn over like a cube.</td><td>Late Night's white on black in DOS windows, with a tape's color bleed and noise and text flickering like a neon sign. Windows fade.</td></tr>
</table>

<table>
<tr><th width="50%">Green Screen</th><th width="50%">Matrix</th></tr>
<tr><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-green-screen.gif" width="100%" alt="Theme: Green Screen" /></td><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-matrix.gif" width="100%" alt="Theme: Matrix" /></td></tr>
<tr><td>A phosphor green of its own, DOS windows, a glowing tube and glowing text. Windows come in on a wave from a corner.</td><td>Green on black: Matrix rain behind the menus, glowing text, and lightning crackling out of the selected line. Windows ripple.</td></tr>
</table>

<table>
<tr><th width="50%">Inferno</th><th width="50%">Arcade</th></tr>
<tr><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-inferno.gif" width="100%" alt="Theme: Inferno" /></td><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-arcade.gif" width="100%" alt="Theme: Arcade" /></td></tr>
<tr><td>Amber on brown: pixel flames burning up from under the window, and a welder's sparks bursting from the selected line's corners.</td><td>Synthwave's colors: a starfield, text running through the rainbow, and a pixel rainbow dripping from under the selected line.</td></tr>
</table>

<table>
<tr><th width="50%">Winter</th><th width="50%">Demoscene</th></tr>
<tr><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-winter.gif" width="100%" alt="Theme: Winter" /></td><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/theme-demoscene.gif" width="100%" alt="Theme: Demoscene" /></td></tr>
<tr><td>Ice on night blue: snow falling, a glint sweeping across the text, and sparkles flying off the selected line. Windows spread from a drop.</td><td>Gold on purple: a starfield, glowing text and sparkles, windows turning left like a demo's cube, and a tracker's XM for its music.</td></tr>
</table>

A theme is a folder in the data folder's `themes` (`~/.local/share/OSD-OS/themes/` on Linux and the OSD/OS image, `~/Library/Application Support/OSD-OS/themes/` on macOS), holding a `theme.json` and its files. To make one, start from the **[theme template](https://github.com/mehmetraif/OSD-OS/blob/main/docs/theme-template/)**: every part of its own, its effects' shaders and a MIDI tune. A `theme.json` names what OSD/OS has, or brings its own:

```json
{
    "name": "Inferno",
    "colors": { "primary": "#FFC860", "surface": "#1C0500" },
    "skin": "rounded",
    "effects": {
        "background": "Fire",
        "selector": "Welding",
        "transition": "Cube"
    },
    "music": "inferno.ogg"
}
```

- **Every part is optional**: one left out is drawn without it (the colors Video 1's).
- **`colors`** is a color scheme's name (`"Video 1"`), or the two colors everything is drawn in: `primary`, the text, the lines and the selection, and `surface`, the background.
- **`skin`** is a skin's name (its folder's: `"dos"`), or a skin of its own: its parts as in a `skin.json`, its pictures in the theme's folder.
- **`effects`** gives any of `text`, `background`, `selector`, `screen` and `transition` an effect's name ([Effects](https://github.com/mehmetraif/OSD-OS/wiki/Effects)) or `"Off"`. A text, background or screen effect can be its own: numbers, or a shader (see the template).
- **`music`** is a file in its folder ([Menu music](https://github.com/mehmetraif/OSD-OS/wiki/Menu-Music)).
- **One of OSD/OS's own** is replaced by a folder of the same name in the data folder. The log says which theme was read, and what in it could not be used.
