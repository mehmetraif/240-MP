# 240-MP OS

A Raspberry Pi OS Lite (64-bit, Trixie) image that boots straight into 240-MP: flash it, plug the Pi into the TV, and the first thing on screen is the app. It is built with Raspberry Pi's own image builder, [pi-gen](https://github.com/RPi-Distro/pi-gen), so the kernel, firmware, Wi-Fi/Bluetooth drivers and the patched FFmpeg that mpv's Pi 4 HEVC decoding relies on are exactly Raspberry Pi OS's. This directory only adds one stage on top of Raspberry Pi OS Lite.

<img src="boot-screen.gif" width="480" alt="The boot screen: a pixel-art VHS cassette whose tape winds from the left reel onto the right one as the progress bar fills, and the list of services coming up">

## What is different from a manual install

Compared with flashing Raspberry Pi OS Lite and running `scripts/install.sh` ([INSTALL.md](../INSTALL.md)):

- **The app comes first.** `240mp.service` starts as soon as the display driver is up (after `basic.target`), not after every other service (`multi-user.target`).
- **The rest waits for it.** Wi-Fi (NetworkManager), Bluetooth, mDNS (`avahi-daemon`) and, if enabled, SSH hold back until the app has drawn its first frame. Then they start one after another, in that order.
- **The boot screen.** While those services start, the app shows a pixel-art VHS cassette: its reels turn, and the tape winds off the left reel onto the right one as the progress bar fills, plus a line per service (`[ OK ] WI-FI`, …). It ends with a check that the network is actually online. The startup module opens once it is done, so modules that need the network find it ready. Any key closes the boot screen early; the services carry on regardless.
- **A quiet boot.** There is no rainbow splash, no one-second firmware delay (`boot_delay=0`), no kernel text, logo or cursor on `tty1`, and no login prompt on `tty1`.
- **Less running.** The image has:
  - no apt, man-db, e2scrub or dpkg-backup timers (they wake the SD card at random times, mid-movie included);
  - no cron;
  - no Raspberry Pi Connect agent.

  cloud-init applies Raspberry Pi Imager's settings on the first boot and is then switched off, because otherwise its stages delay every boot.
- **Stopping isn't powering off.** `systemctl stop` and `systemctl restart` leave the Pi on. Quit in the app still powers it off, and Exit to Terminal still drops to a login shell, as with `install.sh`.

Everything else (the launcher, in-app updates, Exit to Terminal, the data directory in `~/.local/share/240-MP`) is the same as a manual install. The launcher, stop helper and terminal unit are taken from `scripts/install.sh` at build time.

## Flashing

1. In Raspberry Pi Imager, choose **Use custom** and pick the `.img.xz`.
2. Use Imager's OS customisation to set up Wi-Fi, a user, SSH, the locale and the keyboard. It is applied on the first boot.
3. The image's own user is `pi` (or whatever `FIRST_USER_NAME` was at build time), and the app runs as that user. Logging in is only needed for Exit to Terminal or SSH:
   - If the image was built with a password (`FIRST_USER_PASS`), you can log in as `pi`.
   - If it was built without one, the `pi` account is locked. Log in as the user Imager's customisation creates.

### HDMI or a CRT

The display output is set in `240mp-display.txt` on the boot partition (the FAT one any computer can open). To switch, copy one of the presets next to it over that file:

| Preset | Output |
|---|---|
| `240mp-display-hdmi.txt` | HDMI, resolution auto-detected (the default) |
| `240mp-display-crt-ntsc.txt` | Composite, NTSC, 4:3 |
| `240mp-display-crt-pal.txt` | Composite, PAL, 4:3 |

The rest of `config.txt` matches the settings [INSTALL.md](../INSTALL.md) documents, including the per-model drivers and overclocking.

## Building

The image needs a 240-MP arm64 tarball (`240-MP-<version>-linux-arm64.tar.gz`, as the release workflow builds it).

**On GitHub:**

1. Run the **OS image** workflow from the Actions tab (on a fork, enable Actions first). It builds the app from the chosen branch, then the image, on an arm64 runner. It also runs on pull requests that touch the image or the boot screen.
2. The image is the run's `240mp-os-image` artifact.

