#!/usr/bin/env bash
# 개발용: 프로젝트 소스에서 클라이언트를 실행한다 (창 필요). --connect=host:port 로 바로 접속 화면을 건너뛸 수 있다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
if [ ! -d "$ROOT/.godot" ]; then
  "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path "$ROOT" -- "$@"
