#!/bin/sh
# 功能：qutebrowser、硬解 QtWebEngine 二进制和完整配置
# 生效：下次打开 qute；更新内核后不强制重启浏览器
# 被替换的实体配置会先备份；其他本机文件、用户数据及会话不动
# 前提：x86_64 glibc Void，当前验证过的 Qt 系列；网络可访问 GitHub/GHCR
set -eu
mode=${1:-}
dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
case $mode in
'' | --build-only | --prepare-update) ;;
*)
	echo "用法：sh modules/04-apps/qutebrowser.sh [--build-only|--prepare-update]" >&2
	exit 1
	;;
esac
test "$(xbps-uhelper arch)" = x86_64 || {
	echo '此二进制只支持 x86_64 glibc Void。' >&2
	exit 1
}
if [ -z "$mode" ]; then
	sudo xbps-install -y python3 python3-adblock patchelf xbps qt6-wayland-client qt6-plugin-tls-openssl libva
fi

repo=${XDG_CACHE_HOME:-$HOME/.cache}/qutebrowser-xbps
mkdir -p "$repo"
tmp=$(mktemp -d /tmp/qutebrowser.XXXXXX)
qt_version=6.11.2
xml_version=2.15.4
pkg_version=6.11.2_1
qt_sha=1b1f9666f90094609bff11ca4f16655ec09f352f18c2d2566ba01b1c00f4c64a
xml_sha=57b219c3bbf96111a57e2afaa052757b8697f268bc61944689eb9ae35829f1d0
if [ "$mode" = --prepare-update ]; then
	python3 "$dir/modules/04-apps/qutebrowser/update.py" plan "$tmp/update.json"
	[ -f "$tmp/update.json" ] || exit 0
	values=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p["qt"],p["xml"],p["pkgver"],p["qt_sha"],p["xml_sha"])' "$tmp/update.json")
	# All five fields were validated as versions or SHA256 values by the helper.
	set -- $values
	qt_version=$1 xml_version=$2 pkg_version=$3 qt_sha=$4 xml_sha=$5
fi
qt_upper=$(python3 -c 'import sys; a,b,_=map(int,sys.argv[1].split(".")); print(f"{a}.{b+1}")' "$qt_version")
python3 - "$repo" "$tmp" "$qt_sha" "$xml_sha" <<'PY'
import hashlib, json, pathlib, sys, tarfile, urllib.request
cache, dest = map(pathlib.Path, sys.argv[1:3])
bottles = [
    ('qtwebengine', sys.argv[3]),
    ('libxml2', sys.argv[4]),
]
for name, digest in bottles:
    archive = cache / (digest + '.tar.gz')
    if not archive.exists():
        print('下载 ' + name, flush=True)
        url = f'https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/{name}:pull'
        with urllib.request.urlopen(url, timeout=60) as response:
            token = json.load(response)['token']
        url = f'https://ghcr.io/v2/homebrew/core/{name}/blobs/sha256:{digest}'
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
        partial = archive.with_suffix('.part')
        with urllib.request.urlopen(request, timeout=60) as response, partial.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        partial.replace(archive)
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != digest:
            raise SystemExit(f'SHA256 校验失败，请删除后重试：{archive}')
    with tarfile.open(archive) as source:
        source.extractall(dest, filter='data')
PY

qt=$tmp/qtwebengine/$qt_version
xml=$tmp/libxml2/$xml_version
pkg=$tmp/pkg
mkdir -p "$pkg/usr/lib/qtwebengine-hw" "$pkg/usr/lib/qt6/libexec" \
	"$pkg/usr/lib/qt6/qml" "$pkg/usr/share/qt6/translations" \
	"$pkg/usr/share/licenses/qt6-webengine"
cp -a "$qt"/lib/libQt6WebEngine*.so.6* "$pkg/usr/lib/"
cp -a "$xml"/lib/libxml2.so.* "$pkg/usr/lib/qtwebengine-hw/"
cp -a "$qt/share/qt/qml/QtWebEngine" "$pkg/usr/lib/qt6/qml/"
for name in QtWebEngineProcess qwebengine_convert_dict webenginedriver; do
	cp "$qt/share/qt/libexec/$name" "$pkg/usr/lib/qt6/libexec/"
	patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$pkg/usr/lib/qt6/libexec/$name"
done
cp -a "$qt/share/qt/resources" "$pkg/usr/share/qt6/"
cp -a "$qt/share/qt/translations/qtwebengine_locales" "$pkg/usr/share/qt6/translations/"
cp "$qt/LICENSE.Chromium" "$pkg/usr/share/licenses/qt6-webengine/"
cp "$xml/Copyright" "$pkg/usr/share/licenses/qt6-webengine/libxml2-Copyright"

# 只有这些 ELF 使用附带的 libxml2；系统原有 libxml2 不变。
find "$pkg/usr/lib" -type f \( -name '*.so*' -o -path '*/libexec/*' \) \
	-exec patchelf --set-rpath /usr/lib/qtwebengine-hw {} +
