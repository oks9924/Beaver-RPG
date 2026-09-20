#!/usr/bin/env bash
# export 스모크 테스트: export 된 Linux 서버·클라이언트 실행 파일을 프로젝트 폴더가 아닌 곳(/tmp)에서 실행해
# 서버 접속·가입·원정 한 사이클과 "export 본에서 에셋이 ID 로 로드되는가"(AST-01 export 항목)를 검사한다.
# 사용: tests/integration/run_export_smoke.sh [godot]   (build/linux-server, build/linux 가 없으면 export 부터 한다)
set -u
GODOT="${1:-${GODOT:-godot}}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tests/out/export_smoke"; PORT=7861
rm -rf "$OUT"; mkdir -p "$OUT/data"
cd "$ROOT"
[ -x build/linux-server/tail-expedition-server.x86_64 ] || "$GODOT" --headless --path "$ROOT" --export-release "Linux Server" build/linux-server/tail-expedition-server.x86_64 >/dev/null 2>&1
[ -x build/linux/TailExpedition.x86_64 ] || "$GODOT" --headless --path "$ROOT" --export-release "Linux Client" build/linux/TailExpedition.x86_64 >/dev/null 2>&1
[ -x build/linux-server/tail-expedition-server.x86_64 ] && [ -x build/linux/TailExpedition.x86_64 ] || { echo "[export-smoke] export missing"; exit 1; }
# 프로젝트 소스가 보이지 않는 별도 위치로 복사해 실행한다 (원본 png 를 우연히 읽는 상황 방지)
WORK="$(mktemp -d)"
cp build/linux-server/tail-expedition-server.x86_64 build/linux/TailExpedition.x86_64 "$WORK/"
cd "$WORK"
./tail-expedition-server.x86_64 --headless -- --port=$PORT --data-dir="$OUT/data" > "$OUT/server.log" 2>&1 &
SP=$!
sleep 3
timeout 90 ./TailExpedition.x86_64 --headless -- --bot=expedition --create --starter --party=1 --nick=export_bot --addr=127.0.0.1:$PORT --out="$OUT/bot.json" --timeout=80 > "$OUT/client.log" 2>&1
kill $SP 2>/dev/null; wait $SP 2>/dev/null
rm -rf "$WORK"
python3 - "$OUT/bot.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ac = d.get("asset_check", {})
fails = []
if not d.get("ok"): fails.append("expedition flow failed: %s" % d.get("errors"))
if not ac.get("exported"): fails.append("not running as exported build")
if ac.get("fallbacks"): fails.append("assets fell back to placeholder box: %s" % ac["fallbacks"])
if not ac.get("font_ok"): fails.append("font did not load")
if not ac.get("audio_ok"): fails.append("audio did not load")
if d.get("events", {}).get("kills", 0) < 1: fails.append("no kills in exported build")
print("export smoke:", "OK" if not fails else "FAIL", ac)
for f in fails: print("  FAIL", f)
sys.exit(1 if fails else 0)
PY
