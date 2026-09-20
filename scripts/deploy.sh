#!/usr/bin/env bash
# 운영 서버용 배포 스크립트 (Ubuntu). GitHub Release 의 linux-server 묶음을 받아 /opt/tail-expedition/<version> 에 풀고
# current 심볼릭 링크를 바꾼 뒤 systemd 서비스를 재시작한다. 롤백은 current 링크를 이전 버전으로 되돌리면 된다.
# 사용: sudo deploy.sh <version-tag>   예) sudo deploy.sh v0.1.0
#       sudo deploy.sh --rollback <version-tag>
set -euo pipefail
REPO="${REPO:-oks9924/Beaver-RPG}"
BASE="/opt/tail-expedition"
SERVICE="tail-expedition-server"
if [ "${1:-}" = "--rollback" ]; then
  VER="$2"
  [ -d "$BASE/$VER" ] || { echo "no such version $VER"; exit 1; }
  ln -sfn "$BASE/$VER" "$BASE/current"
  systemctl restart "$SERVICE"
  echo "[deploy] rolled back to $VER"; exit 0
fi
VER="${1:?version tag required, e.g. v0.1.0}"
ASSET="tail-expedition-server-linux-${VER}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VER}/${ASSET}"
mkdir -p "$BASE/$VER" "$BASE/server_data" "$BASE/backups"
echo "[deploy] downloading $URL"
curl -fsSL -o "/tmp/$ASSET" "$URL"
tar -xzf "/tmp/$ASSET" -C "$BASE/$VER"
chmod +x "$BASE/$VER/tail-expedition-server.x86_64"
[ -f "$BASE/server_config.json" ] || cp "$BASE/$VER/server_config.example.json" "$BASE/server_config.json"
if [ -f "$BASE/$VER/backup.sh" ]; then bash "$BASE/$VER/backup.sh" "$BASE/server_data" "$BASE/backups" || true; fi
if [ ! -f "/etc/systemd/system/$SERVICE.service" ]; then
  cp "$BASE/$VER/tail-expedition-server.service" "/etc/systemd/system/$SERVICE.service"
  id -u beaver >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin beaver
  chown -R beaver:beaver "$BASE"
  systemctl daemon-reload
  systemctl enable "$SERVICE"
fi
ln -sfn "$BASE/$VER" "$BASE/current"
chown -R beaver:beaver "$BASE"
systemctl restart "$SERVICE"
sleep 2
systemctl --no-pager status "$SERVICE" | head -5
echo "[deploy] $VER is live. logs: journalctl -u $SERVICE -f"
