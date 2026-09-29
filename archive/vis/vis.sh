#!/bin/sh
# 功能：从 Vis 官方 master 构建完整 Vis 本地 XBPS 包，并链接编辑器配置
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
src=$HOME/.local/src/vis
sudo xbps-install -Sy -y git
sudo xbps-install -y gcc make pkg-config binutils ncurses-devel lua54-devel lua54-lpeg tre-devel acl-devel
sudo xbps-pkgdb -m manual gcc make pkg-config binutils ncurses-devel lua54-devel lua54-lpeg tre-devel acl-devel

mkdir -p "$(dirname "$src")"
if [ -d "$src/.git" ]; then git -C "$src" pull --ff-only; else git clone --depth=1 https://github.com/martanne/vis.git "$src"; fi
work=$(mktemp -d /tmp/vis.XXXXXX)
trap 'rm -rf "$work"' EXIT
git clone --quiet --local "$src" "$work/source"
cd "$work/source"
commit=$(git rev-parse HEAD)
version=0.git$(git show -s --format=%ct HEAD)
./configure --prefix=/usr --enable-curses=yes --enable-lua=yes --disable-lpeg-static --enable-tre=yes --enable-acl=yes
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make install DESTDIR="$work/install"

deps=
for package in glibc ncurses-libs acl tre lua54 lua54-lpeg; do
	installed=$(xbps-query -p pkgver "$package")
	deps="$deps $package>=${installed#"$package"-}"
done
shlibs=$(readelf -d "$work/install/usr/bin/vis" "$work/install/usr/bin/vis-menu" "$work/install/usr/bin/vis-digraph" | sed -n 's/.*(NEEDED).*[\[]\(.*\)[\]].*/\1/p' | sort -u | tr '\n' ' ')
install -Dm644 LICENSE "$work/install/usr/share/licenses/vis/LICENSE"
printf '%s\n' "$commit" >"$work/install/usr/share/doc/vis/source-commit"
cd "$work"
xbps-create -A "$(xbps-uhelper arch)" -n "vis-${version}_1" -s 'Vi-like editor with structural regular expressions (Git build)' -l ISC -H https://github.com/martanne/vis -D "$deps" --shlib-requires "$shlibs" "$work/install"
package=$work/vis-${version}_1.$(xbps-uhelper arch).xbps
system_repo=/var/cache/xbps/vis
sudo mkdir -p "$system_repo"
sudo install -m644 "$package" "$system_repo/"
sudo xbps-rindex -fa "$system_repo/$(basename "$package")"
printf 'repository=%s\n' "$system_repo" >"$work/10-vis.conf"
sudo install -Dm644 "$work/10-vis.conf" /etc/xbps.d/10-vis.conf
sudo xbps-install -fy -R "$system_repo" "vis-${version}_1"
sudo xbps-pkgdb -m manual vis
sudo xbps-pkgdb -m repolock vis
[ "$(xbps-query -p pkgver vis)" = "vis-${version}_1" ]
/usr/bin/vis -v

# 避免旧的用户目录版本遮住 XBPS 管理的版本；旧文件可从备份恢复。
backup=
for name in bin/vis bin/vis-clipboard bin/vis-complete bin/vis-digraph bin/vis-menu bin/vis-open \
	share/vis share/doc/vis; do
	old=$HOME/.local/$name
	if [ -e "$old" ] || [ -L "$old" ]; then
		if [ -z "$backup" ]; then
			mkdir -p "$HOME/.local/state"
			backup=$(mktemp -d "$HOME/.local/state/vis-install-backup.XXXXXX")
		fi
		mkdir -p "$backup/$(dirname "$name")"
		mv "$old" "$backup/$name"
	fi
done
[ -z "$backup" ] || printf '旧版备份：%s\n' "$backup"
mkdir -p "$HOME/.config" "$HOME/.local/share/applications"
ln -sfnT "$repo/root/home/.config/vis" "$HOME/.config/vis"
ln -sfn "$repo/root/home/.local/share/applications/vis.desktop" "$HOME/.local/share/applications/vis.desktop"
printf '%s\n' 'Vis 已由 XBPS 管理；重新打开 Vis 即使用新版本。'
