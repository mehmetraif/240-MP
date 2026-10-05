#!/bin/bash -e

# The film partition: on the first boot the root partition grows to
# MP240_ROOT_SIZE GiB instead of to the end of the card, and the rest of the
# card becomes a partition of its own in exFAT, labelled 240-MP (see
# files/resize_early). Windows and macOS open it too, so films copied onto it
# from a computer show up in Local Files, which opens it by default. os/build.sh
# skips this sub-stage with MP240_ROOT_SIZE=0.

ROOT_MIB=$(( ${MP240_ROOT_SIZE:-8} * 1024 ))
ETC="${ROOTFS_DIR}/etc"

# In place of raspberrypi-sys-mods' own resize_early: a script of the same name
# in /etc/initramfs-tools/scripts overrides the one in /usr/share. The
# initramfs is built at the end, by pi-gen's export-image stage.
install -d "${ETC}/initramfs-tools/scripts/local-premount" "${ETC}/initramfs-tools/hooks"
sed "s/@ROOT_MIB@/${ROOT_MIB}/" files/resize_early \
	> "${ETC}/initramfs-tools/scripts/local-premount/resize_early"
chmod 755 "${ETC}/initramfs-tools/scripts/local-premount/resize_early"
install -m 755 files/240mp-media "${ETC}/initramfs-tools/hooks/240mp-media"

install -d "${ROOTFS_DIR}/media/240-MP"

install -d "${ETC}/systemd/system/240mp.service.d"
cat > "${ETC}/systemd/system/240mp.service.d/240mp-media.conf" << 'CONF'
# 240-MP OS: Local Files opens the film partition when its folder isn't set.
[Service]
Environment=MP240_MEDIA_DIR=/media/240-MP
CONF
