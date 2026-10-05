#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Builds the 240-MP OS image: Raspberry Pi OS Lite (arm64, Trixie) from pi-gen,
# plus the stage in os/stage-240mp. See os/README.md.
#
# Usage:
#   [FIRST_USER_PASS=...] os/build.sh path/to/240-MP-<version>-linux-arm64.tar.gz
#
# The tarball is what the release workflow (or a native arm64 build plus
# `cmake --install` into a usr/local tree) produces. The image lands in
# os/work/pi-gen/deploy/.
#
# Settings (environment):
#   FIRST_USER_PASS   password of the first user; without one the account is
#                     locked and people log in as the user Imager creates
#   FIRST_USER_NAME   default "pi"; the user the app runs as
#   MP240_DISPLAY     hdmi (default), crt-ntsc or crt-pal
#   ENABLE_SSH        0 (default) or 1
#   TARGET_HOSTNAME   default "240mp"
#   IMG_NAME          default "240mp-os"
#   WPA_COUNTRY, LOCALE_DEFAULT, KEYBOARD_KEYMAP, KEYBOARD_LAYOUT,
#   TIMEZONE_DEFAULT, PUBKEY_SSH_FIRST_USER, PUBKEY_ONLY_SSH,
#   DEPLOY_COMPRESSION      passed to pi-gen as-is when set
#   MP240_NATIVE=1    run pi-gen's build.sh directly (a Debian host, as root)
#                     instead of build-docker.sh
#   MP240_PREPARE_ONLY=1  set up the pi-gen tree and config, then stop
#   PI_GEN_REF        pi-gen commit to build from (pinned below)
#   WORK              scratch directory (default os/work)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${HERE}/.." && pwd)

TARBALL=${1:-${MP240_TARBALL:-}}
if [ -z "${TARBALL}" ] || [ ! -f "${TARBALL}" ]; then
    echo "usage: [FIRST_USER_PASS=...] $0 <240-MP-<version>-linux-arm64.tar.gz>" >&2
    exit 2
fi
TARBALL=$(realpath "${TARBALL}")

# pi-gen insists on a password once the first-boot rename wizard is off. With
# none given, hand it a random one and lock the account: the app runs as that
# user all the same, and people log in as the user Raspberry Pi Imager creates.
MP240_LOCK_FIRST_USER=0
if [ -z "${FIRST_USER_PASS:-}" ]; then
    FIRST_USER_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
    MP240_LOCK_FIRST_USER=1
    echo "note: no FIRST_USER_PASS; the first user's password will be locked." >&2
fi

