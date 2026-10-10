# Menu music

Settings → **Menu Music** plays a tune under the menus, over and over: the theme's (**Theme**), a file of your own (**File**, picked on the file browser), or none (**Off**). **Music Volume** sets how loud. It never plays over anything else: it stops the moment a video, a module's own music, a script or a web player is about to play, and starts again from the beginning back in the menus. Seven of the themes have their own, made by [make-menu-music.py](https://github.com/mehmetraif/OSD-OS/blob/main/scripts/make-menu-music.py).

- **MP3, WAV, OGG, Opus, FLAC, M4A or AAC**, played by mpv as it is.
- **A tracker's module, XM, MOD, S3M or IT**, played by mpv through ffmpeg's libopenmpt, or made into a WAV by openmpt123 where mpv can't play it. Demoscene's is an XM.
- **A MIDI file**, played by FluidSynth into a WAV once (kept in the cache folder) with a SoundFont: one beside it of the same name (`tune.sf2` beside `tune.mid`), else the first in the data folder's `soundfonts`, else the system's General MIDI one.

The OSD/OS image comes with FluidSynth, a small General MIDI SoundFont and openmpt123; elsewhere, install them for MIDI files ([BUILDING.md](https://github.com/mehmetraif/OSD-OS/blob/main/BUILDING.md)).
