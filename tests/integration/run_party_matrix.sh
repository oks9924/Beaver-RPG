#!/usr/bin/env bash
# 파티 조합 검증 (BAL-01, 3단계): 동일 직업 4인 × 5, 힐러 없는 혼합 4인, 1인 × 5직업을 봇으로 완주 시도한다.
# 각 조합은 별도 서버(포트)에서 2층 경로(전투 2방)를 돈다. 결과는 out/party_matrix.md 에 표로 남긴다.
# 사용: tests/integration/run_party_matrix.sh [godot] [--layers=N]
set -u
GODOT="${1:-${GODOT:-godot}}"
LAYERS=2
for a in "$@"; do case "$a" in --layers=*) LAYERS="${a#--layers=}";; esac; done
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tests/out/party_matrix"
rm -rf "$OUT"; mkdir -p "$OUT"
run_combo() { # port name class1 [class2 class3 class4]   (서브셸에서 돌므로 포트를 인자로 받는다)
  local port="$1"; shift
  local name="$1"; shift
  local classes=("$@")
  local dir="$OUT/$name"; mkdir -p "$dir/data"
  cat > "$dir/config.json" <<JSON
{"port": $port, "max_online_players": 6, "max_active_expeditions": 1, "allow_registration": true, "data_dir": "$dir/data", "log_level": "info", "metrics_interval_sec": 10, "password_iterations": 2000, "debug_route_layers": $LAYERS}
JSON
  "$GODOT" --headless --path "$ROOT" -- --server --config="$dir/config.json" > "$dir/server.log" 2>&1 &
  local spid=$!
  for i in $(seq 1 40); do grep -q "listening on" "$dir/server.log" 2>/dev/null && break; sleep 0.25; done
  local n=${#classes[@]}
  local pids=()
  "$GODOT" --headless --path "$ROOT" -- --bot=expedition --nick="${name}_1" --class="${classes[0]}" --addr=127.0.0.1:$port --create --starter --party=$n --timeout=420 --out="$dir/b1.json" > "$dir/b1.log" 2>&1 &
  pids+=($!)
  sleep 1.5
  for i in $(seq 2 $n); do
    "$GODOT" --headless --path "$ROOT" -- --bot=expedition --nick="${name}_$i" --class="${classes[$((i-1))]}" --addr=127.0.0.1:$port --join=host:${name}_1 --timeout=420 --out="$dir/b$i.json" > "$dir/b$i.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  echo "[pm] $name done"
}
# 3개씩 병렬
run_combo 7841 g4 guardian guardian guardian guardian &
run_combo 7842 p4 pinecone pinecone pinecone pinecone &
run_combo 7843 s4 sawtooth sawtooth sawtooth sawtooth &
wait
run_combo 7844 h4 sapshaman sapshaman sapshaman sapshaman &
run_combo 7845 w4 hydro hydro hydro hydro &
run_combo 7846 mix_nohealer guardian pinecone sawtooth hydro &
wait
run_combo 7847 solo_g guardian &
run_combo 7848 solo_p pinecone &
run_combo 7849 solo_s sawtooth &
wait
run_combo 7850 solo_h sapshaman &
run_combo 7851 solo_w hydro &
run_combo 7852 mix_all sapshaman hydro pinecone sawtooth &
wait
python3 - "$OUT" <<'PY'
import json, sys, os, glob
out = sys.argv[1]
rows = []
fails = 0
for d in sorted(glob.glob(os.path.join(out, "*/"))):
    name = os.path.basename(d.rstrip("/"))
    bots = []
    for f in sorted(glob.glob(os.path.join(d, "b*.json"))):
        try: bots.append(json.load(open(f)))
        except Exception as e: bots.append({"ok": False, "errors": [str(e)], "events": {}})
    if not bots:
        rows.append((name, 0, "no output", 0, 0, 0, 0, 0)); fails += 1; continue
    ok = all(b.get("ok") for b in bots)
    rr = bots[0].get("room_result", {})
    outcome = rr.get("run_outcome", rr.get("outcome", "?"))
    kills = sum(b.get("events", {}).get("kills", 0) for b in bots)
    downs = sum(b.get("events", {}).get("downed", 0) for b in bots)
    rescues = sum(b.get("events", {}).get("rescues_done", 0) for b in bots)
    wipes = sum(b.get("events", {}).get("wipe", 0) for b in bots)
    elapsed = rr.get("elapsed", 0)
    rows.append((name, len(bots), "ok" if ok else "FAIL " + str([b.get("errors") for b in bots if not b.get("ok")])[:120], outcome, kills, downs, rescues, wipes, elapsed))
    if not ok: fails += 1
    # 서버 로그의 스냅샷 크기 경고
    slog = open(os.path.join(d, "server.log"), errors="replace").read()
    if "MTU" in slog or "SCRIPT ERROR" in slog:
        rows[-1] = rows[-1] + ("server warnings",)
        fails += 1
lines = ["| 조합 | 인원 | 결과 | 런 결과(1=승) | 처치 | 다운 | 구조 | 전멸 | 마지막 방 초 |", "|---|---|---|---|---|---|---|---|---|"]
for r in rows:
    lines.append("| " + " | ".join(str(x) for x in r[:9]) + " |" + (" ⚠" if len(r) > 9 else ""))
md = "\n".join(lines)
print(md)
open(os.path.join(out, "party_matrix.md"), "w").write(md + "\n")
print(f"\nparty matrix: {fails} failures")
sys.exit(1 if fails else 0)
PY
