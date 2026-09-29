# MSI Void Linux 配置总览

这份文档记录仓库中目前为 **MSI Stealth 14 AI Studio A1VFG** 准备的全部系统配置。
它只说明现状；`apps/`、`archive/` 和项目设计文档不属于系统配置。

## 1. 基础系统

入口：`modules/01-system.sh`

### 软件源

| 文件 | 作用 |
|---|---|
| `root/etc/xbps.d/00-repository-main.conf` | Void glibc 主仓库 |
| `root/etc/xbps.d/20-nonfree.conf` | nonfree 仓库，用于 Intel 微码等 |
| `root/etc/xbps.d/30-ignore-nvidia.conf` | 不安装 `linux-firmware-nvidia` |

### 主机与权限

- `/etc/hostname` 由安装系统时手动设置。
- 脚本根据 hostname 重写 `/etc/hosts`。
- 为当前用户创建 `/etc/sudoers.d/zz-USER-nopasswd`，允许无密码 sudo。

### 网络

安装：

```text
wpa_supplicant dhcpcd iw
```

启用 runit 服务：

```text
wpa_supplicant
dhcpcd
```

Wi-Fi 凭据只保存在本机 `/etc/wpa_supplicant/wpa_supplicant.conf`，不进入仓库。

### 时间

安装 `chrony`，启用 `chronyd` 服务。

### 基础命令

```text
bash-completion git openssh fzf file chafa
```

脚本链接以下用户配置：

```text
~/.bash_profile
~/.bashrc
~/.inputrc
~/.npmrc
~/.config/htop/htoprc
~/.local/bin/xb
```

## 2. MSI 硬件

入口：`modules/02-hardware/msi.sh`

安装：

| 包 | 作用 |
|---|---|
| `intel-ucode` | Intel CPU 微码 |
| `mesa-dri` | Intel 图形驱动 |
| `intel-video-accel` | 硬件视频解码 |
| `sof-firmware` | MSI 的 SOF 声卡固件 |

### CPU

`root/etc/rc.local.d/cpufreq` 将所有 CPU 核心的 governor 设为：

```text
powersave
```

`msi.sh` 会把它安装到 `/etc/rc.local.d/cpufreq`，并确保 `/etc/rc.local`
调用该脚本。

### NVIDIA

当前配置不安装 NVIDIA 固件，也没有安装 NVIDIA 驱动。桌面使用 Intel 核显。

## 3. 双系统启动

入口：`modules/02-hardware/msi/boot.sh`

| 文件 | 作用 |
|---|---|
| `root/etc/default/grub.msi` | 隐藏 GRUB 菜单，等待 1 秒，默认第 0 项 |
| `root/etc/grub.d/09_windows` | 把 Windows 放在 Void 前面 |

行为：

1. 主板 EFI 首先启动 `void` 的 GRUB。
2. GRUB 默认启动第 0 项 Windows。
3. 开机时按 Esc 可显示菜单并选择 Void。
4. 脚本通过 `efibootmgr` 将 `void` EFI 项排在 Windows 前面。

`09_windows` 中写死了本机 EFI 分区 UUID：`0009-85C1`。

## 4. Niri 桌面

入口：`modules/03-desktop/niri.sh`  
配置：`root/home/.config/niri/config.kdl`

### 基础包

```text
niri dbus seatd
```

启用 `dbus`、`seatd` 服务，并把用户加入 `_seatd` 组。

### 显示

支持仓库里记录的两块 MSI 面板，均设置：

```text
2560x1600
scale 1.5
60 Hz
```

### 输入与窗口

- 键盘重复：延迟 200 ms，速率 30。
- 触控板：轻触、自然滚动、clickfinger、速度 0.2。
- 鼠标跟随焦点。
- 默认列宽为屏幕的 0.618。
- 无间距、无焦点框、关闭动画。
- 窗口阴影开启。

### 自动启动

```text
swayidle
fcitx5
alacritty
wlsunset
```

空闲行为：

- 180 秒：`swaylock` 纯黑锁屏。
- 240 秒：关闭显示器。

### 快捷键调用的程序

| 功能 | 程序 |
|---|---|
| 终端 | Alacritty |
| 浏览器 | Firefox |
| 色温 | wlsunset |
| 亮度 | brightnessctl |
| 音量 | amixer |
| 全屏截图 | grim + wl-copy + swappy |
| 区域截图 | slurp + grim + wl-copy + swappy |
| 深浅色切换 | gsettings + GNOME schemas/themes |

对应包：

```text
wlsunset brightnessctl xdg-utils
gnome-themes-extra glib gsettings-desktop-schemas
swayidle swaylock
grim slurp swappy wl-clipboard
```

启动方式：

```sh
dbus-run-session niri --session
```

也可在 Bash 中运行 `ni`。

## 5. 终端与字体

入口：`modules/03-desktop/terminal-fonts.sh`

安装：

```text
alacritty font-inconsolata-otf wqy-microhei
```

配置：

