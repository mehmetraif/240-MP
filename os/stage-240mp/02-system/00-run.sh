#!/bin/bash -e

# The app's service, its exit-to-terminal shell and stop helper (the last two
# taken from scripts/install.sh by os/build.sh), and the boot order: the units
# below hold back until the app is on screen, then start one after another.

ETC="${ROOTFS_DIR}/etc"
LIB="${ROOTFS_DIR}/usr/lib/240mp"

install -m 644 files/240mp.service "${ETC}/systemd/system/240mp.service"
sed -i "s/@FIRST_USER_NAME@/${FIRST_USER_NAME}/" "${ETC}/systemd/system/240mp.service"
install -m 644 files/240mp-terminal.service "${ETC}/systemd/system/"
install -m 644 files/240mp-cloud-init-once.service "${ETC}/systemd/system/"
install -m 755 files/240mp-stop "${ROOTFS_DIR}/usr/local/bin/240mp-stop"
install -m 644 files/99-240mp-tty.rules "${ETC}/udev/rules.d/"
install -d "${LIB}"
install -m 755 files/wait-for-app files/wait-for-display "${LIB}/"

# unit|LABEL, in start order. The boot screen lists them in this order too.
UNITS=(
	"NetworkManager.service|WI-FI"
	"bluetooth.service|BLUETOOTH"
	"avahi-daemon.service|LOCAL NETWORK"
)
if [ "${ENABLE_SSH}" = "1" ]; then
	UNITS+=("ssh.service|SSH")
fi

install -d "${ETC}/240mp"
{
	echo "# Services 240-MP's boot screen follows, as unit|LABEL, in start order."
	echo "# All but the last hold back until the app is on screen (see their"
	echo "# 240mp-defer.conf drop-ins); the last is the network-online check."
	printf '%s\n' "${UNITS[@]}"
	echo "NetworkManager-wait-online.service|ONLINE"
} > "${ETC}/240mp/boot-units"

PREVIOUS=""
for entry in "${UNITS[@]}"; do
	unit="${entry%%|*}"
	install -d "${ETC}/systemd/system/${unit}.d"
	{
		echo "# 240-MP OS: start once the app is on screen, after the service before it."
		if [ -n "${PREVIOUS}" ]; then
			echo "[Unit]"
			echo "After=${PREVIOUS}"
			echo
		fi
		echo "[Service]"
		echo "ExecStartPre=+-/usr/lib/240mp/wait-for-app"
	} > "${ETC}/systemd/system/${unit}.d/240mp-defer.conf"
	PREVIOUS="${unit}"
done

# The connection check gives up after 20 s instead of a minute: with no network
# configured it would otherwise hold the boot screen (and network-online.target)
# that long.
install -d "${ETC}/systemd/system/NetworkManager-wait-online.service.d"
cat > "${ETC}/systemd/system/NetworkManager-wait-online.service.d/240mp.conf" << 'EOF'
# 240-MP OS: don't hold the boot for a minute when there is no network.
[Service]
Environment=NM_ONLINE_TIMEOUT=20
EOF

# The Pi's own Bluetooth. bthelper@hciN (pi-bluetooth, started by udev before
# bluetooth.service) brings the adapter up with hciconfig to set it up, which
# skips the kernel's power-on initialisation, and relied on bluetoothd running
# 5 s later to power it off and on again. Here bluetoothd waits for the app
# (above), so the adapter was left half set up and BlueZ couldn't turn it on.
# Leave it down instead, as pi-bluetooth itself now does
# (RPi-Distro/pi-bluetooth#39): bluetoothd powers it on when it starts. With
# bluetoothd running already (an adapter plugged in later), the kludge works.
install -d "${ETC}/systemd/system/bthelper@.service.d"
cat > "${ETC}/systemd/system/bthelper@.service.d/240mp.conf" << 'EOF'
# 240-MP OS: leave the adapter down, for bluetoothd to power on (AutoEnable).
[Service]
ExecStartPost=-/bin/sh -c 'pidof bluetoothd > /dev/null || /bin/hciconfig %I down'
EOF

# Built without a password (os/build.sh), the first user can't log in, and Exit
# to Terminal would end at a login nobody can pass: it logs that user in by
# itself instead. Whoever is at the keyboard could take the card out anyway.
if [ "${MP240_LOCK_FIRST_USER:-0}" = "1" ]; then
	install -d "${ETC}/systemd/system/240mp-terminal.service.d"
	cat > "${ETC}/systemd/system/240mp-terminal.service.d/240mp-autologin.conf" << EOF
# 240-MP OS built without a password: the terminal logs ${FIRST_USER_NAME} in by itself.
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${FIRST_USER_NAME} --noclear tty1 linux
EOF
fi
