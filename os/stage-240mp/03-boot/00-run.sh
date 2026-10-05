#!/bin/bash -e

# Boot partition: a quiet boot straight to the app, with the display preset in
# a file of its own next to config.txt, so switching between a CRT and HDMI is a
# file copy from any computer.

BOOT="${ROOTFS_DIR}/boot/firmware"
DISPLAY_PRESET="${MP240_DISPLAY:-hdmi}"
case "${DISPLAY_PRESET}" in
	hdmi|crt-ntsc|crt-pal) ;;
	*) echo "MP240_DISPLAY must be hdmi, crt-ntsc or crt-pal (got ${DISPLAY_PRESET})" >&2; exit 1 ;;
esac

install -m 644 files/config.txt "${BOOT}/config.txt"
install -m 644 files/240mp-display-hdmi.txt files/240mp-display-crt-ntsc.txt \
	files/240mp-display-crt-pal.txt "${BOOT}/"
install -m 644 "files/240mp-display-${DISPLAY_PRESET}.txt" "${BOOT}/240mp-display.txt"

# Kernel messages go to tty3 instead of tty1, with no logo and no cursor, so the
# screen stays black until the app draws its boot screen.
if ! grep -q 'vt.global_cursor_default=0' "${BOOT}/cmdline.txt"; then
	sed -i -e 's/console=tty1/console=tty3/' \
		-e 's/$/ quiet loglevel=3 logo.nologo vt.global_cursor_default=0 consoleblank=0/' \
		"${BOOT}/cmdline.txt"
fi
