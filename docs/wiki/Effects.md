# Effects

Each in its row in Settings, or the theme's:

- **Text Effect**, what the text, the lines and the bars do: **Rainbow** runs them through the colors, **Shimmer** sweeps a glint across them now and then, **Glow** gives them a halo, **Flicker** fails like a neon sign.
- **Background Effect**, what goes on behind the menus, in the window: **Matrix**, a rain of glyphs; **Fire**, pixel flames burning up from under the window; **Stars**, a starfield drifting by; **Snow**, snow falling.
- **Selector Effect**, what goes on round the selected line: **Sparkles** fly off its four corners, left and right; **Welding** sparks burst from its corners and scatter, white hot, then yellow, orange and red; **Lightning** crackles out of it; **Rainbow**, a pixel rainbow, runs down from under it and fades away.
- **Screen Effect**, a picture tube's or a tape's look over the whole screen: **Scanlines**; **CRT**, a tube's curved face with scanlines, glow and darker corners; **VHS**, a tape's color bleed and noise.
- **Transition**, how one window gives way to the next: **Fade**; **Cube**, the window turning over like a cube's face with the next on another, which one at random, or always one way (**Cube Left**, **Cube Right**, **Cube Up**, **Cube Down**); **Ripple**, the old rippling out as the new ripples in; **Wave**, a wave running out from a corner and dying away, the new window behind it; **Drop**, a drop falling in a corner, the new window inside its spreading ring.

<table>
<tr><th width="50%">Cube</th><th width="50%">Drop</th></tr>
<tr><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/transition-cube.gif" width="100%" alt="Transition: Cube" /></td><td><img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/transition-drop.gif" width="100%" alt="Transition: Drop" /></td></tr>
<tr><td>YouTube on the main menu: the window turns over, YouTube on the next face.</td><td>A drop falls in a corner, and its ring spreads the next window across the screen.</td></tr>
</table>

**Never over a video.** The effects and the menu music rest while a video plays, in the window, behind the menus or in mpv's own; while it loads; while its menu is open; and while a player's screen is up. A window changes without its transition into or out of a player: a video is always shown as it is.

The GPU draws the text, background and screen effects and the Ripple, Wave and Drop transitions: they need a build with Qt Shader Tools, as the releases and the OSD/OS image are ([BUILDING.md](https://github.com/mehmetraif/OSD-OS/blob/main/BUILDING.md)), and Settings offers them only where Qt draws with a GPU. The selector effects, Fade and the cubes work everywhere. A screen effect has the GPU draw the screen twice, into a picture and then through the effect. Menus at rest aren't drawn again, so they cost nothing more; moving effects draw them about 30 times a second. At a CRT's 480 or 576 lines that is a sixth of the work of 1080p.
