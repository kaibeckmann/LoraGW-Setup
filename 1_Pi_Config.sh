#!/bin/bash

if [ $(id -u) -ne 0 ]; then
	echo "Installer must be run as root."
	echo "Try 'sudo bash $0'"
	exit 1
fi

MODEL=`cat /proc/device-tree/model`

echo "This script configure a Raspberry Pi"
echo "Raspian for being a LoRaWAN Gateway"
echo
echo "Device is $MODEL"
echo
echo "Run time ~5 minutes. Reboot required."
echo
echo -n "CONTINUE? [Y/n] "
read
if [[ "$REPLY" =~ ^(no|n|N)$ ]]; then
	echo "Canceled."
	exit 0
fi

# These functions have been copied from excellent Adafruit Read only tutorial
# https://github.com/adafruit/Raspberry-Pi-Installer-Scripts/blob/master/read-only-fs.sh
# the one inspired by my original article http://hallard.me/raspberry-pi-read-only/
# That's an excellent demonstration of collaboration and open source sharing
# 
# Given a filename, a regex pattern to match and a replacement string:
# Replace string if found, else no change.
# (# $1 = filename, $2 = pattern to match, $3 = replacement)
replace() {
	grep $2 $1 >/dev/null
	if [ $? -eq 0 ]; then
		# Pattern found; replace in file
		sed -i "s/$2/$3/g" $1 >/dev/null
	fi
}

# Given a filename, a regex pattern to match and a replacement string:
# If found, perform replacement, else append file w/replacement on new line.
replaceAppend() {
	grep $2 $1 >/dev/null
	if [ $? -eq 0 ]; then
		# Pattern found; replace in file
		sed -i "s/$2/$3/g" $1 >/dev/null
	else
		# Not found; append on new line (silently)
		echo $3 | sudo tee -a $1 >/dev/null
	fi
}

# Given a filename, a regex pattern to match and a string:
# If found, no change, else append file with string on new line.
append1() {
	grep $2 $1 >/dev/null
	if [ $? -ne 0 ]; then
		# Not found; append on new line (silently)
		echo $3 | sudo tee -a $1 >/dev/null
	fi
}

