#!/usr/bin/env bash
# 재현 가능한 빌드: export preset 으로 Windows 클라이언트, Linux/Windows 전용 서버를 만든다.
# 요구: Godot 4.4.1 편집기 바이너리(GODOT 환경변수 또는 PATH 의 godot), 같은 버전의 export templates.
# 사용: scripts/build.sh [all|windows-client|linux-server|windows-server|linux-client]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TARGET="${1:-all}"
VERSION="$(grep -oP 'const BUILD_VERSION: String = "\K[^"]+' "$ROOT/shared/protocol.gd")"
cd "$ROOT"
echo "[build] godot: $("$GODOT" --version)  build version: $VERSION"
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
export_one() { # preset, output
  mkdir -p "$(dirname "$2")"
  echo "[build] export '$1' -> $2"
  "$GODOT" --headless --path "$ROOT" --export-release "$1" "$2" 2>&1 | grep -iE "error" && { echo "[build] export failed: $1"; exit 1; } || true
  [ -f "$2" ] || { echo "[build] missing output: $2"; exit 1; }
}
case "$TARGET" in
  all)
    export_one "Windows Client" "build/windows/TailExpedition.exe"
    export_one "Linux Server" "build/linux-server/tail-expedition-server.x86_64"
    export_one "Windows Server" "build/windows-server/tail-expedition-server.exe"
    ;;
  windows-client) export_one "Windows Client" "build/windows/TailExpedition.exe" ;;
  linux-server)   export_one "Linux Server" "build/linux-server/tail-expedition-server.x86_64" ;;
  windows-server) export_one "Windows Server" "build/windows-server/tail-expedition-server.exe" ;;
  linux-client)   export_one "Linux Client" "build/linux/TailExpedition.x86_64" ;;
  *) echo "unknown target $TARGET"; exit 2 ;;
esac
# 서버 묶음에는 예제 설정·운영 스크립트를 같이 넣는다.
for d in build/linux-server build/windows-server; do
  [ -d "$d" ] || continue
  cp -f scripts/server_config.example.json "$d/server_config.example.json"
  cp -f scripts/backup.sh "$d/" 2>/dev/null || true
  cp -f scripts/tail-expedition-server.service "$d/" 2>/dev/null || true
  echo "$VERSION" > "$d/VERSION"
done
[ -d build/windows ] && echo "$VERSION" > build/windows/VERSION
echo "[build] done"
ls -la build/*/ 2>/dev/null || true
