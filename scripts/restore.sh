#!/usr/bin/env bash
# 백업 복구: 서버를 멈춘 뒤 실행한다. 사용: restore.sh <backup_dir> [data_dir]
set -euo pipefail
SRC="$1"; DATA="${2:-$(dirname "$0")/server_data}"
mkdir -p "$DATA"
for f in accounts.json world.json; do
  [ -f "$SRC/$f" ] && cp -p "$SRC/$f" "$DATA/$f" && echo "[restore] $f"
done
