# The OSD/OS image

## An operating system, not an app

240-MP is an app: it is installed on a system that is already set up, Raspberry Pi OS, Steam OS or macOS, and starts once that system has booted its own way, its splash, boot messages and login prompt or desktop included. The **OSD/OS** image ([os/README.md](https://github.com/mehmetraif/OSD-OS/blob/main/os/README.md)) is the system itself:

- **It boots into OSD/OS.** No rainbow splash, no boot messages, no login prompt: from the moment the Pi is switched on the screen is OSD/OS's, starting with its own boot screen: the OSD/OS cassette, its reels turning and its tape winding from one onto the other while the system comes up under it, a line per service.
- **No desktop, no window manager, no file manager.** There is no display server (X11 or Wayland) and no compositor: OSD/OS draws straight to the screen through the kernel's display driver, and mpv plays straight to it too ([Nothing between the app and the screen](#nothing-between-the-app-and-the-screen)).
- **Every screen is OSD/OS's own.** The boot screen, the menus, the file browser (Local Files' tree), the on-screen keyboard, the info screens, Settings, Bluetooth pairing, updates, and quitting, restarting or switching off: all of it is drawn by OSD/OS, in its own letters, and worked with a remote. It hands the screen over only to what plays: mpv for a video, and Chromium, full screen with nothing around it, for Netflix and Prime Video, whose players only run in a browser (and to sign in to YouTube), or a script of yours that asks for the screen.
- **No needless background jobs.** The services Raspberry Pi OS keeps, Wi-Fi, Bluetooth, the local network and SSH (when enabled), wait until OSD/OS is on screen and then start one after another. The apt, man-db, e2scrub and dpkg-backup timers that wake the SD card at random times, mid-film included, are gone, as are cron and the Raspberry Pi Connect agent, and cloud-init runs on the first boot only.
- **Films on the card.** The card's free space is a partition of its own, in exFAT, which Windows and macOS open too: copy films onto it from a computer and Local Files plays them.
- **USB drives as they are plugged in.** A USB stick or disk shows up in Local Files, under its label, and goes again when it is pulled out. It is mounted read-only, so it can be pulled out at any moment.
- **Linux underneath.** The image is Raspberry Pi OS Lite (64-bit), which is based on Debian 13 "trixie", built with Raspberry Pi's own image builder, pi-gen. The kernel, the firmware and the drivers are Raspberry Pi OS's, and OSD/OS adds one stage on top. What the image is made of, and under which licences, is in [os/NOTICE](https://github.com/mehmetraif/OSD-OS/blob/main/os/NOTICE).

As an app ([Install](https://github.com/mehmetraif/OSD-OS#get-it)), OSD/OS is the same on screen, on top of whatever the system around it runs.

## How it works

### Nothing between the app and the screen

<img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/display-path.svg" width="100%" alt="How the picture reaches the TV on a desktop, in a kiosk, on the OSD/OS image, and on the OSD/OS image with Transparent Background" />

On a desktop, OSD/OS and mpv are windows. They hand their frames to a compositor (labwc on Raspberry Pi OS), and the compositor holds the screen. A kiosk setup replaces the desktop with one full-screen window, but Xorg or cage still sits in between.

The OSD/OS image has no display server at all. OSD/OS draws through Qt's EGLFS platform straight to the kernel's KMS/DRM driver, the way Kodi does on LibreELEC. Only one program draws at a time (it holds the *DRM master*), so there are no windows to manage. `DisplayHandoff` gives the screen to whatever takes over and takes it back when that exits:

- mpv (`--vo=drm`) when a video plays
- a takeover script from the Scripts module
- Chromium, in `cage`, for Netflix and Prime Video, and for signing in to YouTube

With **Transparent Background**, mpv runs inside OSD/OS instead, as libmpv. OSD/OS then keeps the screen the whole time, draws the video as part of its own picture and lays its menus over it.

### On screen first at boot

<img src="https://raw.githubusercontent.com/mehmetraif/OSD-OS/main/docs/images/boot-order.svg" width="100%" alt="Boot order in a manual install and on the OSD/OS image" />

A manual install starts OSD/OS last, once every service is up. The OSD/OS image turns that around: OSD/OS starts as soon as systemd reaches `basic.target`. Wi-Fi, Bluetooth, the local network and SSH (when enabled) wait for its first frame, then start one after another. The boot screen follows them until the network is online. The details are in [os/README.md](https://github.com/mehmetraif/OSD-OS/blob/main/os/README.md).

### Inside the app

- At startup the shell (`AppCore`) finds the modules from their `modules/*/manifest.json`. Each module is a set of QML views, plus a C++ backend when it needs one.
- Keyboards, remotes and gamepads (through SDL2) all arrive as the same key events, so every screen works with the arrows, select and back.
- Playback goes through `MpvController`. mpv plays full screen on its own, or inside the app with Transparent Background.
- Settings are kept in `config.json`.

[ARCHITECTURE.md](https://github.com/mehmetraif/OSD-OS/blob/main/ARCHITECTURE.md) has the rest.
