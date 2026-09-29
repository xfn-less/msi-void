#!/bin/sh
set -eu

if [ "${RENEWED_LINEAGE:-}" != /etc/letsencrypt/live/memo.xfnss.top ]; then
    exit 0
fi

install -d -o xfn -g xfn -m 700 /home/xfn/.config/tg-note/tls
install -o xfn -g xfn -m 600 "$RENEWED_LINEAGE/fullchain.pem" /home/xfn/.config/tg-note/tls/fullchain.pem
install -o xfn -g xfn -m 600 "$RENEWED_LINEAGE/privkey.pem" /home/xfn/.config/tg-note/tls/privkey.pem
systemctl try-restart tg-note.service
