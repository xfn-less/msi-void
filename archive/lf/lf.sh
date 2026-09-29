#!/bin/sh
# 已归档：LF、文件选择器及默认打开方式（从 modules/04-apps/ 移出）
# 恢复时把本目录配置链回 $HOME，或对照历史提交。
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
a=$repo/archive/lf
h=$repo/root/home

mkdir -p "$HOME/.config" "$HOME/.local/share/applications"
sudo xbps-install -Sy -y lf fzf file wl-clipboard xdg-utils xdg-desktop-portal-termfilechooser
ln -sfnT "$a/config" "$HOME/.config/lf"
ln -sfnT "$a/xdg-desktop-portal" "$HOME/.config/xdg-desktop-portal"
ln -sfnT "$a/xdg-desktop-portal-termfilechooser" "$HOME/.config/xdg-desktop-portal-termfilechooser"
chmod +x "$a/config/preview" "$a/config/scripts/"*
ln -sfn "$a/lf.desktop" "$HOME/.local/share/applications/lf.desktop"
ln -sfn "$h/.config/mimeapps.list" "$HOME/.config/mimeapps.list"
