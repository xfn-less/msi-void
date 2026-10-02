#!/bin/sh
set -eu

# Void 安装：选择 Base、Local，在 Network 中配置 Wi-Fi + DHCP，
# 服务保留 chronyd、dhcpcd、wpa_supplicant、acpid，然后重启。
#
# 如果安装时跳过网络，重启后先运行：
#   ip link
#   sudo -v
#   {
#     printf 'mac_addr=1\npreassoc_mac_addr=1\n'
#     wpa_passphrase 'Wi-Fi 名称'
#   } | sudo tee /etc/wpa_supplicant/wpa_supplicant.conf
#   sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
#   sudo ln -sfn /etc/sv/wpa_supplicant /var/service/wpa_supplicant
#   sudo ln -sfn /etc/sv/dhcpcd /var/service/dhcpcd
#   sudo sv restart wpa_supplicant
#
# 联网后进入 void-config 目录，运行：sh setup-msi.sh

# 1. 基础系统

## 软件源
sudo install -d -m 755 /etc/xbps.d
cat <<'EOF' | sudo tee /etc/xbps.d/00-repository-main.conf >/dev/null
repository=https://repo-fastly.voidlinux.org/current
repository=https://repo-fastly.voidlinux.org/current/nonfree
ignorepkg=linux-firmware-nvidia
ignorepkg=linux-firmware-amd
ignorepkg=linux-firmware-broadcom
ignorepkg=wifi-firmware
ignorepkg=alsa-firmware
ignorepkg=btrfs-progs
ignorepkg=xfsprogs
ignorepkg=f2fs-tools
EOF

sudo xbps-install -Syu

## 删除本机不用的 Base 依赖；ignorepkg 仍让依赖检查保持满足
unused=
for package in \
	linux-firmware-nvidia linux-firmware-amd linux-firmware-broadcom \
	wifi-firmware alsa-firmware btrfs-progs xfsprogs f2fs-tools
do
	xbps-query -p pkgver "$package" >/dev/null 2>&1 && unused="$unused $package"
done
[ -z "$unused" ] || sudo xbps-remove -Ry $unused

## 本机主机名解析
hostname=$(cat /etc/hostname)
printf '127.0.0.1\tlocalhost.localdomain\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n::1\tlocalhost.localdomain\tlocalhost ip6-localhost\n' "$hostname" "$hostname" |
	sudo tee /etc/hosts >/dev/null

## 免密码 sudo
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USER" |
	sudo tee "/etc/sudoers.d/zz-$USER-nopasswd" >/dev/null
sudo chmod 440 "/etc/sudoers.d/zz-$USER-nopasswd"

# 2. MSI 硬件

## 驱动与固件
sudo xbps-install -y intel-ucode mesa-dri intel-video-accel sof-firmware

## 优先省电，保留睿频
cat <<'EOF' | sudo tee /etc/rc.local >/dev/null
#!/bin/sh
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
	[ -w "$epp" ] && printf 'power\n' >"$epp"
done
EOF
sudo chmod 755 /etc/rc.local
sudo /etc/rc.local

# 3. 启动

## 隐藏 GRUB，默认进入 Windows，按 Esc 选择 Void
cat <<'EOF' | sudo tee /etc/default/grub >/dev/null
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="Void"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_SUBMENU=true
EOF

