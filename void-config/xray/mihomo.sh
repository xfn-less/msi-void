#!/bin/sh
set -eu

# 配置固定放在 /home/xfn/work/xray-config/mihomo-config.yaml
# 安装或更新：sh mihomo.sh

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

case $(uname -m) in
x86_64) ;;
*) printf '%s\n' '只支持本机 x86_64。' >&2; exit 1 ;;
esac

if [ "$#" -ne 0 ]; then
	printf '%s\n' 'usage: sh mihomo.sh' >&2
	exit 2
fi

config=/home/xfn/work/xray-config/mihomo-config.yaml
[ -f "$config" ] || {
	printf '配置不存在：%s\n' "$config" >&2
	exit 1
}

missing=
for package in curl gzip python3; do
	xbps-query -p pkgver "$package" >/dev/null 2>&1 || missing="$missing $package"
done
[ -z "$missing" ] || sudo xbps-install -y $missing

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' 0 1 2 15

curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
	-o "$tmp/release.json"

python3 - "$tmp/release.json" >"$tmp/asset" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    release = json.load(file)

tag = release["tag_name"]
name = f"mihomo-linux-amd64-v1-{tag}.gz"
asset = next(item for item in release["assets"] if item["name"] == name)
digest = asset.get("digest", "")
if not digest.startswith("sha256:"):
    raise SystemExit("release asset has no SHA-256 digest")

print(tag)
print(asset["browser_download_url"])
print(digest.removeprefix("sha256:"))
PY

tag=$(sed -n '1p' "$tmp/asset")
url=$(sed -n '2p' "$tmp/asset")
sha256=$(sed -n '3p' "$tmp/asset")

printf '下载 Mihomo %s\n' "$tag"
curl -fL "$url" -o "$tmp/mihomo.gz"
printf '%s  %s\n' "$sha256" "$tmp/mihomo.gz" | sha256sum -c -
gzip -dc "$tmp/mihomo.gz" >"$tmp/mihomo"
chmod 755 "$tmp/mihomo"
"$tmp/mihomo" -v

sudo install -d -m 755 /etc/sv/mihomo/log
sudo install -d -m 700 /var/lib/mihomo/providers /var/log/sv/mihomo
sudo "$tmp/mihomo" -t -d /var/lib/mihomo -f "$config"

sudo install -m 755 "$tmp/mihomo" /usr/local/bin/mihomo.new
sudo mv -f /usr/local/bin/mihomo.new /usr/local/bin/mihomo
sudo install -m 755 "$dir/mihomoctl" /usr/local/bin/mihomoctl

chmod 600 "$config"

cat <<'EOF' | sudo tee /etc/sv/mihomo/run >/dev/null
#!/bin/sh
exec /usr/local/bin/mihomo \
	-d /var/lib/mihomo \
	-f /home/xfn/work/xray-config/mihomo-config.yaml 2>&1
EOF
sudo chmod 755 /etc/sv/mihomo/run

cat <<'EOF' | sudo tee /etc/sv/mihomo/log/run >/dev/null
#!/bin/sh
install -d -m 700 /var/log/sv/mihomo
exec svlogd -tt /var/log/sv/mihomo
EOF
sudo chmod 755 /etc/sv/mihomo/log/run

sudo ln -sfnT /etc/sv/mihomo /var/service/mihomo
if sudo sv status mihomo 2>/dev/null | grep -q '^run:'; then
	sudo sv -w 15 restart mihomo
else
	n=0
	until sudo sv status mihomo >/dev/null 2>&1; do
		n=$((n + 1))
		[ "$n" -lt 15 ] || { printf '%s\n' 'Mihomo 服务未启动。' >&2; exit 1; }
		sleep 1
	done
	sudo sv -w 15 up mihomo
fi

sudo sv status mihomo
printf '%s\n' '完成。运行 mihomoctl status 查看状态。'
