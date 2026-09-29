# Xray 独立服务器：手动安装
只作服务器操作记录，不参与 Void 桌面安装。适用 systemd 服务器，需要 root、curl、unzip、OpenSSL。使用 XTLS 官方安装器和已核对校验值的 Xray-linux-64.zip；不在仓库保存凭据。
官方入口：https://github.com/XTLS/Xray-install 和 https://github.com/XTLS/Xray-core/releases

## 安装
把核对过的官方 install-release.sh 和 Xray-linux-64.zip 放进 /tmp，再运行：
```sh
sudo useradd --system --home-dir /var/lib/xray --create-home --shell /usr/sbin/nologin xray
sudo sh /tmp/install-release.sh install --local /tmp/Xray-linux-64.zip --install-user xray
sudo /usr/local/bin/xray uuid
sudo /usr/local/bin/xray x25519
openssl rand -hex 8
```
记下 UUID、私钥、客户端公钥参数（新版输出可能叫 Password）和 short ID，只在服务器私有文件保存。客户端仅需要 UUID、公钥参数、short ID、地址、端口及 SNI。

## 配置
手动创建 /usr/local/etc/xray/config.json，把下面占位字段换成实际值。先分别验证 HK、CN 的 exit，再在 HK 添加 relay，避免混在一起排障。
exit：
```json
{
  "log": {"loglevel": "warning"},
  "routing": {
    "rules": [
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "BLOCK"}
    ]
  },
  "inbounds": [
    {
      "tag": "VLESS-Reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "__UUID__", "flow": "xtls-rprx-vision", "email": "xfn"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "www.nvidia.com:443",
          "xver": 0,
          "serverNames": ["www.nvidia.com"],
          "privateKey": "__PRIVATE_KEY__",
          "shortIds": ["__SHORT_ID__"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "DIRECT"},
    {"protocol": "blackhole", "tag": "BLOCK"}
  ]
}
```
HK relay（HK 443 自己出口；HK 9443 原样转发到 CN 443）：
```json
{
  "log": {"loglevel": "warning"},
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["CN-TCP-Relay"], "outboundTag": "DIRECT"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "BLOCK"}
    ]
  },
  "inbounds": [
    {
      "tag": "HK-VLESS-Reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "__UUID__", "flow": "xtls-rprx-vision", "email": "xfn"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "www.nvidia.com:443",
          "xver": 0,
          "serverNames": ["www.nvidia.com"],
          "privateKey": "__PRIVATE_KEY__",
          "shortIds": ["__SHORT_ID__"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "CN-TCP-Relay",
      "listen": "0.0.0.0",
      "port": 9443,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "__RELAY_ADDRESS__",
        "port": 443,
        "network": "tcp",
        "followRedirect": false
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "DIRECT"},
    {"protocol": "blackhole", "tag": "BLOCK"}
  ]
}
```
__RELAY_ADDRESS__ 为 CN 地址；其他占位字段为上一步生成的本机参数。www.nvidia.com 是 Reality TLS 目标及 SNI，不是业务流量出口。
验证通过再启用：
```sh
sudo chown root:xray /usr/local/etc/xray/config.json
sudo chmod 640 /usr/local/etc/xray/config.json
sudo /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
sudo systemctl enable --now xray
sudo systemctl restart xray
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 50 --no-pager
sudo ss -lntp
```
防火墙：HK 对公网只需 TCP 22/443/9443；CN TCP 443 仅允许 HK IP /32。客户端 CN 节点填 HK:9443，但使用 CN 的 Reality 参数。先测试两条出口，再恢复 Mihomo rule split。已有服务器改配置前自行备份；旧 Marzban 暂不删除，测试及重启通过后再决定。
