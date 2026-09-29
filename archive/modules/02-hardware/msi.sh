#!/bin/sh
# 功能：MSI 显卡、固件；简单 CPU 降频
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

sudo xbps-install -Sy -y intel-ucode mesa-dri intel-video-accel sof-firmware

sudo install -m 755 -D "$repo/root/etc/rc.local.d/cpufreq" /etc/rc.local.d/cpufreq
if [ ! -e /etc/rc.local ]; then
	printf '%s\n' '#!/bin/sh' '[ ! -x /etc/rc.local.d/cpufreq ] || /etc/rc.local.d/cpufreq' | sudo tee /etc/rc.local >/dev/null
	sudo chmod 755 /etc/rc.local
elif ! grep -q 'rc.local.d/cpufreq' /etc/rc.local; then
	printf '\n[ ! -x /etc/rc.local.d/cpufreq ] || /etc/rc.local.d/cpufreq\n' | sudo tee -a /etc/rc.local >/dev/null
fi
sudo /etc/rc.local.d/cpufreq
