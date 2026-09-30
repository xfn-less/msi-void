#!/bin/bash
# Debian12：xrdp+TG+sakura；公网 40296/443/8443/9443；3389 仅本机
# 隧道 ssh -p 40296 -N -L 3389:127.0.0.1:3389 xfn@主机
# SSH：99-harden.conf；重连前 pkill Xorg openbox telegram-desktop sakura
# 桌面：不写 ~/.xsession，走 /etc/X11/Xsession → openbox-session

sudo apt-get update
sudo apt-get install --no-install-recommends \
  xrdp xorgxrdp openbox sakura dbus-x11 fonts-wqy-microhei telegram-desktop

sudo adduser "$USER" ssl-cert
sudo sed -i '0,/^port=3389$/s//port=tcp:\/\/127.0.0.1:3389/' /etc/xrdp/xrdp.ini
sudo systemctl enable --now xrdp
