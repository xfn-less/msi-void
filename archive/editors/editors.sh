#!/bin/sh
# 功能：只链接 Emacs、Neovim 配置，不安装应用
# 生效：下次打开编辑器
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
h=$repo/root/home
mkdir -p "$HOME/.config" "$HOME/.local/bin"
config=$HOME/.config/emacs
if [ -L "$config" ]; then
    saved=$(mktemp -d "$HOME/.config/.emacs.XXXXXX")
    cp -a "$config/." "$saved/"
    unlink "$config"
    mv "$saved" "$config"
fi
mkdir -p "$config"
backup=
for name in init.el early-init.el lisp; do
    if [ -e "$config/$name" ] && [ ! -L "$config/$name" ]; then
        [ -n "$backup" ] || backup=$(mktemp -d "$HOME/.config/.emacs-backup.XXXXXX")
        mv "$config/$name" "$backup/"
    fi
    ln -sfnT "$h/.config/emacs/$name" "$config/$name"
done
ln -sfnT "$h/.config/nvim" "$HOME/.config/nvim"
