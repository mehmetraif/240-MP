#!/bin/bash -e

# Runs inside the image. FAT, exFAT, NTFS and HFS+ keep no owners of their own:
# a drive's files belong to the user the app runs as, as the film partition's
# do.

USER_ID=$(id -u "${FIRST_USER_NAME}")
GROUP_ID=$(id -g "${FIRST_USER_NAME}")
sed -i -e "s/@USER_ID@/${USER_ID}/" -e "s/@GROUP_ID@/${GROUP_ID}/" /usr/lib/osdos/usb-mount
install -d /media/usb
