#!/bin/bash -e

# Runs inside the image. The film partition is mounted for the user the app runs
# as, since exFAT keeps no owners of its own; a card too small for one leaves
# the folder on the root filesystem, where it belongs to that user too. It is
# read-only: films are copied onto it from a computer, the app only plays them,
# and a Pi switched off at the wall can't leave it half-written. nofail and the
# short device timeout keep a boot without it from waiting.

USER_ID=$(id -u "${FIRST_USER_NAME}")
GROUP_ID=$(id -g "${FIRST_USER_NAME}")
chown "${USER_ID}:${GROUP_ID}" /media/240-MP

if ! grep -q '/media/240-MP' /etc/fstab; then
	echo "LABEL=240-MP  /media/240-MP  exfat  ro,nofail,noatime,uid=${USER_ID},gid=${GROUP_ID},umask=0022,x-systemd.device-timeout=10s  0  0" >> /etc/fstab
fi
