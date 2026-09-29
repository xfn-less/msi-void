#!/bin/sh
# 功能：Niri、壁纸、色温、idle、锁屏、截图与启动器
# 前提：已运行 01-system.sh 和 terminal-fonts.sh；输入法、音频按需先运行
# 生效：Niri 配置自动重载；用户组和自启需重新登录
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
h=$repo/root/home
sudo xbps-install -Sy -y niri dbus seatd wlsunset brightnessctl xdg-utils gnome-themes-extra glib gsettings-desktop-schemas swayidle swaylock grim slurp swappy wl-clipboard
sudo ln -sfn /etc/sv/dbus /var/service/dbus
sudo ln -sfn /etc/sv/seatd /var/service/seatd
sudo usermod -aG _seatd "$USER"
mkdir -p "$HOME/.config"
ln -sfnT "$h/.config/niri" "$HOME/.config/niri"
niri validate --config "$h/.config/niri/config.kdl"