- Alacritty 字号：14.5。
- 英文默认字体：Inconsolata。
- 中文字体：WenQuanYi Micro Hei Mono。
- fontconfig 将 monospace、sans-serif、serif 都优先指向 Inconsolata。

## 6. 中文输入

入口：`modules/03-desktop/input-method.sh`

安装：

```text
fcitx5 fcitx5-chinese-addons
```

配置：

- 默认英文。
- 输入框获得焦点时重置为英文。
- 输入状态不在不同输入框之间共享。
- 双拼方案记录为自然码。
- 保留 classic UI、拼音和剪贴板附加配置。

当前 `profile` 中输入法名称为 `zrm`。如果它来自已删除的 Rime 配置，
这项需要重新确认是否仍可由 `fcitx5-chinese-addons` 提供。

## 7. 声音

入口：`modules/03-desktop/audio.sh`

当前只安装：

```text
alsa-utils
```

Niri 音量键调用 `amixer` 调整 `Master`。  
当前配置不启动 PipeWire，也没有 `.asoundrc`。

## 8. 键盘重映射

入口：`modules/03-desktop/keyd.sh`

安装并启用 `keyd`，复制三份按设备 ID 匹配的配置：

| 文件 | 对象 |
|---|---|
| `root/etc/keyd/laptop.conf` | MSI 内置键盘（ID `0001`） |
| `root/etc/keyd/60.conf` | ID `1a2c`、`41e4` 的外接设备 |
| `root/etc/keyd/new.conf` | ID `feed`、`3601` 的外接设备 |

主要行为包括：

- Space/Caps/Enter 等按键兼作修饰层。
- `IJKL` 作为方向键。
- Home/End/PageUp/PageDown 导航层。
- 部分外接键盘进行字母和符号位置重排。

## 9. Bash 与 fzf

配置：`root/home/.bashrc`

- Prompt：时间 + 当前目录。
- fzf：
  - Ctrl-T 选文件。
  - Alt-C 选目录。
  - Ctrl-R 搜历史。
  - 图片通过 chafa 预览。
  - 文本通过 sed 预览。
- `cd` 成功后自动 `ls`。
- `EDITOR`、`VISUAL` 均为 Vim。
- `ni` 从 TTY 启动 Niri。
- 保存十万条 Bash 历史，立即追加到历史文件。
- 每次显示 prompt 时更新终端标题。

`.inputrc` 额外设置：

- 上下方向键按当前前缀搜索历史。
- 补全忽略大小写。
- 关闭终端铃声。
- 补全结果显示颜色和文件类型。

`.bash_profile` 设置：

- `QT_QPA_PLATFORMTHEME=xdgdesktopportal`
- Go 和 npm 用户目录加入 PATH。

## 10. Vim

- 系统包：`vim`
- `.vimrc` 只把 table-mode 表格角设为 `|`。
- `vim-table-mode` 插件实际位于用户目录，不由仓库安装脚本管理。

## 11. Firefox

- 系统包：`firefox`
- Niri 的 `Mod+c` 直接启动 Firefox。
- `Mod+t` 打开 `http://127.0.0.1:8787`。
- 无 Firefox 专用配置。

## 12. XBPS 辅助命令

`root/home/.local/bin/xb` 提供：

| 命令 | 功能 |
|---|---|
| `xb g` | 更新系统 |
| `xb k` | 清理旧内核 |
| `xb o` | 交互删除孤儿包 |
| `xb a` | 从全部包中交互删除 |
| `xb r` | 删除不在 `packages.list` 的手动包 |
| `xb s` | 跨已启用仓库搜索并安装 |

## 13. Mihomo（可选）

入口：`modules/05-optional/mihomo.sh`

- 从 GitHub 下载 Mihomo 到 `/usr/local/bin/mihomo`。
- 私有配置位于 `/etc/mihomo/config.yaml`，不进入仓库。
- 仓库只保存配置模板。
- 通过 runit 启用 `/etc/sv/mihomo`。
- 日志写入 `/var/log/sv/mihomo`。
- 用户控制脚本：`~/.local/bin/mihomoctl`。

## 14. 软件清单

`packages.list` 还记录以下按需软件：

```text
StyLua shfmt ruff go nodejs
htop fastfetch dufs socklog-void mesa-vulkan-radeon
telegram-desktop zip unzip 7zip xz imv mpv
```

这些不是 MSI 启动或 Niri 运行所必需。

## 15. 当前已知的不一致

以下内容只是记录，尚未处理：

1. `modules/01-system.sh` 仍尝试链接已经删除的 `mimeapps.list`。
2. `root/etc/tlp.d/10-laptop.conf` 仍在仓库，但 TLP 已不再使用。
3. `30-ignore-nvidia.conf` 的注释仍写“两台机器”，现在仓库只维护 MSI。
4. Fcitx profile 中的 `zrm` 需要确认是否仍有效。
5. Niri 模块开头仍写“壁纸”，但壁纸和 swaybg 已删除。
6. ALSA 能驱动硬件，但现代浏览器是否能直接输出声音需要实际验证。
7. `packages.list` 含若干旧的按需软件，不代表当前都需要。
