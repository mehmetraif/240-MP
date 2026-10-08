#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# OSD/OS installer for Raspberry Pi OS Trixie (arm64)
#
# Usage:
#   bash install.sh             # install latest release
#   bash install.sh v1.2.0      # install a specific release tag
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="mehmetraif/OSD-OS"
INSTALL_DIR="/opt/osdos"
LAUNCHER="/usr/local/bin/osdos"
SYSTEMD_SERVICE="/etc/systemd/system/osdos.service"

# ── Resolve version ────────────────────────────────────────────────────────────
VERSION="${1:-latest}"
if [ "$VERSION" = "latest" ]; then
    echo "Fetching latest release tag..."
    VERSION=$(curl -fsSL \
        "https://api.github.com/repos/${REPO}/releases/latest" \
        | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")
fi
echo "Installing OSD/OS ${VERSION}"

TARBALL="OSD-OS-${VERSION}-linux-arm64.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"

# ── Verify architecture ────────────────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "Error: this installer is for arm64 (aarch64). Detected: $ARCH"
    exit 1
fi

# ── An install from 240-MP's days ─────────────────────────────────────────────
# OSD/OS was 240-MP. An install of that (240-MP's own installer) ran
# /opt/240mp through 240mp.service: its service and what it put around the
# system go, so the two never fight over the screen. The app moves its data
# folder (~/.local/share/240-MP) over to its own on its first start.
if [ -e /etc/systemd/system/240mp.service ] || [ -d /opt/240mp ] || [ -e /usr/local/bin/240mp ]; then
    echo "Removing the 240-MP install this replaces..."
    if [ -e /etc/systemd/system/240mp.service ]; then
        sudo systemctl disable --now 240mp.service 2> /dev/null || true
        sudo rm -f /etc/systemd/system/240mp.service /etc/systemd/system/240mp-terminal.service
        sudo systemctl daemon-reload
    fi
    sudo rm -f /usr/local/bin/240mp /usr/local/bin/240mp-stop /etc/udev/rules.d/99-240mp-tty.rules
    sudo rm -rf /opt/240mp
fi

# ── Install runtime dependencies ──────────────────────────────────────────────
echo "Installing runtime dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    libqt6quick6 \
    libqt6qml6 \
    libqt6opengl6 \
    libqt6network6 \
    libqt6svg6 \
    qt6-svg-plugins \
    qt6-wayland \
    qml6-module-qtquick \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-window \
    qml6-module-qtquick-effects \
    libsdl2-2.0-0 \
    libpcsclite1 \
    libmpv2 \
    mpv

# ── udev rule: allow tty group to open /dev/tty0 for VT switching ─────────────
echo 'KERNEL=="tty0", GROUP="tty", MODE="0620"' \
    | sudo tee /etc/udev/rules.d/99-osdos-tty.rules > /dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger /dev/tty0

# ── Choose install owner ──────────────────────────────────────────────────────
# Asked up front so the extract step can hand /opt/osdos to the user the app
# will run as — the launcher applies in-app staged updates there without root.
echo ""
read -r -p "Install systemd autostart service? [y/N] " AUTOSTART_REPLY
SERVICE_USER=""
if [[ "${AUTOSTART_REPLY}" =~ ^[Yy]$ ]]; then
    read -r -p "Run service as user [default: pi]: " SERVICE_USER
    SERVICE_USER="${SERVICE_USER:-pi}"
fi
OWNER_USER="${SERVICE_USER:-$USER}"

# Settings → Bluetooth talks to BlueZ as the user the app runs as, which
# BlueZ's D-Bus policy lets in through the bluetooth group.
if getent group bluetooth > /dev/null; then
    sudo usermod -aG bluetooth "${OWNER_USER}"
fi

# ── Download tarball ───────────────────────────────────────────────────────────
echo "Downloading ${TARBALL}..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL -o "${TMP_DIR}/${TARBALL}" "${DOWNLOAD_URL}"

# ── Extract to install directory ───────────────────────────────────────────────
# Tarball structure: usr/local/bin/osdos + usr/local/share/osdos/...
# We strip the usr/local prefix and place files directly in $INSTALL_DIR.
echo "Extracting to ${INSTALL_DIR}..."
sudo mkdir -p "${INSTALL_DIR}"
sudo tar -xzf "${TMP_DIR}/${TARBALL}" \
    --strip-components=3 \
    -C "${INSTALL_DIR}"

# Owned by the running user so the launcher can swap in staged in-app updates.
sudo chown -R "${OWNER_USER}:" "${INSTALL_DIR}"

# ── Create launcher ────────────────────────────────────────────────────────────
echo "Creating launcher at ${LAUNCHER}..."
sudo tee "${LAUNCHER}" > /dev/null << 'LAUNCHER_SCRIPT'
#!/usr/bin/env bash
# OSD/OS launcher — applies staged in-app updates, then auto-detects the
# display platform and execs the binary.
INSTALL_DIR="/opt/osdos"

# Tells the app this launcher knows how to apply staged updates; the in-app
# updater refuses to stage anything without it (older installs must re-run
# this installer once to pick up the launcher/osdos-stop contract).
# 2: osdos-stop also reboots on exit 12, so the quit menu offers Restart.
# 3: osdos-stop also writes a display preset on exit 20-29 and reboots, so
#    Settings offers Display Output (OSD/OS image), and the launcher takes the
#    output that preset names.
export OSDOS_LAUNCHER_API=3

# ── Apply a staged in-app update ───────────────────────────────────────────────
# The app downloads the release tarball to DATA_ROOT/updates and writes
# staged.sha256 ("<sha256>  <tarball>", coreutils format). Applied here, before
# exec, so it works identically for manual runs, desktop sessions, and the
# autostart service (which relaunches through this script on exit code 11 —
# see osdos-stop). Mirror any DATA_ROOT override into the app's environment
# (e.g. the systemd unit) or this block won't find the staging directory.
UPDATES_DIR="${DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/OSD-OS}/updates"

# Crash recovery: a previous apply died between the child renames below.
if [ ! -x "$INSTALL_DIR/bin/osdos" ] && [ -x "$INSTALL_DIR/.new/bin/osdos" ]; then
    for d in "$INSTALL_DIR"/.new/*; do mv -f "$d" "$INSTALL_DIR/"; done
    rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
fi

if [ -f "$UPDATES_DIR/staged.sha256" ] && [ -w "$INSTALL_DIR" ]; then
    if ( cd "$UPDATES_DIR" && sha256sum -c --status staged.sha256 ); then
        STAGED_TARBALL=$(awk '{print $2}' "$UPDATES_DIR/staged.sha256")
        rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
        mkdir -p "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
        # Extract fully, then swap top-level dirs (bin, share) via rename —
        # shrinks the power-loss window from the whole extraction to two mv's,
        # and drops files that no longer exist in the new release.
        if tar -xzf "$UPDATES_DIR/$STAGED_TARBALL" --strip-components=3 -C "$INSTALL_DIR/.new" \
           && [ -x "$INSTALL_DIR/.new/bin/osdos" ]; then
            for d in "$INSTALL_DIR"/.new/*; do
                name=$(basename "$d")
                [ -e "$INSTALL_DIR/$name" ] && mv "$INSTALL_DIR/$name" "$INSTALL_DIR/.old/$name"
                mv "$d" "$INSTALL_DIR/$name"
            done
            rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
            rm -f "$UPDATES_DIR/$STAGED_TARBALL" "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.json"
        else
            # Bad extract: keep the old tree; .failed stops a retry every boot.
            rm -rf "$INSTALL_DIR/.new" "$INSTALL_DIR/.old"
            mv -f "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.sha256.failed" 2>/dev/null
        fi
    else
        # Corrupt/partial stage — discard; the app re-offers the update.
        rm -f "$UPDATES_DIR/staged.sha256" "$UPDATES_DIR/staged.json"
    fi
fi

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
elif [ -n "${DISPLAY:-}" ]; then
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
else
    # No display server — use EGLFS for headless/kiosk mode (RPi Lite)
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
    export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
    export QT_QPA_EGLFS_KMS_ATOMIC=1

    # On a Pi 5, the output the OSD/OS image's display preset names
    # (/boot/firmware/osdos-display.txt: "# osdos-output: <type>"), in its mode
    # ("# osdos-mode: WxH") if the connector has it: a Pi 5 may keep HDMI on
    # beside a CRT, and there a composite mode's lines make PAL or NTSC. mpv
    # plays on it too (OSDOS_DRM_*). A Pi 4 has one output on at a time.
    KMS_CARD=""; KMS_OUTPUT=""; KMS_MODE=""
    PRESET=/boot/firmware/osdos-display.txt
    if [ -r "$PRESET" ] && tr -d '\0' 2>/dev/null < /proc/device-tree/model | grep -q '^Raspberry Pi 5'; then
        want=$(sed -n 's/^# osdos-output: *\([A-Za-z-]*\).*/\1/p' "$PRESET" | head -n1)
        mode=$(sed -n 's/^# osdos-mode: *\([0-9]*x[0-9]*\).*/\1/p' "$PRESET" | head -n1)
        for d in /sys/class/drm/card*-"${want:-none}"-*; do
            [ -e "$d" ] || continue
            n=$(basename "$d"); KMS_CARD="${n%%-*}"; KMS_OUTPUT="${n#*-}"
            if [ -n "$mode" ] && grep -qE "^${mode}i?\$" "$d/modes" 2>/dev/null; then
                KMS_MODE="$mode"
            fi
            break
        done
    fi

    # Point Qt EGLFS at the DRM card that has a real display pipeline. Render-
    # only nodes (v3d) have no connector dirs under /sys/class/drm and make Qt
    # fail with "drmModeGetResources failed (Operation not supported)". On
    # Pi3B+/Pi4 the display card happens to be card0 (auto-pick works), but on
    # Pi5 the v3d render node often enumerates first, so we must select the
    # right card explicitly. Prefer a connected connector; fall back to the
    # first card that has any connector at all.
    if [ -z "$KMS_CARD" ]; then
        for s in /sys/class/drm/card*-*/status; do
            [ -e "$s" ] || continue
            if [ "$(cat "$s")" = "connected" ]; then
                n=$(basename "$(dirname "$s")"); KMS_CARD="${n%%-*}"; break
            fi
        done
    fi
    if [ -z "$KMS_CARD" ]; then
        for d in /sys/class/drm/card*-*; do
            [ -e "$d" ] || continue
            n=$(basename "$d"); KMS_CARD="${n%%-*}"; break
        done
    fi
    if [ -n "$KMS_CARD" ] && [ -e "/dev/dri/$KMS_CARD" ]; then
        KMS_CONF="${XDG_RUNTIME_DIR:-/tmp}/osdos-kms.json"
        if [ -n "$KMS_OUTPUT" ]; then
            # Qt names an output by its type and number: HDMI-A-1 is HDMI1.
            qt_name="${KMS_OUTPUT%-*}"
            qt_name="${qt_name%-[AB]}${KMS_OUTPUT##*-}"
            printf '{ "device": "/dev/dri/%s", "outputs": [ { "name": "%s", "primary": true%s } ] }\n' \
                "$KMS_CARD" "$qt_name" "${KMS_MODE:+, \"mode\": \"$KMS_MODE\"}" > "$KMS_CONF"
            export OSDOS_DRM_DEVICE="/dev/dri/$KMS_CARD" OSDOS_DRM_CONNECTOR="$KMS_OUTPUT" \
                OSDOS_DRM_MODE="$KMS_MODE"
        else
            printf '{ "device": "/dev/dri/%s" }\n' "$KMS_CARD" > "$KMS_CONF"
        fi
        export QT_QPA_EGLFS_KMS_CONFIG="$KMS_CONF"
    fi
fi

export QT_QPA_PLATFORM
export QML2_IMPORT_PATH="/usr/lib/aarch64-linux-gnu/qt6/qml"

exec "${INSTALL_DIR}/bin/osdos" "$@"
LAUNCHER_SCRIPT

sudo chmod +x "${LAUNCHER}"

# ── Optional: systemd autostart ───────────────────────────────────────────────
if [[ "${AUTOSTART_REPLY}" =~ ^[Yy]$ ]]; then
    sudo tee "${SYSTEMD_SERVICE}" > /dev/null << UNIT
[Unit]
Description=OSD/OS Media Player
After=multi-user.target sound.target

[Service]
Type=simple
User=${SERVICE_USER}
SupplementaryGroups=tty video input
AmbientCapabilities=CAP_SYS_TTY_CONFIG
Environment=QT_QPA_PLATFORM=eglfs
Environment=QT_QPA_EGLFS_ALWAYS_SET_MODE=1
Environment=QT_QPA_EGLFS_KMS_ATOMIC=1
Environment=QML2_IMPORT_PATH=/usr/lib/aarch64-linux-gnu/qt6/qml
Environment=OSDOS_AUTOSTART=1
ExecStartPre=+-/usr/bin/systemctl stop osdos-terminal.service
ExecStart=${LAUNCHER}
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=10 12 20 21 22 23 24 25 26 27 28 29
ExecStopPost=+/usr/local/bin/osdos-stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

    # ExecStopPost helper: normal quit (exit 0) or a crash powers the Pi off as
    # before; exit 10 means the user chose "Exit to Terminal", so instead spawn a
    # login shell on tty1 (see views/Settings.qml). RestartPreventExitStatus=10
    # keeps Restart=on-failure from relaunching the app over that shell.
    # Exit 12 is the quit menu's "Restart": reboot (kept out of Restart=on-failure
    # the same way, so the app isn't started again on the way down).
    # Exit 20-29 is Settings → Display Output on the OSD/OS image: a display
    # preset written, then a reboot, kept out of Restart=on-failure as well.
    # Exit 11 is "Apply & Restart" from the in-app updater (views/Update.qml):
    # do nothing here — it's a failure status, so Restart=on-failure relaunches
    # through the launcher, which applies the staged update before exec.
    # A stop or restart from outside (systemctl stop/restart, a shutdown) ends the
    # app by signal — it exits 128+signal, or dies of it — and leaves the Pi on.
    sudo tee /usr/local/bin/osdos-stop > /dev/null << 'STOP_HELPER'
#!/usr/bin/env bash
# Called by osdos.service ExecStopPost. systemd sets $EXIT_STATUS to the app's
# exit code, or to the signal name if a signal killed it.

# Settings → Display Output on the OSD/OS image: the chosen preset (or the one
# before it, to go back) over osdos-display.txt, which the firmware reads only
# at power-on. A missing preset changes nothing; the app says so after the
# reboot. A Pi 5's SCART RGB needs its composite sync on GPIO 1.
display_output() {
    local boot=/boot/firmware src
    if [ "$1" = previous ]; then
        src="$boot/osdos-display-previous.txt"
    else
        src="$boot/osdos-display-$1.txt"
    fi
    [ -f "$src" ] || return 1
    [ "$1" = previous ] || cp -f "$boot/osdos-display.txt" "$boot/osdos-display-previous.txt"
    cp -f "$src" "$boot/osdos-display.txt.new" && mv -f "$boot/osdos-display.txt.new" "$boot/osdos-display.txt" || return 1
    if grep -q '^# osdos-output: DPI' "$boot/osdos-display.txt"; then
        echo "options drm_rp1_dpi force_csync=1" > /etc/modprobe.d/osdos-display.conf
    else
        rm -f /etc/modprobe.d/osdos-display.conf
    fi
    sync
}
# The app's codes for them (src/display/DisplayOutput.cpp): keep the two in step.
DISPLAY_PRESETS=(hdmi crt-ntsc crt-pal crt-gpio-ntsc crt-gpio-pal
                 scart-rgb-ntsc scart-rgb-pal scart-rgb-240p scart-rgb-288p previous)

case "${EXIT_STATUS:-}" in
    10) systemctl start osdos-terminal.service ;;
    11) : ;;  # in-app update restart — Restart=on-failure brings the app back up
    12) systemctl reboot ;;  # the quit menu's Restart
    2[0-9]) display_output "${DISPLAY_PRESETS[EXIT_STATUS - 20]}"; systemctl reboot ;;
    129|130|143|HUP|INT|TERM|KILL) : ;;  # stopped from outside, not by the user
    *)  systemctl poweroff ;;
esac
STOP_HELPER
    sudo chmod +x /usr/local/bin/osdos-stop

    # On-demand login shell for "Exit to Terminal". Not enabled (no boot race with
    # osdos.service); getty@tty1 stays masked. Started only by osdos-stop, and
    # stopped again by osdos.service's ExecStartPre when the app comes back.
    sudo tee /etc/systemd/system/osdos-terminal.service > /dev/null << 'TERMINAL_UNIT'
[Unit]
Description=OSD/OS exit-to-terminal login shell

[Service]
Type=idle
ExecStart=-/sbin/agetty --noclear tty1 linux
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
KillMode=process
Restart=no
TERMINAL_UNIT

    sudo systemctl mask getty@tty1.service autovt@.service
    sudo systemctl daemon-reload
    sudo systemctl enable osdos.service
    echo "Service installed and enabled."
    echo "Start now with: sudo systemctl start osdos"
fi

echo ""
echo "OSD/OS ${VERSION} installed successfully."
echo "Run: osdos"
