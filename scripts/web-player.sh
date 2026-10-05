#!/bin/sh
# Opens a streaming service's own web player full screen, for 240-MP's Netflix
# and Prime Video modules (src/modules/web_player/WebPlayerBackend.h):
#
#   web-player.sh <service> <url>
#
# The module runs this as a takeover: on a headless Pi the app has handed the
# screen over before this starts, and takes it back once everything this
# starts has exited. Closing the browser (Ctrl+W or Alt+F4), or holding BACK in
# 240-MP, ends the run.
#
# Needs a Chromium-based browser with Widevine, which these players require.
# On Raspberry Pi OS: `sudo apt install chromium libwidevinecdm0`, and `cage`
# to give the browser a screen when there is no desktop.
#
# Environment (optional):
#   MP240_WEB_PLAYER_UA  the browser's user agent (default: see below)
set -u

if [ $# -ne 2 ]; then
    echo "usage: $0 <service> <url>"
    exit 2
fi
SERVICE=$1
URL=$2
DATA=${DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/240-MP}
# The browser's own profile for this service, so its sign-in survives between
# runs. WebPlayerBackend::signOut() deletes it.
PROFILE=$DATA/$SERVICE/browser
mkdir -p "$PROFILE"

if [ "$(uname -s)" = Darwin ]; then
    # A new instance on its own profile, so -W waits for exactly this one.
    if [ -d "/Applications/Google Chrome.app" ]; then
        exec open -W -n -a "Google Chrome" --args --kiosk --no-first-run \
            --user-data-dir="$PROFILE" "$URL"
    fi
    exec open -W -n -a Safari "$URL"
fi

# The same browsers, in the same order, as WebPlayerBackend checks for.
BROWSER=
for candidate in chromium chromium-browser google-chrome-stable google-chrome; do
    if command -v "$candidate" >/dev/null 2>&1; then
        BROWSER=$candidate
        break
    fi
done
if [ -z "$BROWSER" ]; then
    echo "No Chromium found. On Raspberry Pi OS: sudo apt install chromium libwidevinecdm0 cage"
    exit 127
fi

set -- \
    --kiosk \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --hide-crash-restore-bubble \
    --password-store=basic \
    --autoplay-policy=no-user-gesture-required \
    --ozone-platform-hint=auto \
    --enable-spatial-navigation

# These players play on an Arm Linux browser only when it says it is ChromeOS,
# as Raspberry Pi OS's Chromium already does; say so here too, with the
# browser's real version, so other builds work the same.
UA=${MP240_WEB_PLAYER_UA:-}
case "$(uname -m)" in
    aarch64|arm64|armv7l|armv6l)
        if [ -z "$UA" ]; then
            VERSION=$("$BROWSER" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
            if [ -n "$VERSION" ]; then
                UA="Mozilla/5.0 (X11; CrOS aarch64 15917.71.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$VERSION Safari/537.36"
            fi
        fi
        ;;
esac
if [ -n "$UA" ]; then
    set -- "$@" --user-agent="$UA"
fi

# With a desktop, the browser's window simply covers 240-MP's.
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
    exec "$BROWSER" "$@" "$URL"
fi

# Without one, cage gives the browser the screen 240-MP just handed over. The
# app holds no login seat for cage to share, so cage opens the display and the
# input devices itself, which the app's video and input groups allow.
if ! command -v cage >/dev/null 2>&1; then
    echo "cage is not installed: sudo apt install cage"
    exit 127
fi
export LIBSEAT_BACKEND="${LIBSEAT_BACKEND:-noop}"
# cage puts its socket in XDG_RUNTIME_DIR, which a service has no login
# session to provide: then a private one for this run, removed afterwards,
# even when 240-MP ends the run (it signals the whole process group).
RUNTIME=
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -w "${XDG_RUNTIME_DIR:-/nonexistent}" ]; then
    RUNTIME=$(mktemp -d "${TMPDIR:-/tmp}/240mp-$SERVICE.XXXXXX") || exit 1
    export XDG_RUNTIME_DIR="$RUNTIME"
fi
trap '[ -n "$RUNTIME" ] && rm -rf "$RUNTIME"' EXIT
trap 'exit 143' TERM INT HUP
cage -- "$BROWSER" "$@" --ozone-platform=wayland "$URL"
