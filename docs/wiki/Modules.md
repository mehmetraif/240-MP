# Modules

Playback is handled by modules, so a new service can join without changes to the rest. Think of each module as a different input on a VHS deck. OSD/OS plays through [mpv](https://github.com/anthonycaccese/240-MP/wiki/MPV), which the [install](https://github.com/mehmetraif/OSD-OS#get-it) puts in place. Some modules (like YouTube and NFC Reader) need more, as their sections say; 240-MP's wiki pages, linked from the headings, have its own notes on setting them up.

## Ambient:Mode ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Ambient-Mode))

A backdrop for the room, like the art or wallpaper modes of modern TVs: a video of your choice (a fireplace, an aquarium, rain on a window) plays on a loop, with your own music over it if you like.

- Supported video file types: `"mp4", "mkv", "avi", "mov", "m4v", "webm", "wmv", "flv", "f4v", "mpg", "mpeg", "vob"`
- Playlist support for audio tracks using `m3u` and `m3u8` files
- Mix video with a different audio track
- Loops forever until you stop it

## Emby Module ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Emby))

Your films and series from an [Emby](https://emby.media) media server, on your network or through Emby Connect: browse its libraries, carry on where you stopped, and watch.

- Supported library types: `movies, tvshows, homevideos, boxsets`
- Username / password authentication, or Emby Connect (emby.media cloud account, with server picker)
- Select specific libraries to display
- Continue Watching, Next Up and Resume Playback
- Autoplay next episode in a season (optional, off by default)
- Intro/Credit skip using the server's chapter markers (when detected)
- Collections support
- Select preferred audio/subtitle track before playback and switch tracks during playback
- Full library browsing by letter
- Show/Season browsing
- Video quality selection: Direct Playback (Default) or Transcode options

## Jellyfin ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Jellyfin))

Your films and series from a [Jellyfin](https://jellyfin.org) media server, the free and open one: sign in with Quick Connect, browse its libraries, carry on where you stopped, and watch.

- Supported library types: `movies, tvshows, homevideos, boxsets`
- "Quick Connect" authentication
- Select specific libraries to display
- Continue Watching, Next Up and Resume Playback
- Autoplay next episode in a season (optional, off by default)
- Collections support
- Select preferred audio/subtitle track before playback and switch tracks during playback
- Full library browsing by letter
- Show/Season browsing
- Video quality selection: Direct Playback (Default) or Transcode options

## Local Files ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Local-Files))

The films, videos and photos you keep yourself, in a folder on the device, a USB drive or a network share (on the OSD/OS image, the SD card's own film partition): browse the folders and play.

- Supported file types: `"mp4", "mkv", "avi", "mov", "m4v", "webm", "wmv", "flv", "f4v", "mpg", "mpeg", "vob"`
- On the OSD/OS image, films go on the SD card itself: its **OSD-OS** partition opens on Windows and macOS like a USB stick, and Local Files opens it ([os/README.md](https://github.com/mehmetraif/OSD-OS/blob/main/os/README.md#films-on-the-card))
- Playlist support using `m3u` and `m3u8` files
- Folder browsing as a horizontal tree: the open folders run along a line across the screen, every folder in the current one branches off to a few of its own entries, and the folder under the cursor branches once more
- **Recently Watched**, **Favorites** and **Search** lead the tree: what you played last, what you marked (right on a file, then **Add to Favorites**), and file and folder names anywhere in the media folder and on the USB drives plugged in, typed on an on-screen keyboard
- **USB drives** plugged in come next, each under its label (`USB: KINGSTON`), and go when they are pulled out, the tree closing back from one that was open. On the OSD/OS image they are mounted read-only by themselves ([os/README.md](https://github.com/mehmetraif/OSD-OS/blob/main/os/README.md#usb-drives)); on a desktop or a Mac, whatever the system mounts as it comes is there too
- Loop playback
- Shuffle playback
- Playback history
- Switch audio/subtitle tracks during playback
- Back during a video opens its menu: subtitles, looping and Scaling, then Favorites, Play at Startup, Browse Local Files and Close Video. With Transparent Background it lies over the picture, which plays on: looping and Scaling change as it plays, and the subtitles reload it from where it is when you go back to it. Without, the video stops for the menu and starts again from where it was when you go back to it, with the settings as you left them

## Netflix and Prime Video

What Netflix and Prime Video carry in your country, browsed in OSD/OS's own menus and played in the service's own player: OSD/OS shows the catalogue, the service plays the title.

- Browse what the service carries in your country in the same tree as Local Files: **Recently Watched** and **Favorites** first, then **Search** (on an on-screen keyboard), **Movies** and **Series** by Popular and by genre, a page of titles at a time with **More…** at the end
- Select on a title plays it straight away in the service's own web player, full screen. It opens at the title's own page on the service where [Wikidata](https://www.wikidata.org) knows it (by its TMDB or IMDb id), and at the service's search for it otherwise. **Netflix Home** / **Prime Video Home** opens the service as it is. OSD/OS comes back when the player closes, with the tree as you left it
- The catalogue comes from [TMDB](https://www.themoviedb.org)'s API, which needs a free API key: put it (a v3 key or a v4 read access token) on the first line of `tmdb_api_key.txt` in the data folder. Each module's settings set the country and the language of the titles
- Neither service has an API for a front end like this one, and their streams are DRM-protected, so playback is the official site in Chromium with Widevine, not an OSD/OS view: use it with a keyboard (arrow keys move between titles) or a mouse
- A title's info screen (story, genre, director or creator, cast, rating) comes up when the cursor has rested on it for 3 seconds, or at once with right; Settings → **Info Screen** sets the seconds, or **Key** for right only, or **Off**
- Right on the info screen (or on the title, with the info screen off) offers its options: **Add to Favorites** or **Remove from Favorites**
- Come back by holding back (`[ESC]` / `[B]`) for two seconds, or by closing the browser (`Ctrl+W`)
- **Sign in** in its settings opens the service's sign-in page full screen, to sign in with a keyboard before you browse (a title you open asks too, while you aren't). Each keeps its sign-in between visits; **Sign out** forgets it
- Needs `chromium`, `libwidevinecdm0` and, without a desktop, `cage` and `wtype` (on Raspberry Pi OS: `sudo apt install chromium libwidevinecdm0 cage wtype`); the OSD/OS image has them. With `wtype`, holding back closes the browser the way `Ctrl+W` does, which keeps a sign-in made moments before: Chromium saves new cookies only every half minute, and stopping it outright loses them
- Off by default; enable them in Settings
- This product uses the TMDB API but is not endorsed or certified by TMDB. Which service carries a title where comes from [JustWatch](https://www.justwatch.com), through TMDB

## NFC Reader ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-NFC-Reader))

Tap a card to play, the way a tape goes in a deck: each NFC card stands for a video, a file, a YouTube video or a Plex title, and plays it when it touches the reader.

- Start video playback via NFC cards
  - Supports the mapping of video paths, YouTube URLs and content from a Plex library
- Reader support:
  - `PN532 USB` — recommended. Needs no drivers or daemon on any platform, so it also works on immutable distros like SteamOS
  - `ACS ACR122U` and other PC/SC contactless readers — needs `pcscd` (see `scripts/setup-nfc-reader.sh`)
- Readers are detected automatically; no configuration needed
- Maps cards to videos via per-card text files in a `nfc_tags` data directory
- Tapping an unknown card auto-creates a stub tag file for it

## Playlists

Your own lists of videos, like a mixtape, from several modules at once: Local Files, YouTube, Jellyfin and Emby on one list, played from where they live or downloaded to play without the network.

- Lists of videos from Local Files, YouTube, Jellyfin and Emby together, played as one: **In Order**, carrying on from where the list stopped (it asks), or **Shuffle**, in a new order each time. **Play from Here** on a video starts there. mpv's display has ◄ ► for the previous and next video
- **Online** playlists play each video from where it lives: a file from Local Files, a YouTube video as the YouTube module plays it (its Advanced settings, through yt-dlp), a Jellyfin or Emby item streamed from its server
- **Offline** playlists play only what is on the device: Local Files' files as they are, and a copy of every other video, downloaded in the background into a **Playlists** folder in Local Files' folder (the **Download Folder** setting can name another). On OSD/OS image that is the card's OSD-OS partition. A video is downloaded once, whatever lists it is on, and deleted once no offline list has it
- YouTube videos download with yt-dlp in the YouTube module's resolution, codec and audio language (ffmpeg puts a video above 360p back together; the OSD/OS image has it). Jellyfin and Emby items download as their original file, where the server lets the user download (a user without the right shows **Not Allowed**)
- Add videos from inside the module (**Add Videos**: a tree of Local Files, YouTube, Jellyfin and Emby, with their libraries, shows and seasons), from a video's options in Local Files and YouTube (►, **Add to Playlist**), or with ► on **PLAY** on a Jellyfin or Emby item's page. A list can also be started from there (**New Online Playlist**, **New Offline Playlist**)
- Back during a video opens its menu: subtitles, looping and Scaling, then Browse Playlists and Close Video. With Transparent Background, the list plays on behind the menus and the main menu's first row takes it back
- Netflix and Prime Video play in the service's own player, so they can't go on a playlist

## Plex ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Plex))

Your films and series from a [Plex](https://www.plex.tv) Media Server: sign in with a code at plex.tv/link, choose the server and the profile, browse its libraries, carry on where you stopped, and watch.

- Supported library types: `Movies, TV Shows, Other Videos`
- Server switching
- User profile switching and auto sign in
- Select specific libraries to display
- Continue Watching and Resume
- Autoplay next episode in a season (optional, off by default)
- Write an NFC card for any movie, episode, season or show from its detail screen to use with the NFC Reader module
- Hub, Playlist, Collection and Category support
- Folder browsing — walk a library by its on-disk folder structure
- Movie editions
- Select preferred audio/subtitle track before playback and switch tracks during playback
- Full library browsing by letter
- Show/Season browsing
- Video quality selection: Direct Playback (Default) or Transcode options

## Scripts ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Scripts))

Other programs on the machine, started from the menu through your own shell scripts: FieldStation42, RetroArch, an update, anything a script can run.

- Run your own `.sh` scripts from a folder, so OSD/OS can launch anything else on the machine (FieldStation42, RetroArch, `yt-dlp -U`, updates)
- Two run modes per script, set in its `.txt` file:
    - `console` — OSD/OS stays on screen and shows the script's output
    - `takeover` — the script gets the whole display, and OSD/OS returns when it exits
- A `.txt` file beside each script sets its display name and options; one is created for you automatically the first time a script is seen
- Mark a script as a favorite to put it on the main menu alongside the other modules (press play/pause on it in the list)
- Optionally auto-run one script when OSD/OS starts
- Off by default; enable it in Settings and point it at your scripts folder

## Weather ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-Weather))

The weather, shown the way a cable weather channel showed it in the 90s: current conditions and a three-day forecast for your town, and for up to six more places.

- Inspired by [WeatherStar 3000+](https://github.com/netbymatt/ws3kp) by netbymatt
- Integrates with Open-Meteo to provide weather forecasts for worldwide locations
- Integrates with NWS to provide current conditions for US locations
- For your main location it displays Current Conditions and Extended (3-day forecast)
- Can display forecast data for 6 additional locations
- Supports background music, US/Metric Units and 12-hour/24-hour time display

## YouTube ([Wiki](https://github.com/anthonycaccese/240-MP/wiki/Module:-YouTube))

YouTube without the YouTube app: your subscriptions, channels and playlists, search, and playback through mpv and yt-dlp, with no account needed.

- List content from YouTube RSS feeds and playback via mpv + yt-dl (no account needed)
- Browse it all in the same tree as Local Files: **Recently Watched**, **Favorites**, **Search**, **Subscriptions**, **Channels**, **Playlists** and **Watch Later**
- Search YouTube on an on-screen keyboard (through yt-dlp), twenty matches at a time with **More…** at the end
- View Subscriptions: Browse the latest videos from your configured channels as a reverse chronological list
- Browse videos by Channel, and by Playlist
- A video's info screen (channel, date, length, views, description), like the streaming catalogues'; right on it (or, with the info screen off, on the video) offers its options: add it to **Favorites**, or save it to a local **Watch Later** list
- **Recently Watched** is your local watch history
- Resume Playback
- **Advanced** in its settings holds the details:
    - **Playback Resolution**: 240p to 2160p. 480p, the default, suits a CRT and a Pi.
    - **Video Codec**: H.264 first, which a Pi decodes in hardware, or **Any** for whatever looks best (VP9 or AV1, needed above 1080p).
    - **Max Frame Rate**: Any, or 30 where a video also has 60.
    - **Scaling**.
    - **Audio Language**: the original track, or a dub where a video has one.
    - **Subtitles** in a **Subtitle Language**: Off, On, or With Auto for YouTube's automatic captions too.
    - **Playback Speed**: 0.75x to 2x.
    - **Resume Playback**, and whether to **Display Shorts** (on by default).
- Back during a video opens its menu: the Advanced settings for it, then Favorites, Play at Startup, Watch Later, Browse YouTube and Close Video. With Transparent Background it lies over the picture, which plays on: speed and Scaling change as it plays, and the others reload it from where it is when you go back to it. Without, the video stops for the menu and starts again from where it was when you go back to it, with the settings as you left them
- **Sign in** in its settings, if you want to, opens Google's sign-in page full screen in Chromium, to sign in with a keyboard. yt-dlp then searches and plays as that account, which YouTube asks for fewer bot checks and lets play age-restricted videos. **Sign out** forgets it
    - YouTube can block an account used through yt-dlp, as [yt-dlp's wiki](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#youtube) warns, so sign in with a spare one
    - Needs Chromium, with `cage` and `wtype` without a desktop (see Netflix and Prime Video), or Google Chrome on a Mac
- Needs yt-dlp, and Deno for full YouTube support ([BUILDING.md](https://github.com/mehmetraif/OSD-OS/blob/main/BUILDING.md)). The [OSD/OS](https://github.com/mehmetraif/OSD-OS/blob/main/os/README.md) image comes with both and keeps yt-dlp up to date