cat <<'EOF' | sudo tee /etc/grub.d/09_windows >/dev/null
#!/bin/sh
cat <<'ENTRY'
menuentry 'Windows' --class windows --class os {
	insmod part_gpt
	insmod fat
	search --no-floppy --fs-uuid --set=root 0009-85C1
	chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
ENTRY
EOF
sudo chmod 755 /etc/grub.d/09_windows
sudo update-grub

void=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* void.*/\1/p')
windows=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* Windows Boot Manager.*/\1/p')
[ -n "$void" ] && [ -n "$windows" ]
sudo efibootmgr --bootorder "$void,$windows"

# 4. 桌面

## Niri 基础环境
sudo xbps-install -y niri dbus seatd gnome-themes-extra
sudo ln -sfn /etc/sv/dbus /var/service/dbus
sudo ln -sfn /etc/sv/seatd /var/service/seatd
sudo usermod -aG _seatd "$USER"

## Niri 功能
sudo xbps-install -y wlsunset brightnessctl xdg-utils swayidle swaylock \
	grim slurp swappy wl-clipboard

## Niri 配置
mkdir -p "$HOME/.config/niri"
install -m 644 niri/config.kdl "$HOME/.config/niri/config.kdl"
niri validate --config "$HOME/.config/niri/config.kdl"

## 中文输入（自然码：方案名 zrm，词库来自 fcitx5-chinese-addons/libime）
sudo xbps-install -y fcitx5 fcitx5-chinese-addons
mkdir -p "$HOME/.config/fcitx5/conf"
cat <<'EOF' >"$HOME/.config/fcitx5/profile"
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=zrm

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=zrm
Layout=

[GroupOrder]
0=Default
EOF

cat <<'EOF' >"$HOME/.config/fcitx5/config"
[Behavior]
ActiveByDefault=False
resetStateWhenFocusIn=All
ShareInputState=No
ShowInputMethodInformation=True
showInputMethodInformationWhenFocusIn=True
ShowFirstInputMethodInformation=True
CompactInputMethodInformation=True
EOF

cat <<'EOF' >"$HOME/.config/fcitx5/conf/clipboard.conf"
[PastePrimaryKey]
0=Alt+semicolon
EOF

## 声音
sudo xbps-install -y alsa-utils

## 键盘映射
sudo xbps-install -y keyd
sudo install -d -m 755 /etc/keyd
sudo install -m 644 keyd/*.conf /etc/keyd/

sudo keyd check /etc/keyd/*.conf
sudo ln -sfn /etc/sv/keyd /var/service/keyd
sudo sv restart keyd

## 终端与字体
sudo xbps-install -y alacritty font-inconsolata-otf wqy-microhei
mkdir -p "$HOME/.config/fontconfig"
cat <<'EOF' >"$HOME/.config/fontconfig/fonts.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Inconsolata</family>
      <family>WenQuanYi Micro Hei Mono</family>
    </prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Inconsolata</family>
      <family>WenQuanYi Micro Hei</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Inconsolata</family>
      <family>WenQuanYi Micro Hei</family>
    </prefer>
  </alias>
</fontconfig>
EOF
fc-cache -f

mkdir -p "$HOME/.config/alacritty"
cat <<'EOF' >"$HOME/.config/alacritty/alacritty.toml"
[font]
size = 14.5
EOF

# 5. 终端环境

## 软件
sudo xbps-install -y bash-completion git fzf chafa curl file lf \
	zip unzip 7zip

## Vis master
vis_tmp=$(mktemp -d)
trap 'rm -rf "$vis_tmp"' 0 1 2 15
curl -fL https://github.com/xfn-less/vis-nightly/releases/download/nightly/vis-master \
	-o "$vis_tmp/vis-master"
curl -fL https://github.com/xfn-less/vis-nightly/releases/download/nightly/vis-master.sha256 \
	-o "$vis_tmp/vis-master.sha256"
(cd "$vis_tmp" && sha256sum -c vis-master.sha256)
sudo install -Dm755 "$vis_tmp/vis-master" /usr/local/bin/vis
rm -rf "$vis_tmp"
trap - 0 1 2 15

## LF 配置
mkdir -p "$HOME/.config/lf"
cp -R lf/. "$HOME/.config/lf/"
chmod 755 "$HOME/.config/lf/preview" "$HOME/.config/lf/scripts/"*

## Bash
install -m 644 .bashrc "$HOME/.bashrc"
install -m 644 .bash_profile "$HOME/.bash_profile"

## Readline
install -m 644 .inputrc "$HOME/.inputrc"

# 6. 应用

## 浏览器
sudo xbps-install -y firefox

printf '%s\n' '配置完成。重启后登录 TTY，运行 ni 进入 Niri。'

# 7. XBPS 备忘
#
# 更新系统：sudo xbps-install -Syu
# 搜索软件：xbps-query -Rs 名称
# 安装软件：sudo xbps-install -y 包名
# 手动安装：xbps-query -m
# 查看文件：xbps-query -f 包名
# 查文件归属：xbps-query -o /文件路径
# 预览删除：sudo xbps-remove -nR 包名
# 删除及依赖：sudo xbps-remove -Ry 包名
# 清理孤儿：sudo xbps-remove -oy
# 清理缓存：sudo xbps-remove -O；全部未安装包用 -OO
# 检查数据库：sudo xbps-pkgdb -a
#
# 查看旧内核：vkpurge list
# 删除全部旧内核：sudo vkpurge rm all
