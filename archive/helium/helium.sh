#!/bin/sh
# 已归档：Helium 浏览器自管安装（改为系统 firefox）
# 原模块：modules/04-apps/helium.sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
opt=$HOME/.local/opt/helium
tmp=$(mktemp -d /tmp/helium.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

sudo xbps-install -Sy -y nspr nss curl xz

case $(uname -m) in
x86_64) asset=x86_64_linux.tar.xz ;;
aarch64) asset=arm64_linux.tar.xz ;;
*) printf '%s\n' 'Helium 官方 Linux 包只支持 x86_64 和 aarch64。' >&2; exit 1 ;;
esac

curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest -o "$tmp/release.json"
version=$(sed -n 's/.*"tag_name": "\([^"].*\)".*/\1/p' "$tmp/release.json" | head -n 1)
url=$(sed -n 's/.*"browser_download_url": "\([^"]*'"$asset"'\)".*/\1/p' "$tmp/release.json" | head -n 1)
test -n "$version" -a -n "$url"

if [ -x "$opt/helium" ] && "$opt/helium" --version 2>/dev/null | grep -q " $version "; then
	printf 'Helium %s 已是最新版本。\n' "${version#v}"
else
	curl -fL "$url" -o "$tmp/helium.tar.xz"
	mkdir "$tmp/new"
	tar -xJf "$tmp/helium.tar.xz" --strip-components=1 -C "$tmp/new"
	test -x "$tmp/new/helium"
	mkdir -p "$(dirname "$opt")"
	rm -rf "$opt"
	mv "$tmp/new" "$opt"
	printf '%s\n' "${version#v}" >"$opt/.release"
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config"
ln -sfn "$repo/archive/helium/helium" "$HOME/.local/bin/helium"
ln -sfn "$repo/archive/helium/helium.desktop" "$HOME/.local/share/applications/helium.desktop"
ln -sfn "$repo/root/home/.config/mimeapps.list" "$HOME/.config/mimeapps.list"
