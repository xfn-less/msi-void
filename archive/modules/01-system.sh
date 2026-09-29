#!/bin/sh
# 功能：基础系统、Shell、时间同步和 Wi-Fi
# 前提：普通用户运行，已有 sudo 和临时网络；先设置 /etc/hostname，填写 Wi-Fi 凭据
# 生效：服务设置即时生效；用户组和桌面自启需重新登录，驱动需重启
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
h=$repo/root/home

# --- 软件源 ---
sudo install -d /etc/xbps.d
sudo install -m 644 "$repo/root/etc/xbps.d/00-repository-main.conf" /etc/xbps.d/00-repository-main.conf
sudo install -m 644 "$repo/root/etc/xbps.d/20-nonfree.conf" /etc/xbps.d/20-nonfree.conf
sudo install -m 644 "$repo/root/etc/xbps.d/30-ignore-nvidia.conf" /etc/xbps.d/30-ignore-nvidia.conf
printf '%s\n' 'XBPS 软件源已安装，下次运行 xbps-install 时使用。'

# --- 主机名 ---
hostname=$(cat /etc/hostname)
printf '127.0.0.1\tlocalhost.localdomain\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n::1\tlocalhost.localdomain\tlocalhost ip6-localhost\n' "$hostname" "$hostname" | sudo tee /etc/hosts >/dev/null

# --- sudo 权限 ---
user=${USER:?USER is not set}
case "$user" in
	*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*)
		printf 'Unsupported user name: %s\n' "$user" >&2
		exit 1
		;;
esac

sudoers_dir=${SUDOERS_DIR:-/etc/sudoers.d}
rule=$sudoers_dir/zz-$user-nopasswd
tmp=$(mktemp /tmp/sudo-rule.XXXXXX)

printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$user" >"$tmp"
chmod 440 "$tmp"
sudo visudo -cf "$tmp"
sudo install -d -m 755 "$sudoers_dir"
sudo install -o root -g root -m 440 "$tmp" "$rule"
printf '%s\n' "Passwordless sudo enabled for $user."

# --- Shell 与常用命令 ---
mkdir -p "$HOME/.config" "$HOME/.local/bin"
sudo xbps-install -Sy -y bash-completion git openssh fzf file chafa
ln -sfn "$h/.bash_profile" "$HOME/.bash_profile"
ln -sfn "$h/.bashrc" "$HOME/.bashrc"
ln -sfn "$h/.inputrc" "$HOME/.inputrc"
ln -sfn "$h/.npmrc" "$HOME/.npmrc"
mkdir -p "$HOME/.config/htop"
ln -sfn "$h/.config/htop/htoprc" "$HOME/.config/htop/htoprc"
ln -sfn "$h/.local/bin/xb" "$HOME/.local/bin/xb"
ln -sfn "$h/.config/mimeapps.list" "$HOME/.config/mimeapps.list"

# --- 时间同步 ---
sudo xbps-install -Sy -y chrony
sudo ln -sfn /etc/sv/chronyd /var/service/chronyd

# --- Wi-Fi ---
sudo xbps-install -Sy -y wpa_supplicant dhcpcd iw
if ! sudo test -s /etc/wpa_supplicant/wpa_supplicant.conf; then
    printf '%s\n' '请先按 README 填写本机 /etc/wpa_supplicant/wpa_supplicant.conf，然后重跑本模块。' >&2
    exit 1
fi
sudo ln -sfn /etc/sv/wpa_supplicant /var/service/wpa_supplicant
sudo ln -sfn /etc/sv/dhcpcd /var/service/dhcpcd
