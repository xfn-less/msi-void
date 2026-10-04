#!/bin/sh
set -eu

# Void 安装：选择 Base、Local，在 Network 中配置 Wi-Fi + DHCP，
# 服务保留 chronyd、dhcpcd、wpa_supplicant、acpid，然后重启。
#
# 如果安装时跳过网络，重启后把 /etc/wpa_supplicant/wpa_supplicant.conf 写成：
#
#   ctrl_interface=/run/wpa_supplicant
#   ctrl_interface_group=wheel
#   update_config=0
#   mac_addr=1
#   preassoc_mac_addr=1
#
#   network={
#   	ssid="Wi-Fi 名称"
#   	psk="密码"
#   }
#
#   sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
#   sudo ln -sfn /etc/sv/wpa_supplicant /var/service/wpa_supplicant
#   sudo ln -sfn /etc/sv/dhcpcd /var/service/dhcpcd
#   sudo sv restart wpa_supplicant
#
# 以后加网：再写一个 network={}，然后 sudo sv restart wpa_supplicant
#
# 丢光设备时先用密码登录 GitHub，再配新 SSH 钥，然后：
#   git clone git@github.com:xfn-less/msi-void.git
#   cd msi-void/void-config && sh setup-msi.sh
# vis 的 Lua 由 vis-nightly 打进二进制，不要再装 ~/.config/vis。
# 本脚本之后：
#   git clone git@github.com:xfn-less/work.git /home/xfn/work
#   sh xray/mihomo.sh
# 重启，TTY 登录后运行 ni。Windows ESP 的 UUID 换盘后改 09_windows。

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

## 键盘映射
sudo xbps-install -y keyd
sudo install -d -m 755 /etc/keyd
sudo install -m 644 keyd/*.conf /etc/keyd/

sudo keyd check /etc/keyd/*.conf
sudo ln -sfn /etc/sv/keyd /var/service/keyd
sudo sv restart keyd

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

# 4. 终端

## 软件
sudo xbps-install -y bash-completion git fzf chafa curl file lf \
	zip unzip 7zip fastfetch

## Vis master（Lua 已打进 nightly 二进制）
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

## LF
mkdir -p "$HOME/.config/lf"
cp -R lf/. "$HOME/.config/lf/"
chmod 755 "$HOME/.config/lf/preview" "$HOME/.config/lf/scripts/"*

## Bash
install -m 644 .bashrc "$HOME/.bashrc"
install -m 644 .bash_profile "$HOME/.bash_profile"

## Readline
install -m 644 .inputrc "$HOME/.inputrc"

## 字体与 Alacritty
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

# 5. 桌面

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

printf '%s\n' '配置完成。重启后登录 TTY，运行 ni。然后 clone work，再 sh xray/mihomo.sh。'
