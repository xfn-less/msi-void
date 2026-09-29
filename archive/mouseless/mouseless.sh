#!/bin/sh
# 功能：更新 Mouseless 二进制、输入权限及配置
# 生效：重新登录 Niri，使 input/uinput 用户组生效
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mouseless_tmp=$(mktemp -d /tmp/mouseless.XXXXXX)
sudo xbps-install -y curl tar gzip
[ "$(uname -m)" = x86_64 ] || {
	printf '%s\n' 'Mouseless 官方目前只提供 Linux x86_64 二进制。' >&2
	exit 1
}
latest=$(curl -fsSL https://api.github.com/repos/jbensmann/mouseless/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n 1)
case $latest in v[0-9]*) ;; *) printf '%s\n' '无法获取 Mouseless 最新稳定版。' >&2; exit 1 ;; esac
curl -fL "https://github.com/jbensmann/mouseless/releases/download/$latest/mouseless_linux_amd64.tar.gz" -o "$mouseless_tmp/mouseless.tar.gz"
tar -xzf "$mouseless_tmp/mouseless.tar.gz" -C "$mouseless_tmp" mouseless
"$mouseless_tmp/mouseless" --version
mkdir -p "$HOME/.local/bin"
install -m 755 "$mouseless_tmp/mouseless" "$HOME/.local/bin/mouseless.new"
mv -f "$HOME/.local/bin/mouseless.new" "$HOME/.local/bin/mouseless"
sudo groupadd -f -r uinput
sudo usermod -aG input,uinput "$USER"
sudo install -o root -g root -m 644 -D "$repo/root/etc/udev/rules.d/99-mouseless.rules" /etc/udev/rules.d/99-mouseless.rules
sudo modprobe uinput
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=uinput
mkdir -p "$HOME/.config"
ln -sfnT "$repo/root/home/.config/mouseless" "$HOME/.config/mouseless"
printf '%s\n' 'Mouseless 已更新；重新登录整个 Niri 会话使用户组生效。'
