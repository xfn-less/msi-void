#!/bin/sh
# 功能：安装、复制并重新加载 keyd 配置
# 生效：立即；如果服务未运行，启动服务后生效
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sudo xbps-install -Sy -y keyd
sudo keyd check "$repo/root/etc/keyd/"*.conf
sudo install -d /etc/keyd
sudo install -m 644 "$repo/root/etc/keyd/"*.conf /etc/keyd/
sudo ln -sfn /etc/sv/keyd /var/service/keyd
if sudo sv status keyd 2>/dev/null | grep -q '^run:'; then
    sudo keyd reload
fi
