# Skins

Settings → **Skin** dresses the window, apart from the color scheme: the shapes of OSD Background's window frame, the title and hint bars and the selected line, and icons of its own. A skin gives only shapes. They are drawn in the color scheme's two colors, so every skin goes with every scheme. Two come with OSD/OS: **DOS**, a double line round the window, and **Rounded**, round corners on the window, the bars and the selected line.

A skin is a folder in the data folder's `skins` (`~/.local/share/OSD-OS/skins/` on Linux and the OSD/OS image, `~/Library/Application Support/OSD-OS/skins/` on macOS), holding a `skin.json` and its pictures. To make one, start from the **[skin template](https://github.com/mehmetraif/OSD-OS/blob/main/docs/skin-template/)**: it dresses every part, draws an icon and uses every option, and its script draws the pictures from text drawings. A skin's `skin.json` looks like this:

```json
{
    "name": "Rounded",
    "window":    { "image": "window.png", "border": 4 },
    "titleBar":  { "image": "bar.png", "border": 3 },
    "hintBar":   { "image": "bar.png", "border": 3 },
    "selection": { "image": "bar.png", "border": 3 }
}
```

- **Every part is optional**: one left out is drawn as OSD/OS draws it. `window` is the frame of OSD Background's window (Window, with Window Frame On or Shadow).
- **A picture has two colors**, a PNG (or GIF, BMP): white where the color scheme's color goes, black where its background goes, transparent where nothing is drawn (round the window's frame, what is around the window shows). Each of its pixels is an art pixel, a pixel of a 240-line picture, scaled up to the screen without blurring.
- **`border`** is how many of the picture's pixels at each edge are its frame: one number, or `[left, top, right, bottom]`. The corners stay as drawn, the edges stretch along the part, and the middle fills the rest. `"tile": "repeat"` repeats the edges instead of stretching them (for a dotted line).
- **`icons`** draws icons of its own in place of OSD/OS's, by name: a module's by its folder's name (`"youtube"`), the main menu's `"logo"`, any other by its file's name (`"settings"`), as in `"icons": { "logo": "tv.png" }`. An icon is drawn in the title bar's color, from its shape.
- **One of OSD/OS's own** is replaced by a folder of the same name in the data folder. The log says which skin was read, and what in it could not be used. A skin made before skins had their name, a `theme.json` of these parts in the data folder's `themes`, is read as one.