provides='libQt6WebEngineCore.so.6 libQt6WebEngineWidgets.so.6 libQt6WebEngineQuick.so.6 libQt6WebEngineQuickDelegatesQml.so.6'
deps='qt6-core>=6.11.1_1<6.12 qt6-gui>=6.11.1_1<6.12
qt6-network>=6.11.1_1<6.12 qt6-position>=6.11.1_1<6.12
qt6-printsupport>=6.11.1_1<6.12 qt6-declarative>=6.11.1_1<6.12
qt6-webchannel>=6.11.1_1<6.12 qt6-widgets>=6.11.1_1<6.12
qt6-plugin-tls-openssl>=6.11.1_1<6.12 glibc>=2.38
libglvnd>=0 libX11>=0 libXcomposite>=0 libXdamage>=0 libXext>=0
libXfixes>=0 libXrandr>=0 libXtst>=0 alsa-lib>=0 dbus-libs>=0
expat>=0 fontconfig>=0 freetype>=0 libgbm>=0 libgcc>=0
libharfbuzz>=0 libicu78>=78 libjpeg-turbo>=0 lcms2>=0 minizip>=0
nspr>=0 nss>=0 libopenjpeg2>=0 opus>=0 libpng>=0 snappy>=0
libstdc++>=0 tiff>=0 eudev-libudev>=0 libwebp>=0 libxcb>=0
libxkbcommon>=0 libxkbfile>=0 libxslt>=0 zlib>=0'
requires=$(find "$pkg/usr/lib" -type f \( -name '*.so*' -o -path '*/libexec/*' \) \
	-exec patchelf --print-needed {} + | sort -u |
	sed '/^libQt6WebEngine/d; /^libxml2.so./d' | tr '\n' ' ')
python3 "$dir/modules/04-apps/qutebrowser/update.py" verify "$tmp" "$qt_version"
if [ "$mode" = --prepare-update ]; then
	printf '%s\n' "$requires" >"$tmp/requires"
	deps=$(python3 "$dir/modules/04-apps/qutebrowser/update.py" dependencies "$tmp/update.json" "$tmp/requires")
fi
(
	cd "$repo"
	xbps-create -q -A x86_64 -n qt6-webengine-${pkg_version} \
		-s 'Qt WebEngine with VA-API (Homebrew Linux binaries)' \
		-l 'LGPL-3.0-only, BSD-3-Clause, MIT' -H https://www.qt.io \
		-D "$deps" -C "qt6-core>=$qt_upper" \
		--shlib-provides "$provides" --shlib-requires "$requires" "$pkg"
	xbps-rindex -fa qt6-webengine-${pkg_version}.x86_64.xbps
)
[ "$mode" != --build-only ] || exit 0

# 用相同包名满足 qutebrowser 的依赖，并让普通系统更新保留本地版本。
system_repo=/var/cache/xbps/qutebrowser
sudo install -d "$system_repo" /etc/xbps.d
sudo install -m 644 "$repo/qt6-webengine-${pkg_version}.x86_64.xbps" "$system_repo/"
sudo xbps-rindex -fa "$system_repo/qt6-webengine-${pkg_version}.x86_64.xbps"
printf 'repository=%s\n' "$system_repo" >"$tmp/10-qutebrowser.conf"
sudo install -m 644 "$tmp/10-qutebrowser.conf" /etc/xbps.d/10-qutebrowser.conf
if [ "$mode" = --prepare-update ]; then
	echo "本地 QtWebEngine $pkg_version 已准备好，由下一步 XBPS 系统升级一起安装。"
	exit 0
fi
sudo xbps-install -y -R "$system_repo" qt6-webengine
sudo xbps-pkgdb -m repolock qt6-webengine
if ! xbps-query -p pkgver qutebrowser >/dev/null 2>&1; then
	sudo xbps-install -y qutebrowser
fi

config=${XDG_CONFIG_HOME:-$HOME/.config}/qutebrowser
mkdir -p "$(dirname -- "$config")"
if [ -L "$config" ]; then
    saved=$(mktemp -d "$(dirname -- "$config")/.qutebrowser.XXXXXX")
    cp -a "$config/." "$saved/"
    unlink "$config"
    mv "$saved" "$config"
fi
mkdir -p "$config/bookmarks"
backup=
for name in config.py autoconfig.yml bilibili.py bilibili-api.py fcitx.py site-zoom.py start.html quickmarks bookmarks/urls greasemonkey lib; do
    if [ -e "$config/$name" ] && [ ! -L "$config/$name" ]; then
        [ -n "$backup" ] || backup=$(mktemp -d "$(dirname -- "$config")/.qutebrowser-backup.XXXXXX")
        mv "$config/$name" "$backup/"
    fi
    ln -sfnT "$dir/root/home/.config/qutebrowser/$name" "$config/$name"
done
echo '广告规则首次使用或更新：在 qute 中执行 :adblock-update。'
echo '完成：直接启动 qutebrowser。内核由本地 XBPS 包管理。'