The run gives the `pi` user the repository secret `OS_FIRST_USER_PASS` as its password. Without that secret the account is locked.

The app in these images is built as `dev`, which turns its self-update off. That way a branch image can't swap itself for a release that doesn't have its changes.

**Locally:** with Docker on an arm64 Linux host (an x86 host works too, through QEMU emulation, but takes hours), run:

```bash
FIRST_USER_PASS='…' os/build.sh path/to/240-MP-<version>-linux-arm64.tar.gz
```

The image lands in `os/work/pi-gen/deploy/`. `os/build.sh` fetches pi-gen at a pinned commit of its `arm64` branch and builds stages 0–2 (Raspberry Pi OS Lite), then `stage-240mp`. Settings, all through the environment:

| Variable | Default | |
|---|---|---|
| `FIRST_USER_PASS` | — | Password of the first user. Without one, the account is locked. |
| `FIRST_USER_NAME` | `pi` | The first user; the app runs as this user. |
| `MP240_DISPLAY` | `hdmi` | Initial display preset: `hdmi`, `crt-ntsc` or `crt-pal`. |
| `ENABLE_SSH` | `0` | `1` enables SSH (it then also waits for the app, after mDNS). |
| `TARGET_HOSTNAME` | `240mp` | |
| `IMG_NAME` | `240mp-os` | |
| `WPA_COUNTRY`, `LOCALE_DEFAULT`, `KEYBOARD_KEYMAP`, `KEYBOARD_LAYOUT`, `TIMEZONE_DEFAULT`, `PUBKEY_SSH_FIRST_USER`, `PUBKEY_ONLY_SSH`, `DEPLOY_COMPRESSION` | pi-gen's | Passed through to pi-gen. |
| `MP240_NATIVE` | `0` | `1` runs pi-gen's `build.sh` directly (a Debian host, as root) instead of in Docker. |
| `MP240_PREPARE_ONLY` | `0` | `1` sets up the pi-gen tree and its config, then stops. |
| `PI_GEN_REF` | pinned | pi-gen commit to build from. |

## How the boot works

1. **Firmware.** It loads the kernel with no splash and no delay.
2. **Kernel.** It boots quietly and logs to `tty3`, so `tty1` stays black.
3. **systemd reaches `basic.target`.** `240mp.service` starts: `wait-for-display` holds it (at most five seconds) until the KMS driver has a display connector, then the launcher runs as in a manual install.
4. **The first frame is on screen.** The app writes `/run/240mp/ready` (`MP240_READY_FILE`).
5. **The held-back units start.** These are the ones listed in `/etc/240mp/boot-units`. Each has a `240mp-defer.conf` drop-in that runs `/usr/lib/240mp/wait-for-app` before it starts and orders it after the unit before it.
   - `wait-for-app` returns as soon as the ready file exists, or after 20 seconds whatever happens.
   - It returns at once when the app isn't starting this boot at all.
   - It is a wait, not an `After=240mp.service` ordering, on purpose: the worst a wait can cost is its timeout, while an ordering cycle with an early-boot unit could stall the whole boot.
6. **The boot screen follows them.** `BootProgress` (`src/boot/`) polls `systemctl` for the units in `MP240_BOOT_UNITS_FILE`. It closes once every one has settled (started, failed, or skipped because its condition failed), when a key is pressed, or after a minute.

Outside this image neither environment variable is set, so `BootProgress` does nothing and a normal install is unaffected. It also stays out of the way when the app restarts after the boot has finished.

`/etc/240mp/boot-units` lists `unit|LABEL` pairs. You can change a label there. To hold back another service, give it the same drop-in and add it to the list.

### Measuring

The app logs when its first frame appeared and when each service settled, relative to the app's start:

```bash
journalctl -b -u 240mp | grep '\[boot\]'
systemd-analyze critical-chain 240mp.service
systemd-analyze blame
```

## Notes

- An image built from a release tarball keeps in-app updates, which install releases from [anthonycaccese/240-mp](https://github.com/anthonycaccese/240-mp). A release without `BootProgress` still runs on this image. It just never writes the ready file, so the held-back services start after their 20-second timeout instead of right away.
