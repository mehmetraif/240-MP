#!/bin/bash -e

# USB drives: a USB stick or disk plugged in is mounted read-only under
# /media/usb, in a folder named after its label, and Local Files lists it at the
# top of its tree (src/modules/local_files/RemovableDrives); pulled out, its
# folder goes. Read-only, so a drive can be pulled out at any moment.

ETC="${ROOTFS_DIR}/etc"
LIB="${ROOTFS_DIR}/usr/lib/osdos"

install -d "${LIB}"
install -m 755 files/usb-mount "${LIB}/usb-mount"
install -m 644 files/osdos-usb-mount@.service "${ETC}/systemd/system/"
install -m 644 files/99-osdos-usb-mount.rules "${ETC}/udev/rules.d/"
