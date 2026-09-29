#!/bin/sh
# 功能：Mihomo 下载、私有配置及用户控制命令
# 生效：验证后启用服务；更新会重启正在运行的 Mihomo
# 前提：网络可访问 GitHub；仅在需要代理的设备运行
set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
template=$dir/root/etc/mihomo/config.yaml.example
mkdir -p "$HOME/.local/bin"
ln -sfn "$dir/root/home/.local/bin/mihomoctl" "$HOME/.local/bin/mihomoctl"
tmp=$(mktemp -d /tmp/mihomo.XXXXXX)

if [ -n "${MIHOMO_BIN:-}" ]; then
	source_bin=$MIHOMO_BIN
else
	sudo xbps-install -y curl gzip
	case $(uname -m) in
	x86_64) arch=amd64-v1 ;;
	aarch64) arch=arm64 ;;
	*)
		printf '%s\n' '此安装脚本仅支持 x86_64 和 aarch64。' >&2
		exit 1
		;;
	esac
	latest=$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest |
		sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n 1)
	case $latest in
	v[0-9]*) ;;
	*)
		printf '%s\n' '无法获取 Mihomo 最新稳定版。' >&2
		exit 1
		;;
	esac
	printf '安装 Mihomo %s\n' "$latest"
	curl -fL "https://github.com/MetaCubeX/mihomo/releases/download/$latest/mihomo-linux-$arch-$latest.gz" -o "$tmp/mihomo.gz"
	gzip -dc "$tmp/mihomo.gz" >"$tmp/mihomo"
	chmod 755 "$tmp/mihomo"
	source_bin=$tmp/mihomo
fi
"$source_bin" -v

install_binary() {
	# Rename instead of overwriting an executable that may be running.
	sudo install -m 755 "$source_bin" /usr/local/bin/mihomo.new
	sudo mv -f /usr/local/bin/mihomo.new /usr/local/bin/mihomo
	# Keep the user command and the system service on the same binary.
	mkdir -p "$HOME/.local/bin"
	ln -sfn /usr/local/bin/mihomo "$HOME/.local/bin/mihomo"
}

sudo install -d -m 755 /etc/mihomo /etc/sv/mihomo/log
sudo install -d -m 700 /var/lib/mihomo/providers /var/log/sv/mihomo

if ! sudo test -f /etc/mihomo/config.yaml; then
	install_binary
	sudo install -m 600 "$template" /etc/mihomo/config.yaml
	printf '%s\n' \
		'已创建 /etc/mihomo/config.yaml。' \
		'请执行 sudoedit /etc/mihomo/config.yaml，填入两个完整节点并删除 REPLACE_STATIC_NODE_VALUES 标记，' \
		'然后重新运行 sh modules/05-optional/mihomo.sh。'
	exit 0
fi

if sudo grep -Fq 'REPLACE_STATIC_NODE_VALUES' /etc/mihomo/config.yaml; then
	printf '%s\n' '请先填入 /etc/mihomo/config.yaml 中的两个静态节点。' >&2
	exit 1
fi

sudo chmod 600 /etc/mihomo/config.yaml
sudo "$source_bin" -t -d /var/lib/mihomo -f /etc/mihomo/config.yaml
install_binary
sudo install -m 755 "$dir/root/etc/sv/mihomo/run" /etc/sv/mihomo/run
sudo install -m 755 "$dir/root/etc/sv/mihomo/log/run" /etc/sv/mihomo/log/run
sudo ln -sfnT /etc/sv/mihomo /var/service/mihomo
# Only restart an already-running service; a fresh install waits for runsvdir.
if sudo sv status mihomo 2>/dev/null | grep -q '^run:'; then
	sudo sv -w 15 restart mihomo
fi
printf '%s\n' 'Mihomo 已安装，配置有效，runit 服务已启用。'
