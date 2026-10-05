#!/bin/bash -e

# 240-MP itself, laid out the way scripts/install.sh lays it out: the release
# tarball unpacked under /opt/240mp and owned by the user the app runs as (so
# the launcher can swap in-app updates in), the launcher at /usr/local/bin.
# os/build.sh drops the tarball and the launcher (taken from install.sh) in files/.

install -d "${ROOTFS_DIR}/opt/240mp"
# The tarball holds ./usr/local/{bin,share}; strip that prefix like install.sh.
tar -xzf files/240mp.tar.gz --strip-components=3 -C "${ROOTFS_DIR}/opt/240mp"
if [ ! -x "${ROOTFS_DIR}/opt/240mp/bin/240mp" ]; then
	echo "files/240mp.tar.gz has no usr/local/bin/240mp" >&2
	exit 1
fi

install -m 755 files/240mp-launcher "${ROOTFS_DIR}/usr/local/bin/240mp"

on_chroot << EOF
chown -R "${FIRST_USER_NAME}:" /opt/240mp
EOF