# The arm64 branch of pi-gen builds the 64-bit images; pinned so a build is
# reproducible. Bump deliberately.
PI_GEN_REPO=${PI_GEN_REPO:-https://github.com/RPi-Distro/pi-gen}
PI_GEN_REF=${PI_GEN_REF:-4d8ee447dd3d37e8b0ef8752e460d9082d9d435d}
WORK=${WORK:-${HERE}/work}
PIGEN="${WORK}/pi-gen"
STAGE="${PIGEN}/stage-240mp"

# ── pi-gen at the pinned commit ───────────────────────────────────────────────
if [ ! -d "${PIGEN}/.git" ]; then
    mkdir -p "${PIGEN}"
    git -C "${PIGEN}" init -q
    git -C "${PIGEN}" remote add origin "${PI_GEN_REPO}"
fi
git -C "${PIGEN}" fetch -q --depth 1 origin "${PI_GEN_REF}"
git -C "${PIGEN}" checkout -q --force FETCH_HEAD
git -C "${PIGEN}" clean -qfdx -e work -e deploy

# Lite (stage2) is the base; only our stage exports an image.
touch "${PIGEN}/stage2/SKIP_IMAGES"

# ── Our stage, with the pieces generated from this repo ───────────────────────
# Docker builds copy the pi-gen directory into the container, so the stage has
# to live inside it.
cp -a "${HERE}/stage-240mp" "${STAGE}"
mkdir -p "${STAGE}/01-app/files"
# pi-gen silently skips a prerun.sh or NN-run.sh that isn't executable, which
# would leave the stage without its root filesystem or the app. Don't rely on
# the checkout having kept the bits (a ZIP download, a Windows clone).
chmod +x "${STAGE}/prerun.sh" "${STAGE}"/*/[0-9][0-9]-run.sh

# The launcher, stop helper and exit-to-terminal unit are taken verbatim from
# scripts/install.sh, so the image and a manual install never drift apart.
extract() {
    awk -v marker="$1" '
        $0 ~ "<< .?" marker ".?$" { on = 1; next }
        on && $0 == marker        { exit }
        on                        { print }
    ' "${REPO_ROOT}/scripts/install.sh"
}
extract LAUNCHER_SCRIPT > "${STAGE}/01-app/files/240mp-launcher"
extract STOP_HELPER     > "${STAGE}/02-system/files/240mp-stop"
extract TERMINAL_UNIT   > "${STAGE}/02-system/files/240mp-terminal.service"
for f in 01-app/files/240mp-launcher 02-system/files/240mp-stop; do
    head -n1 "${STAGE}/${f}" | grep -q '^#!' \
        || { echo "error: could not extract ${f} from scripts/install.sh" >&2; exit 1; }
done
head -n1 "${STAGE}/02-system/files/240mp-terminal.service" | grep -q '^\[Unit\]' \
    || { echo "error: could not extract 240mp-terminal.service from scripts/install.sh" >&2; exit 1; }

cp "${TARBALL}" "${STAGE}/01-app/files/240mp.tar.gz"

# ── pi-gen config ─────────────────────────────────────────────────────────────
# %q-quoted: pi-gen sources this file, and a password may hold any character.
CONFIG="${PIGEN}/config"
{
    setting() { printf '%s=%q\n' "$1" "$2"; }
    setting IMG_NAME                       "${IMG_NAME:-240mp-os}"
    setting PI_GEN_RELEASE                 "240-MP OS"
    setting TARGET_HOSTNAME                "${TARGET_HOSTNAME:-240mp}"
    setting FIRST_USER_NAME                "${FIRST_USER_NAME:-pi}"
    setting FIRST_USER_PASS                "${FIRST_USER_PASS}"
    # The app's service runs as FIRST_USER_NAME, so it must keep its name: no
    # first-boot rename wizard (which would also fight the app for tty1).
    setting DISABLE_FIRST_BOOT_USER_RENAME 1
    setting ENABLE_SSH                     "${ENABLE_SSH:-0}"
    setting DEPLOY_COMPRESSION             "${DEPLOY_COMPRESSION:-xz}"
    setting STAGE_LIST                     "stage0 stage1 stage2 stage-240mp"
    for var in WPA_COUNTRY LOCALE_DEFAULT KEYBOARD_KEYMAP KEYBOARD_LAYOUT \
               TIMEZONE_DEFAULT PUBKEY_SSH_FIRST_USER PUBKEY_ONLY_SSH; do
        if [ -n "${!var:-}" ]; then
            setting "${var}" "${!var}"
        fi
    done
    # Read by the stage's own scripts, so they have to reach their environment.
    printf 'export MP240_DISPLAY=%q\n' "${MP240_DISPLAY:-hdmi}"
    printf 'export MP240_LOCK_FIRST_USER=%q\n' "${MP240_LOCK_FIRST_USER}"
} > "${CONFIG}"

# ── Build ─────────────────────────────────────────────────────────────────────
if [ "${MP240_PREPARE_ONLY:-0}" = "1" ]; then
    echo "pi-gen tree ready in ${PIGEN} (config: ${CONFIG}); not building."
    exit 0
fi
cd "${PIGEN}"
if [ "${MP240_NATIVE:-0}" = "1" ]; then
    ./build.sh -c "${CONFIG}"
else
    ./build-docker.sh -c "${CONFIG}"
fi
shopt -s nullglob
images=("${PIGEN}"/deploy/*240mp*)
echo "Image: ${images[*]:-(none found in ${PIGEN}/deploy)}"
