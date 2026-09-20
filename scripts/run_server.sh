#!/usr/bin/env bash
# 개발용: 프로젝트 소스에서 전용 서버를 headless 로 실행한다.
# 사용: scripts/run_server.sh [--port=7777] [--data-dir=경로] [--config=경로] [--log-level=debug]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
if [ ! -d "$ROOT/.godot" ]; then
  echo "[run_server] first run: importing project (builds class cache)"
  "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --headless --path "$ROOT" -- --server "$@"
