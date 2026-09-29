#!/bin/sh
# 功能：Alacritty、字体与 fontconfig
# 前提：已运行 01-system.sh
# 生效：新终端；字体重新打开应用后生效
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
h=$repo/root/home
sudo xbps-install -Sy -y alacritty font-inconsolata-otf wqy-microhei
mkdir -p "$HOME/.config"
ln -sfnT "$h/.config/alacritty" "$HOME/.config/alacritty"
ln -sfnT "$h/.config/fontconfig" "$HOME/.config/fontconfig"
fc-cache -f
