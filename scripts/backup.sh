#!/usr/bin/env bash
# 서버 영구 데이터(계정·월드) 백업. 서버가 켜져 있어도 안전하다 (원자적 rename 으로 쓰인 파일만 복사).
# 사용: backup.sh [data_dir] [backup_root]
set -euo pipefail
DATA="${1:-$(dirname "$0")/server_data}"
DEST_ROOT="${2:-$(dirname "$0")/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$DEST_ROOT/$STAMP"
mkdir -p "$DEST"
for f in accounts.json world.json; do
  [ -f "$DATA/$f" ] && cp -p "$DATA/$f" "$DEST/$f"
done
echo "[backup] $DEST"
# 30일 지난 백업 정리
find "$DEST_ROOT" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