# Given a list of strings representing options, display each option
# preceded by a number (1 to N), display a prompt, check input until
# a valid number within the selection range is entered.
selectN() {
	for ((i=1; i<=$#; i++)); do
		echo $i. ${!i}
	done
	echo
	REPLY=""
	while :
	do
		echo -n "SELECT 1-$#: "
		read
		if [[ $REPLY -ge 1 ]] && [[ $REPLY -le $# ]]; then
			return $REPLY
		fi
	done
}

echo "Updating dependencies"
apt-get update && apt-get upgrade -y --force-yes && apt-get update
apt-get install -y --force-yes git-core build-essential ntp scons i2c-tools vim

echo "Updating python dependencies"
apt-get install -y --force-yes python-dev swig python-psutil python-rpi.gpio python-pip
python -m pip install --upgrade pip setuptools wheel

if [[ ! -d /home/loragw ]]; then
  echo "Adding new user loragw, enter it password"
	useradd -m loragw -s /bin/bash
	passwd loragw
	usermod -a -G sudo loragw
	cp /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_loragw-nopasswd
	sed -i -- 's/pi/loragw/g' /etc/sudoers.d/010_loragw-nopasswd
	cp /home/pi/.profile /home/loragw/
	cp /home/pi/.bashrc /home/loragw/
	chown loragw:loragw /home/loragw/.*
    usermod -a -G i2c,spi,gpio,dialout loragw

fi


if [[ ! -d /home/loragw/LoraGW-Setup ]]; then
    cd /home/loragw
    sudo -u loragw git clone https://github.com/kaibeckmann/LoraGW-Setup.git
    cd
fi

# c&p from https://github.com/kuanyili/rak831-gateway
echo "creating user for gateway processes"
# Create ttn group if it isn't already there
if ! getent group ttn >/dev/null; then
    # Add system group: ttn
    addgroup --system ttn >/dev/null
fi

# Create ttn user if it isn't already there
if ! getent passwd ttn >/dev/null; then
    # Add system user: ttn
    adduser \
        --system \
        --disabled-login \
        --ingroup ttn \
        --no-create-home \
        --home /nonexistent \
        --gecos "The Things Network Gateway" \
        --shell /bin/false \
        ttn >/dev/null
    # Add ttn user to supplementary groups so it can
    # reset and communicate with concentrator board
    usermod --groups gpio,spi,i2c,dialout ttn
fi


echo "Enabling Uart, I2C, SPI, Video Memory to 16MB"
raspi-config nonint do_spi 0
raspi-config nonint do_i2c 0
raspi-config nonint do_serial 2
raspi-config nonint do_expand_rootfs
raspi-config nonint do_configure_keyboard us
raspi-config nonint do_change_locale "en_US.UTF-8"
raspi-config nonint do_change_timezone "Europe/Berlin"
raspi-config nonint do_memory_split 16
raspi-config nonint do_ssh 0
raspi-config nonint do_onewire 0

#replaceAppend /boot/config.txt "^.*enable_uart.*$" "enable_uart=1"
#replaceAppend /boot/config.txt "^.*dtparam=i2c_arm=.*$" "dtparam=i2c_arm=on"
#replaceAppend /boot/config.txt "^.*dtparam=spi=.*$" "dtparam=spi=on"
#replaceAppend /boot/config.txt "^.*gpu_mem=.*$" "gpu_mem=16"
#replaceAppend /etc/modules "^.*i2c-dev.*$" "i2c-dev"

echo -n "Do you want to configure timezone [y/N] "
read
if [[ "$REPLY" =~ ^(yes|y|Y)$ ]]; then
	echo "Reconfiguring Time Zone."
	dpkg-reconfigure tzdata
fi

echo -n "Do you want to use permanent IPv6 EUIs? [y/N] "
read
if [[ "$REPLY" =~ ^(yes|y|Y)$ ]]; then
    echo "Deactivating IPv6 Privacy Extensions"
    touch /etc/sysctl.d/10-ipv6-privacy.conf
    replaceAppend /etc/sysctl.d/10-ipv6-privacy.conf "^.*net.ipv6.conf.all.use_tempaddr=.*$" "net.ipv6.conf.all.use_tempaddr=0"
    replaceAppend /etc/sysctl.d/10-ipv6-privacy.conf "^.*net.ipv6.conf.default.use_tempaddr=.*$" "net.ipv6.conf.default.use_tempaddr=0"
    replaceAppend /etc/dhcpcd.conf "^.*slaac.*$" "slaac hwaddr"
fi

if [[ ! -f /usr/local/bin/log2ram ]]; then
	echo -n "Do you want to enable log2ram [y/N] "
	read
	if [[ "$REPLY" =~ ^(yes|y|Y)$ ]]; then
		echo "Setting up log2ram."
		git clone https://github.com/azlux/log2ram.git
		cd log2ram
		chmod +x install.sh uninstall.sh
		./install.sh
		ln -s /usr/local/bin/log2ram /etc/cron.hourly/
		echo "cleaning up log rotation"
		replace /etc/logrotage.d/rsyslog "^.*daily.*$" "    hourly"
		replace /etc/logrotage.d/rsyslog "^.*monthly.*$" "    daily"
		replace /etc/logrotage.d/rsyslog "^.*delaycompress.*$" "  "

        # more space, use rsync
        replace /etc/log2ram.conf "^.SIZE=.*$" "SIZE=256M"
        replace /etc/log2ram.conf "^.USE_RSYNC=.*$" "USE_RSYNC=true"

		echo "forcing one log rotation"
		logrotate /etc/logrotate.conf
		echo "Please don't forget to adjust the logrotate"
		echo "paratemeters in /etc/logrotage.d/* to avoid"
		echo "filling up the ramdisk, see README in"
		echo "https://github.com/ch2i/LoraGW-Setup/"
		echo ""
	fi
fi

# set hostname to loragw-xxyy with xxyy last MAC Address digits
# wenn exitsiert, sonst eth0
if [[ -e /sys/class/net/wlan0/address ]]; then
    set -- `cat /sys/class/net/wlan0/address`
elif [[ -e /sys/class/net/eth0/address ]]; then
    set -- `cat /sys/class/net/eth0/address`
fi
    
IFS=":"; declare -a Array=($*)
NEWHOST=loragw-${Array[4]}${Array[5]}

echo ""
echo "Please select new device name (hostname)"
selectN "Leave as $HOSTNAME" "loragw" "$NEWHOST"
SEL=$?
if [[ $SEL -gt 1 ]]; then
	if [[ $SEL == 2 ]]; then
    NEWHOST=loragw
	fi
	sudo bash -c "echo $NEWHOST" > /etc/hostname
	replace /etc/hosts  "^127.0.1.1.*$HOSTNAME.*$" "127.0.1.1\t$NEWHOST"
  echo "New hostname set to $NEWHOST"
else
  echo "hostname unchanged"
fi

echo "Done."
echo
echo "Settings take effect on next boot."
echo "after reboot, login back here with"
echo "ssh loragw@$NEWHOST.local"
echo
echo -n "REBOOT NOW? [y/N] "
read
if [[ ! "$REPLY" =~ ^(yes|y|Y)$ ]]; then
	echo "Exiting without reboot."
	exit 0
fi
echo "Reboot started..."
reboot
exit 0

