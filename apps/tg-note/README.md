# Telegram File Note

单人使用的 Telegram Web K 便签。Go 标准库后端，一个群一个 UTF-8 明文文件；Violentmonkey 脚本负责查看和编辑。不使用数据库、加密、iframe 或 Text Vault。

```text
data/
  客户A项目群.txt
  台子.txt
```

## 运行

需要 Go 1.24+，没有第三方 Go 依赖：

```sh
cd apps/tg-note
export TG_NOTE_TOKEN='替换为至少32字符的随机Token'
export TG_NOTE_DIR='/你的绝对路径/tg-notes'
go build -o tg-note .
./tg-note
```

可用 `openssl rand -hex 32` 生成 Token。不要使用 README 中的占位值。

默认只监听 `127.0.0.1:8790`。环境变量：

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `TG_NOTE_TOKEN` | 必填 | 读写鉴权，至少 32 字符 |
| `TG_NOTE_DIR` | `data` | 文件目录，长期运行建议绝对路径 |
| `TG_NOTE_ADDR` | `127.0.0.1:8790` | 监听地址 |
| `TG_NOTE_TLS_CERT` | 空 | 可选 TLS 证书文件 |
| `TG_NOTE_TLS_KEY` | 空 | 可选 TLS 私钥文件 |

公网使用 HTTPS。可沿用现有反向代理，例如 Caddy：

```caddyfile
notes.example.com {
    reverse_proxy 127.0.0.1:8790
}
```

只代理 Go 服务，不要把 `data/` 配成公开静态目录。也可设置 `TG_NOTE_TLS_CERT`、`TG_NOTE_TLS_KEY` 和监听地址，由 Go 直接提供 HTTPS。域名不是硬性要求，证书必须与访问地址匹配并受浏览器信任。

长期运行时交给现有 runit / systemd 等进程管理器，固定运行用户、数据路径和 Token。定期备份数据目录；原子写入不能替代磁盘故障或误操作备份。更新程序或重启不会删除便签。

## 安装脚本

1. 将 `telegram-note.user.js` 安装进 Violentmonkey，停用旧 Workflowy 便签脚本。
2. 打开 Telegram Web K 的任意聊天，点便签的 **设置**，或用户脚本菜单“设置便签服务器”。
3. 默认服务器地址为 `https://memo.xfnss.top:8443`，填入服务器的 Token。
4. 首次跨域连接时允许 Violentmonkey 访问这个服务器。改用其他主机时，同时修改脚本的 `@connect memo.xfnss.top` 为实际主机名。

服务器地址和 Token 保存在用户脚本管理器中，无需每次登录。只允许 HTTPS；本机 `localhost` / `127.0.0.1` / `::1` 调试可用 HTTP。

## 使用

- 按当前聊天标题精确匹配，同名聊天共用一份文件。
- 没有文件时显示空编辑框，首次保存创建文件。
- 在编辑框内按 **Ctrl+S / Cmd+S**，或点 **保存**。
- **整个便签浅红**代表有未保存内容。保存成功恢复深色；失败保留浅红和错误提示。
- 保存期间继续输入，后输入的内容仍标记为未保存。
- 草稿按群名保存在用户脚本本地存储中，切群和刷新后可恢复。浏览器提示离开时可以取消。
- 点 **↻** 从文件重新读取；有草稿时会先询问是否放弃，读取失败仍保留草稿。
- 标题只显示名称，不再点击复制。拖动标题栏空白或左侧把手；折叠状态和位置会记住。
- 打开聊天时，点 **铺满** 覆盖右侧聊天区域，再点 **还原** 回到悬浮窗；铺满偏好会记住。
- 没有打开聊天时，右侧自动铺满显示全部便签文件，点击文件进入编辑，点 **← 全部文件** 返回。返回列表和切换文件都会保留草稿。
- 列表读取便签目录中的普通 `.txt` 文件，忽略目录、符号链接和临时文件；文件名遵循下方转义规则。手动新增文件后点 **↻** 刷新列表。
- 在服务器直接用文本编辑器修改 `.txt`，然后点悬浮窗 **↻**。没有自动监视文件变化，也没有历史版本。

单人、单实例，采用最后一次保存覆盖文件。外部编辑后先刷新再继续编辑，避免旧编辑框覆盖手工修改。群改名时手工重命名 `.txt` 即可。

普通名称直接使用 `群名.txt`。斜杠、反斜杠、百分号和 ASCII 控制字符会百分号转义，例如 `项目/生产` 对应 `项目%2F生产.txt`；不会把群名当作目录路径。转义后的文件名主体最多 240 UTF-8 字节，超过时明确报错；正文最多 256 KiB。

## 接口与验证

所有接口都要求 `Authorization: Bearer <TG_NOTE_TOKEN>`：

```text
GET /api/note?title=<URL编码的群名>   → 200 text/plain；无文件 404
PUT /api/note?title=<URL编码的群名>   → 请求体为 UTF-8 纯文本；保存成功 204
GET /api/notes                     → 200 JSON：{"titles":["群名", ...]}
```

缺少或无效群名返回 400，无效 Token 返回 401，正文过大返回 413，文件读写失败返回 500。响应禁止缓存。保存使用同目录临时文件、文件同步、原子替换和目录同步；文件权限为 0600。

```sh
go test -race ./...
go vet ./...
node --check telegram-note.user.js
```

Telegram 改版时，优先检查脚本里的 `getCurrentChatTitle()`。脚本不会解析正文 HTML，也不会自动向 Telegram 发消息。

## 当前部署

- 服务器：`xfn@23.26.201.235`
- HTTPS：`https://memo.xfnss.top:8443`
- 编译后的程序：`/home/xfn/work/tg-note`
- 明文便签：`/home/xfn/memo/群名.txt`
- 私有配置：`/home/xfn/.config/tg-note/env`
- 服务：`tg-note.service`，已配置开机启动、失败重启。
- 证书：Certbot 自动续期，续期后通过 `deploy/renew-tg-note.sh` 更新服务使用的证书并重启便签服务。HTTP 验证需要保留公网 80 端口可用；443 继续由原有 Xray 使用。

服务器已有下载服务公开 `/home/xfn/work`，因此这里只放不含凭证的可执行文件，便签和 Token 存在下载目录之外。

```sh
ssh xfn@23.26.201.235 'sudo systemctl status tg-note --no-pager'
ssh xfn@23.26.201.235 'sudo journalctl -u tg-note -n 30 --no-pager'
```

更新时将新二进制先上传为 `~/work/tg-note.new`，校验后赋予执行权限、重命名替换 `~/work/tg-note`，再 `sudo systemctl restart tg-note`。便签目录不受程序更新影响。
