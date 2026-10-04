#!/bin/bash
# Debian12：xrdp+TG+sakura+Firefox+fcitx5；公网 40296/443/8443/9443；3389 仅本机
# 隧道 ssh -p 40296 -N -L 3389:127.0.0.1:3389 xfn@主机
# SSH：99-harden.conf；重连前 pkill Xorg openbox telegram-desktop sakura firefox tint2
# 会话：~/.xsession（fcitx5 + TG + sakura + tint2 + openbox）
# 输入法：自然码 zrm（词库 fcitx5-chinese-addons/libime；用户词 ~/.local/share/fcitx5/table/zrm.*）

sudo apt-get update
sudo apt-get install --no-install-recommends \
  xrdp xorgxrdp openbox sakura tint2 dbus-x11 fonts-wqy-microhei telegram-desktop \
  firefox-esr \
  fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5

mkdir -p ~/.config/fcitx5
cat > ~/.config/fcitx5/profile <<'EOF'
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

cat > ~/.xsession <<'EOF'
#!/bin/sh
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
fcitx5 -d &
telegram-desktop &
sakura &
tint2 &
exec openbox
EOF
chmod +x ~/.xsession

sudo adduser "$USER" ssl-cert
sudo sed -i '0,/^port=3389$/s//port=tcp:\/\/127.0.0.1:3389/' /etc/xrdp/xrdp.ini
sudo systemctl enable --now xrdp
